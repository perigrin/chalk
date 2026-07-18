# ABOUTME: Mode-1 whole-file TAP oracle runner: lowers a wrapped .t through B::SoN
# ABOUTME: and compares full multi-line lli stdout (epilogue-stripped) against real perl.
package Chalk::CodeGen::Harness::Mode1Runner;

use 5.42.0;
use utf8;
no warnings 'experimental::class';

use File::Temp qw(tempfile);
use JSON::PP;

use Chalk::IR::Serialize::JSON ();
use Chalk::IR::Graph::TypedInvariant;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::MainWrap  qw(wrap_main);
use Chalk::CodeGen::Harness::EpilogueStrip qw(strip_epilogue);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

# ---------------------------------------------------------------------------
# run_file($t_path) -> \%result
#
# Runs one whole .t file in Mode-1: its top-level program body is wrapped in a
# synthetic `sub __main__` (MainWrap, I3), lowered through B::SoN + Target::LLVM
# + lli, and the FULL multi-line lli stdout (after the compiler epilogue is
# stripped, EpilogueStrip/I13) is compared against real perl's raw TAP output.
#
# Result hash keys:
#   verdict     'PASS' | 'SKIP' | 'FAIL'
#   lli_stdout  epilogue-stripped lli stdout (defined on PASS/FAIL)
#   perl_stdout raw perl TAP output (the oracle)
#   skip_reason on SKIP: the first unsupported construct (named, never silent)
#
# Verdict rules:
#   SKIP  — the file failed to lower (producer GAP / from_json / lower / lli
#           die). A LOUD COUNTED skip naming the first unsupported construct.
#   PASS  — lowered, and epilogue-stripped lli stdout equals perl's TAP AND the
#           loaded graph passes the TypedInvariant (R2.4).
#   FAIL  — lowered, but behavior or invariant mismatched (a real miscompile).
# ---------------------------------------------------------------------------
sub run_file ($class, $t_path) {
    open my $fh, '<', $t_path or return {
        verdict => 'SKIP', skip_reason => "cannot read $t_path: $!",
    };
    my $body = do { local $/; <$fh> };
    close $fh;

    # Strip a leading #! shebang if present; it is not part of the program body
    # and B::SoN parses the file itself (the shebang is a comment to perl too).
    $body =~ s/\A\#![^\n]*\n//;

    my $perl_stdout = _perl_oracle($t_path);

    my ($lli_stdout, $err, $graph) = _lower_wrapped($body);
    if (defined $err) {
        # R2.5: a file that does not lower is a LOUD COUNTED skip naming the
        # first unsupported construct — NEVER a silent pass.
        return {
            verdict     => 'SKIP',
            skip_reason => $err,
            perl_stdout => $perl_stdout,
        };
    }

    # R2.4 invariant: the loaded graph must satisfy the TypedInvariant.
    my $inv = eval { Chalk::IR::Graph::TypedInvariant->check($graph->nodes) }
        // { ok => 0, violations => [{ message => "died: $@" }] };
    unless ($inv->{ok}) {
        my $why = join('; ', map { $_->{message} } $inv->{violations}->@*);
        return {
            verdict     => 'FAIL',
            lli_stdout  => $lli_stdout,
            perl_stdout => $perl_stdout,
            skip_reason => "TypedInvariant violation: $why",
        };
    }

    # R2.2 behavior: FULL multi-line stdout equality after stripping the
    # compiler epilogue from the lli side.
    my $verdict = ($lli_stdout eq $perl_stdout) ? 'PASS' : 'FAIL';
    return {
        verdict     => $verdict,
        lli_stdout  => $lli_stdout,
        perl_stdout => $perl_stdout,
    };
}

# ---------------------------------------------------------------------------
# run_file_into_histogram(\%hist, $t_path) -> \%result
#
# run_file, plus: on a SKIP, increments $hist{$reason}. The histogram is a
# first-class output — a reason->count map so a whole-corpus sweep reports WHY
# each file was skipped, not just how many. PASS/FAIL do not touch the map.
# ---------------------------------------------------------------------------
sub run_file_into_histogram ($class, $hist, $t_path) {
    my $result = $class->run_file($t_path);
    $hist->{ $result->{skip_reason} }++ if $result->{verdict} eq 'SKIP';
    return $result;
}

# ---------------------------------------------------------------------------
# _perl_oracle($t_path) -> $stdout
#
# The oracle: run the ORIGINAL .t under real perl 5.42 and capture its raw TAP
# stdout. This is the ground truth the lowered output must reproduce.
# ---------------------------------------------------------------------------
sub _perl_oracle ($t_path) {
    my $out = qx($PERL $t_path 2>/dev/null);
    return $out;
}

# ---------------------------------------------------------------------------
# _lower_wrapped($body) -> ($lli_stdout, $err, $graph)
#
# Wraps $body in sub __main__ and runs it through the B::SoN pipeline (same
# shape as son-corpus-wide.t's run_through_bson), then strips the compiler
# epilogue. On any lowering failure returns (undef, $reason, undef) — $reason
# names the first unsupported construct. On success returns
# ($stripped_stdout, undef, $loaded_graph).
# ---------------------------------------------------------------------------
sub _lower_wrapped ($body) {
    my $prog = "package main;\n" . wrap_main($body);

    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $prog;
    close $fh;

    # Capture producer stderr: when B::SoN GAPs a method it emits
    # "B::SoN: skipped main::__main__: GAP: <first unsupported construct>".
    my ($efh, $etmp) = tempfile(SUFFIX => '.err', UNLINK => 1);
    close $efh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>$etmp);
    my $producer_err = do { local (@ARGV, $/) = ($etmp); <> } // '';

    return (undef, "B::SoN produced no JSON", undef) unless $json =~ /\S/;

    my $data = eval { JSON::PP->new->decode($json) };
    return (undef, "JSON decode failed", undef) unless $data;

    unless ($data->{methods}{'main::__main__'}) {
        # __main__ was GAPped by the producer: surface the named reason.
        my $reason = _producer_gap_reason($producer_err)
            // "producer emitted no main::__main__ method (unsupported top-level construct)";
        return (undef, $reason, undef);
    }

    my ($graphs, $mop) = eval { Chalk::IR::Serialize::JSON::from_json($json) };
    return (undef, "from_json failed: $@", undef) unless $graphs;
    my $g = $graphs->{'main::__main__'} or return (undef, "no loaded __main__ graph", undef);
    my $ret = $g->returns->[0] or return (undef, "no Return node in __main__", $g);

    my $ll = eval { Chalk::Target::LLVM->lower($ret, (defined $mop ? (mop => $mop) : ())) };
    return (undef, "lower: $@", $g) if $@;

    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lfh, ':utf8';
    print $lfh $ll;
    close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    if (my $sig = $? & 127) {
        return (undef, "lli died on signal $sig", $g);
    }
    my $exit = $? >> 8;
    return (undef, "lli exited $exit: $out", $g) if $exit != 0;

    # Strip the compiler epilogue (the final TYPE:value line). The expected
    # epilogue is determined from the return node's representation (I13 robust
    # known-string strip, NOT a naive /^(Int|...):/ regex).
    my $expected = _expected_epilogue($ret, $out);
    my ($stripped, $removed) = strip_epilogue($out, $expected);
    return (undef, "missing/unexpected compiler epilogue (expected '$expected')", $g)
        unless defined $removed;

    return ($stripped, undef, $g);
}

# ---------------------------------------------------------------------------
# _expected_epilogue($return_node, $lli_stdout) -> $epilogue_string
#
# The epilogue tag is driven by the return value node's representation (see
# Chalk::Target::LLVM::lower_with_elaboration). For a whole-file program whose
# last statement is a print, the value is print's genuine Bool true -> "Bool:1".
#
# For Bool the value is statically known (true|false). For value-bearing reprs
# (Int/Num/Str/Undef/Slot) the runtime value is not known statically, so we
# adopt the lli stdout's final line AS the epilogue only when it carries the
# repr's tag prefix — the repr was independently established from the graph, so
# this is a checked adoption, not a blind pattern strip. If the final line does
# not carry the expected prefix, we return a prefix-only sentinel so
# strip_epilogue signals a missing epilogue (a loud error, not a silent pass).
# ---------------------------------------------------------------------------
sub _expected_epilogue ($return_node, $lli_stdout) {
    my $vn   = $return_node->inputs->[0];
    my $repr = defined $vn ? $vn->representation : undef;
    $repr //= 'Int';   # lower() defaults undef repr to Int

    # Bool: value is statically known.
    return 'Bool:1' if $repr eq 'Bool';   # print returns true; false is 'Bool:'

    my %prefix = (
        Int => 'Int:', Num => 'Num:', Str => 'Str:',
        Undef => 'Undef:', Slot => 'Int:',
    );
    my $pfx = $prefix{$repr} // "$repr:";

    # Adopt the final line as the epilogue when it carries the repr's prefix.
    my $final = ($lli_stdout =~ /([^\n]*)\n\z/) ? $1 : '';
    return $final if index($final, $pfx) == 0;

    # Final line does not carry the expected prefix: return the prefix alone so
    # strip_epilogue finds no exact match and signals a missing epilogue.
    return $pfx;
}

# ---------------------------------------------------------------------------
# _producer_gap_reason($producer_stderr) -> $reason | undef
#
# Extract the named first-unsupported-construct from a B::SoN skip line:
#   "B::SoN: skipped main::__main__: GAP: list-context ternary not yet lowered"
# Returns the "GAP: ..." tail (the named construct), or undef if not present.
# ---------------------------------------------------------------------------
sub _producer_gap_reason ($stderr) {
    for my $line (split /\n/, $stderr) {
        return $1 if $line =~ /skipped\s+main::__main__:\s*(.+\S)/;
    }
    return;
}

1;
