# ABOUTME: Compiles a file AS ITSELF and compares stdout + exit status against perl.
# ABOUTME: The one standalone-executable contract; every file-scoring gate uses it.
package Chalk::CodeGen::Harness::ProgramRunner;

use 5.42.0;
use utf8;
no warnings 'experimental::class';

use File::Temp qw(tempfile);
use JSON::PP;

use Chalk::IR::Serialize::JSON ();
use Chalk::IR::Graph::TypedInvariant;
use Chalk::Target::LLVM ();
use Chalk::CodeGen::Pipeline;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

# This runner consumes ARBITRARY REAL FILES — that is its whole contract, and
# the reason it must filter by EXCLUSION rather than inclusion.
#
# It used to pass `package=main`, an INCLUSION filter, which emits only the
# packages it is told about. Since the file is handed over unmodified, this
# runner cannot know what packages it declares, so every one of them was
# dropped from the wire. A call into a dropped package then arrives with no
# resolved callee and therefore no return type, and GAPs at _require_repr as
# "reached LLVM backend with NO representation" — a message naming
# TypeInference when the cause is that the callee was never loaded.
#
# That was LIVE on the Phase-5 target set: t/base/lex.t declares `Someother`
# and `v10`, and t/cmd/subval.t goes through this same runner.
#
# A source scan for `^package` would not have fixed it. lex.t also creates the
# `xyz` and `foo::::::` namespaces via qualified SUB declarations
# (`sub xyz::foo {...}`) with no `package` statement anywhere, so a
# declaration-scanning fix would find two of its namespaces and miss two more.
#
# The list below is the producer's own dependency footprint plus perl's pragma
# modules — measured, not guessed: compiling a two-package program with no
# filter emits 17 infrastructure namespaces alongside the user's. Excluding
# them fails toward NOISE (an unanticipated dependency leaks into the wire,
# which is visible) rather than toward SILENCE (an unanticipated user package
# disappears, which is not). If a future producer dependency leaks, the fix is
# to add it here; nothing user-facing breaks in the meantime.
#
# Matching is by PREFIX, so a bare name here covers both the package itself and
# anything beneath it: `Carp` excludes Carp and Carp::Heavy alike. Do not write
# `Carp::` — that form leaves the bare `Carp` package itself in the wire.
my $PKG_EXCLUDE = join(',', map { "not_package=$_" } qw(
    SoN
    B
    JSON
    Carp
    Config
    Exporter
    DynaLoader
    List
    Scalar
    overload
    overloading
    warnings
    strict
    utf8
    bytes
    feature
));

# ---------------------------------------------------------------------------
# WHY THIS EXISTS, AND WHAT IT REPLACED
#
# Chalk compiles files to EXECUTABLES. The only honest question about a file is
# therefore: run it under perl, run the compiled form, do stdout AND exit status
# match? This class asks exactly that and nothing else.
#
# The predecessor (Mode1Runner) scored files on a WRAPPED contract: it rewrote
# the source to put the program body inside a synthetic `sub __main__`, stripped
# the compiler's `Int:`/`Str:` return-value epilogue from the output afterwards,
# and treated any nonzero lli exit as failure-to-lower. All three are FALSE
# POSITIVES against the goal:
#
#   - the wrap invents an entry point. Finding the entry point of a bare file is
#     part of the job, so a contract that supplies one cannot measure it.
#   - the epilogue is the CORPUS's return-value oracle for a lowered fragment.
#     A program's stdout is what the program printed; stripping a trailing line
#     that the program never emitted hides the difference.
#   - exit status is part of the contract, not a health check on the toolchain.
#     `die` must exit 255 and `exit 3` must exit 3; folding those into "did not
#     lower" makes a wrong exit status unobservable.
#
# The concrete cost of the old contract, measured: t/base/rs.t reported its
# first blocker as an explicit-filehandle `print`, which is a blocker of the
# WRAPPED graph. Compiled as itself, rs.t stops somewhere else entirely. The
# worklist was naming features that were not the next thing in the way.
#
# The wrapped machinery (Mode1Runner, MainWrap, EpilogueStrip) is deleted, not
# deprecated — a second contract that scores files is how the first one survived
# unnoticed. This is the only one.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# run_file($path) -> \%result
#
#   verdict      'PASS' | 'SKIP' | 'FAIL'
#   skip_reason  on SKIP: the named first blocker. On FAIL: the divergence.
#   lli_stdout   the compiled program's stdout    (defined on PASS/FAIL)
#   lli_exit     the compiled program's exit status
#   perl_stdout  perl's stdout   (the oracle)
#   perl_exit    perl's exit status
#
#   SKIP  the file did not compile. A LOUD COUNTED skip naming the first
#         unsupported construct — never a silent pass.
#   FAIL  it compiled, but stdout or exit status diverged from perl, or the
#         loaded graph violated the TypedInvariant. A real miscompile.
#   PASS  stdout AND exit status both match perl exactly.
# ---------------------------------------------------------------------------
sub run_file ($class, $path) {
    return { verdict => 'SKIP', skip_reason => "cannot read $path" } unless -r $path;

    my ($perl_stdout, $perl_exit) = _perl_oracle($path);
    my ($lli_stdout, $lli_exit, $err, $graph) = _compile_and_run($path);

    if (defined $err) {
        return {
            verdict => 'SKIP', skip_reason => $err,
            perl_stdout => $perl_stdout, perl_exit => $perl_exit,
        };
    }

    my %out = (
        lli_stdout => $lli_stdout, lli_exit    => $lli_exit,
        perl_stdout => $perl_stdout, perl_exit => $perl_exit,
    );

    # The loaded graph must satisfy the TypedInvariant. A program that prints
    # the right bytes off a malformed graph is not a pass.
    my $inv = eval { Chalk::IR::Graph::TypedInvariant->check($graph) }
        // { ok => 0, violations => [{ message => "died: $@" }] };
    unless ($inv->{ok}) {
        my $why = join('; ', map { $_->{message} } $inv->{violations}->@*);
        return { %out, verdict => 'FAIL',
                 skip_reason => "TypedInvariant violation: $why" };
    }

    return { %out, verdict => 'PASS' }
        if $lli_stdout eq $perl_stdout && $lli_exit == $perl_exit;

    return { %out, verdict => 'FAIL', skip_reason => sprintf(
        'behavior divergence: perl(exit=%d, %s) vs chalk(exit=%d, %s)',
        $perl_exit, _show($perl_stdout), $lli_exit, _show($lli_stdout)) };
}

# ---------------------------------------------------------------------------
# run_file_into_histogram(\%hist, $path) -> \%result
#
# run_file, plus: on a SKIP, increments $hist{$reason}. The histogram is a
# first-class output — a reason->count map so a whole-ring sweep reports WHY
# each file was skipped, not just how many. PASS/FAIL do not touch the map.
# ---------------------------------------------------------------------------
sub run_file_into_histogram ($class, $hist, $path) {
    my $result = $class->run_file($path);
    $hist->{ $result->{skip_reason} }++ if $result->{verdict} eq 'SKIP';
    return $result;
}

# _perl_oracle($path) -> ($stdout, $exit) — the ground truth.
sub _perl_oracle ($path) {
    my $out = qx($PERL $path 2>/dev/null);
    return ($out // '', $? >> 8);
}

# ---------------------------------------------------------------------------
# _compile_and_run($path) -> ($stdout, $exit, $err, $graph)
#
# The file is handed to the producer UNMODIFIED — shebang intact, no wrap — and
# lowered with program_mode => 1 so the return-value epilogue is never emitted.
# On any failure to compile returns (undef, undef, $reason, undef).
# ---------------------------------------------------------------------------
sub _compile_and_run ($path) {
    my ($efh, $etmp) = tempfile(SUFFIX => '.err', UNLINK => 1);
    close $efh;
    my $json = qx($PERL -I$SON -MO=SoN,json,$PKG_EXCLUDE $path 2>$etmp);
    my $producer_err = do { local (@ARGV, $/) = ($etmp); <> } // '';

    return (undef, undef, 'producer emitted no JSON', undef) unless $json =~ /\S/;
    my $data = eval { JSON::PP->new->decode($json) }
        or return (undef, undef, 'JSON decode failed', undef);

    # The entry point. A bare file's top level is main_root; whether the
    # producer walks it is exactly what this contract is here to measure, so a
    # missing entry graph is a named blocker, not a wrap-and-retry.
    unless ($data->{methods}{'main::__PROGRAM__'}
         // $data->{methods}{'main::__main__'}) {
        my $gap = _producer_gap_reason($producer_err);
        return (undef, undef, $gap
            // 'no entry graph: a bare file produced no top-level graph', undef);
    }

    # The entry unit, lowered through the ONE pipeline seam. program_mode rides
    # on the CALL, not on pipeline state (D6): this runner compiles a file AS
    # ITSELF, so the Int:/Str: return-value epilogue must never be emitted.
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'}
            or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };

    my ($units, $graphs, undef, $load_err) = Chalk::CodeGen::Pipeline->new
        ->run_detail($json, $select, program_mode => 1);
    return (undef, undef, $load_err, undef) if $load_err;

    # The two failure strings below are distinct on purpose: "did not load"
    # means the loader produced no entry graph at all, "has no Return" means it
    # loaded one with no exit. Collapsing them loses which half failed.
    my $g = $graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'}
        or return (undef, undef, 'entry graph did not load', undef);
    return (undef, undef, 'entry graph has no Return', $g) unless @$units;

    my $unit = $units->[0];
    return (undef, undef, "lower: $unit->{err}", $g) unless $unit->{ok};
    my $ll = $unit->{ll};

    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lfh, ':utf8';
    print $lfh $ll;
    close $lfh;
    my $out = qx($LLI $lltmp 2>/dev/null);
    return (undef, undef, "lli died on signal @{[ $? & 127 ]}", $g) if $? & 127;
    return ($out // '', $? >> 8, undef, $g);
}

# ---------------------------------------------------------------------------
# _producer_gap_reason($producer_stderr) -> $reason | undef
#
# Extract the named first-unsupported construct from a B::SoN skip line:
#   "B::SoN: skipped main::__PROGRAM__: GAP: <construct>"
#
# ONLY the entry graph's own line counts. The producer GAPs each sub
# independently and reports them in walk order, so the first GAP in stderr is
# routinely some other sub's: on t/base/rs.t, `main::test_bad_setting` GAPs on
# an if/else arm and is printed BEFORE `main::__PROGRAM__`'s own
# explicit-filehandle GAP. Adopting the first GAP names a feature that is not
# in this file's way — a plausible, specific, wrong worklist entry, which is
# worse than no entry. When the entry graph named no reason, say exactly that.
# ---------------------------------------------------------------------------
sub _producer_gap_reason ($stderr) {
    for my $line (split /\n/, $stderr) {
        return $1 if $line =~ /skipped\s+main::(?:__PROGRAM__|__main__):\s*(.+\S)/;
    }
    return;
}

# _show($s) — a one-line elision of a stdout blob, for divergence messages.
sub _show ($s) {
    $s //= '';
    $s =~ s/\n/\\n/g;
    return length($s) > 60 ? q{"} . substr($s, 0, 60) . q{..."} : qq{"$s"};
}

1;
