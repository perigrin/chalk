# ABOUTME: A self-recursive callee must GAP loudly, not inline forever.
# ABOUTME: Guards the GAP-not-miscompile invariant against a non-terminating compiler.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::ProgramRunner ();

# ---------------------------------------------------------------------------
# The inliner is the only direct-call mechanism today, so a self-recursive sub
# has no terminating lowering: _lower_call_direct inlines the callee, which
# contains the same Call, which inlines again. Measured before this guard
# existed: `Deep recursion on _lower_inlined_effects_then_value` followed by a
# hang — the compiler never returned (true exit 124 under `timeout 60`).
#
# A hang is a GAP-not-miscompile violation and is worse than a miscompile for a
# build system: a wrong answer can be caught by a gate, a compiler that never
# returns cannot. The contract is that an unsupported shape GAPs LOUDLY.
#
# This test is wrapped in alarm() because a regression here does not fail — it
# hangs, and an un-alarmed test would take the whole suite with it.
# ---------------------------------------------------------------------------

my $RECURSIVE = <<'PERL';
sub f { my $n = shift; $n <= 0 ? 0 : f($n-1) }
f(3)
PERL

my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
binmode $fh, ':utf8';
print $fh $RECURSIVE;
close $fh;

my $result;
my $timed_out = 0;

eval {
    local $SIG{ALRM} = sub { die "ALARM\n" };
    alarm 30;
    $result = Chalk::CodeGen::Harness::ProgramRunner->run_file($path);
    alarm 0;
    1;
} or do {
    alarm 0;
    $timed_out = 1 if $@ eq "ALARM\n";
};

ok(!$timed_out, 'lowering a self-recursive callee TERMINATES (does not hang)')
    or diag('the compiler did not return within 30s — the recursion guard is gone');

SKIP: {
    skip 'lowering hung; the assertions below cannot run', 2 if $timed_out;

    # Recursion is a GAP, not a guard: `sub fib` is ordinary Perl and MUST
    # compile eventually. It cannot today because inlining is the only call
    # mechanism, and a self-recursive callee cannot be inlined at any finite
    # depth -- which makes this a CORRECTNESS CEILING ON THE LANGUAGE, closed
    # by real `define` + `call` emission (F3), not a refusal to be preserved.
    #
    # TODO rather than an asserted GAP: asserting "does not compile" would go
    # RED the day recursion works, punishing the fix and training the next
    # reader to edit the test. As a TODO it reports a surprise success.
    #
    # The termination assertion above is NOT part of this and stays as-is: a
    # compiler that hangs is wrong however recursion is eventually handled.
    TODO: {
        local $TODO = 'recursion needs real define+call emission (F3); '
                    . 'inlining alone cannot express a self-recursive callee';

        is($result->{verdict}, 'PASS', 'a self-recursive callee compiles')
            or diag("skip reason was: " . ($result->{skip_reason} // '(undef)'));
    }
}

done_testing();
