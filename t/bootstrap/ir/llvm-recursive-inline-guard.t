# ABOUTME: A self-recursive callee must GAP loudly, not inline forever.
# ABOUTME: Guards the GAP-not-miscompile invariant against a non-terminating compiler.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::CodeGen::Harness::Mode1Runner ();

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

my ($out, $err);
my $timed_out = 0;

eval {
    local $SIG{ALRM} = sub { die "ALARM\n" };
    alarm 30;
    ($out, $err) = Chalk::CodeGen::Harness::Mode1Runner::_lower_wrapped($RECURSIVE);
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

    ok(!defined $out, 'a self-recursive callee does not lower to a value')
        or diag("unexpectedly lowered to: $out");

    like($err, qr/GAP:/,
        'it GAPs loudly rather than failing silently or hanging')
        or diag("error was: " . ($err // '(undef)'));
}

done_testing();
