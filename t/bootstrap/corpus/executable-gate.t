# ABOUTME: The PRODUCT gate: compile a file AS ITSELF and diff stdout + exit status
# ABOUTME: against perl. Measures "does this become a runnable program", not a value.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON ();
use Chalk::Target::LLVM ();

# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# Chalk is a compiler for generating EXECUTABLES. Every other gate measures
# something adjacent to that:
#   - son-corpus-wide.t asks "does this lowered FRAGMENT produce the right
#     VALUE?" (triple contract over a wrapped sub).
#   - the ring worklist asks "how far into this .t file do we get?"
# Neither asks "does this FILE become a PROGRAM that RUNS?" — so when the
# question came up, a proxy metric filled the vacuum and ranked the work wrong.
#
# This gate asks the product question directly and only:
#     perl  FILE -> (stdout, exit status)
#     chalk FILE -> (stdout, exit status)
#     PASS iff both match EXACTLY.
#
# Deliberately NOT tolerated here, because each is a way of not being a compiler:
#   - the `sub __main__` source-text wrap (Mode1Runner::_lower_wrapped). A file
#     must compile AS ITSELF; rewriting the source to find an entry point is the
#     thing we are trying to stop doing.
#   - the `Int:`/`Str:` epilogue. Mode1Runner STRIPS it after the fact for the
#     corpus's return-value oracle; this gate instead lowers with
#     `program_mode => 1` so the epilogue is never EMITTED — a real program's
#     stdout is what the program printed, full stop.
#   - nonzero exit as "lowering failed". Mode1Runner treats any nonzero lli exit
#     as an error (Mode1Runner.pm:167). Exit status is part of the CONTRACT:
#     `die` must exit 255, `exit 3` must exit 3.
#
# A program that cannot yet compile is reported BLOCKED with a named reason,
# not silently skipped — the number below is an honest roadmap, not a vanity
# metric. Raise the floor as more programs pass.
# ---------------------------------------------------------------------------

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl 5.42 not found at $PERL"      unless -x $PERL;
plan skip_all => "perl5-son not found at $SON"       unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"             unless -x $LLI;

# Programs whose ENTIRE observable contract is (stdout, exit status). Start
# here: if a hello-world does not round-trip, nothing larger can.
my @PROGRAMS = (
    { name => 'hello',        src => qq{print "hi\\n";\n} },
    { name => 'two-prints',   src => qq{print "a\\n"; print "b\\n";\n} },
    { name => 'arith-print',  src => qq{my \$x = 2 + 3; print "\$x\\n";\n} },
    { name => 'die-aborts',   src => qq{print "before\\n"; die "boom\\n";\n} },
    { name => 'explicit-exit',src => qq{print "bye\\n"; exit 3;\n} },
);

# run_perl($path) -> (stdout, exit)
sub run_perl ($path) {
    my $out = qx($PERL $path 2>/dev/null);
    return ($out // '', $? >> 8);
}

# run_chalk($path) -> (stdout, exit, undef) | (undef, undef, $blocker)
# Compiles the file AS ITSELF — no wrap, no epilogue strip, no exit rewriting.
sub run_chalk ($path) {
    my ($efh, $etmp) = tempfile(SUFFIX => '.err', UNLINK => 1);
    close $efh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $path 2>$etmp);
    my $perr = do { local (@ARGV, $/) = ($etmp); <> } // '';

    return (undef, undef, 'producer emitted no JSON') unless $json =~ /\S/;
    my $data = eval { JSON::PP->new->decode($json) }
        or return (undef, undef, 'JSON decode failed');

    # The entry point. A bare file's top level is main_root, which B::SoN does
    # not walk today — so this is where the bare-file protocol shows up as a
    # measured number rather than an argument.
    my $entry = $data->{methods}{'main::__PROGRAM__'}
             // $data->{methods}{'main::__main__'};
    unless ($entry) {
        my ($gap) = $perr =~ /GAP: ([^\n]+)/;
        return (undef, undef, $gap
            // 'no entry graph: a bare file produces no top-level graph (main_root is not walked)');
    }

    my ($graphs, $mop) = eval { Chalk::IR::Serialize::JSON::from_json($json) };
    return (undef, undef, "from_json failed: $@") unless $graphs;
    my $g = $graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'}
        or return (undef, undef, 'entry graph did not load');
    my $ret = $g->returns->[0] or return (undef, undef, 'entry graph has no Return');

    my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1, (defined $mop ? (mop => $mop) : ())) };
    return (undef, undef, "lower: $@") if $@;

    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lfh, ':utf8';
    print $lfh $ll;
    close $lfh;
    my $out = qx($LLI $lltmp 2>/dev/null);
    return (undef, undef, 'lli died on a signal') if $? & 127;
    return ($out // '', $? >> 8, undef);
}

my ($passing, @report) = (0);

for my $p (@PROGRAMS) {
    my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $p->{src};
    close $fh;

    my ($p_out, $p_exit)          = run_perl($path);
    my ($c_out, $c_exit, $blocker) = run_chalk($path);

    if (defined $blocker) {
        chomp $blocker;
        push @report, sprintf('  %-14s BLOCKED  %s', $p->{name}, $blocker);
        ok(1, "$p->{name}: blocked, reason named (no silent failure)");
        next;
    }

    my $same = ($c_out eq $p_out) && ($c_exit == $p_exit);
    $passing++ if $same;
    push @report, $same
        ? sprintf('  %-14s PASS', $p->{name})
        : sprintf('  %-14s DIFF     perl(exit=%d, %s) vs chalk(exit=%d, %s)',
              $p->{name}, $p_exit, _show($p_out), $c_exit, _show($c_out));
    ok(1, "$p->{name}: compared against the perl oracle");
}

sub _show ($s) {
    $s //= '';
    $s =~ s/\n/\\n/g;
    return length($s) > 40 ? q{"} . substr($s, 0, 40) . q{..."} : qq{"$s"};
}

diag('');
diag('=== EXECUTABLE GATE: does this FILE become a PROGRAM that runs? ===');
diag($_) for @report;
diag(sprintf('  passing: %d/%d', $passing, scalar @PROGRAMS));
diag('');
diag('  A program PASSES only when stdout AND exit status both match perl');
diag('  exactly: no source-text wrap, no epilogue strip, no exit-code');
diag('  tolerance. Raise the floor below as programs start passing.');

# The floor. It starts where the capability actually is, and may only rise.
cmp_ok($passing, '>=', 4,
    'executable-gate floor (4; hello/two-prints/arith-print/die-aborts now compile '
  . 'and run as standalone programs. The Int/Str/Bool/Undef return-value type-tag '
  . 'epilogue -- needed only so the corpus harness can read back a fragment\'s '
  . 'return value -- is no longer being printed as if it were program output: '
  . 'lower() takes program_mode => 1 to suppress it at emission time (defaults '
  . 'off; the corpus reads the tag as its oracle). The remaining program, '
  . 'explicit-exit, is blocked on dispatch_kind: "builtin" name: "exit" -- an '
  . 'unlowered builtin Call, not an epilogue or entry-protocol issue. Raise this '
  . 'as more programs pass.)');

done_testing();
