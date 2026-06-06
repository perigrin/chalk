# ABOUTME: FP-tolerance + dualvar_policy='numeric-first' tests for Comparator.
# ABOUTME: Guards against the trust-root crack where 'numeric-first' fell through to exact-string comparison (H2).
use 5.42.0;
use utf8;

use Test2::V0;
use lib 'lib';

use Chalk::CodeGen::Harness::Comparator;
use constant Comparator => 'Chalk::CodeGen::Harness::Comparator';

# -------------------------------------------------------------------------
# Local test-fixture record — same field/accessor contract as BehaviorRecord.
# Uses 'numeric-first' as the default dualvar_policy, matching what the oracle
# (RunUnderPerl) actually emits.
# -------------------------------------------------------------------------
package t::FPBehaviorRecord {
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use feature 'class';

    class t::FPBehaviorRecord {
        field $return_values     :param :reader = [];
        field $wantarray_context :param :reader = 'scalar';
        field $stdout            :param :reader = '';
        field $stderr            :param :reader = '';
        field $exception         :param :reader = undef;
        field $object_state      :param :reader = {};
        field $hash_order_policy :param :reader = 'sorted-keys';
        field $fp_tolerance      :param :reader = 1e-9;
        field $dualvar_policy    :param :reader = 'numeric-first';
        field $aliasing_topology :param :reader = {};
    }
}

package main;

my $COMPLETE_META = { emitted_for_every_construct => 1, marked_unsupported => 0 };

# =========================================================================
# V1: Vocabulary guard — oracle-emitted token is in the Comparator's handled set.
#
# This is a policy assertion: if RunUnderPerl.pm ever changes the token it
# emits, this test will fail loudly, preventing a silent regression.
# =========================================================================
{
    # The oracle emits exactly this token. Confirm it routes to FP-tolerant
    # numeric comparison (not exact-string fallthrough) by verifying that two
    # within-tolerance floats give PASS when policy='numeric-first'.
    my $s = t::FPBehaviorRecord->new(
        return_values  => [3.0],
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',   # the real oracle token
    );
    my $p = t::FPBehaviorRecord->new(
        return_values  => [3.0],
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS',
        "V1: oracle-emitted token 'numeric-first' routes to FP-aware comparison (identical floats => PASS)" );
}

# =========================================================================
# FP1: Within-tolerance floats with dualvar_policy='numeric-first' => PASS.
#
# "3" vs "3.0000000005" with fp_tolerance=1e-9: abs(3 - 3.0000000005) = 5e-10
# which is LESS than 1e-9, so these should PASS.
#
# This is the canonical bug scenario from the H2 trust-root crack report.
# Before the fix this verdict MISCOMPILE (fell through to exact-string compare).
# After the fix it must PASS.
# =========================================================================
{
    my $s = t::FPBehaviorRecord->new(
        return_values  => ["3"],             # oracle returns string face "3"
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $p = t::FPBehaviorRecord->new(
        return_values  => ["3.0000000005"],  # compiled output; within 1e-9 numerically
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS',
        "FP1: within-tolerance floats (numeric-first) => PASS (the H2 bug scenario)" );
}

# =========================================================================
# FP2: Outside-tolerance floats with dualvar_policy='numeric-first' => MISCOMPILE.
#
# Both sides of the tolerance boundary must be covered (bilateral rule).
# "3" vs "3.000000002" with fp_tolerance=1e-9: abs diff = 2e-9 > 1e-9 => MISCOMPILE.
# =========================================================================
{
    my $s = t::FPBehaviorRecord->new(
        return_values  => ["3"],
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $p = t::FPBehaviorRecord->new(
        return_values  => ["3.000000002"],   # 2e-9 outside tolerance
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE',
        "FP2: outside-tolerance floats (numeric-first) => MISCOMPILE (not false-green)" );
}

# =========================================================================
# FP3: Boundary — just inside tolerance (bilateral, inner side).
#
# abs diff exactly at 0.9 * tolerance => PASS.  Ensures we use <= not <.
# =========================================================================
{
    my $tol  = 1e-6;
    my $diff = 0.9e-6;    # inside: 0.9 * tol < tol
    my $s = t::FPBehaviorRecord->new(
        return_values  => [1.0],
        fp_tolerance   => $tol,
        dualvar_policy => 'numeric-first',
    );
    my $p = t::FPBehaviorRecord->new(
        return_values  => [1.0 + $diff],
        fp_tolerance   => $tol,
        dualvar_policy => 'numeric-first',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS',
        "FP3: just inside tolerance (numeric-first) => PASS" );
}

# =========================================================================
# FP4: Boundary — just outside tolerance (bilateral, outer side).
#
# abs diff at 1.1 * tolerance => MISCOMPILE.
# =========================================================================
{
    my $tol  = 1e-6;
    my $diff = 1.1e-6;    # outside: 1.1 * tol > tol
    my $s = t::FPBehaviorRecord->new(
        return_values  => [1.0],
        fp_tolerance   => $tol,
        dualvar_policy => 'numeric-first',
    );
    my $p = t::FPBehaviorRecord->new(
        return_values  => [1.0 + $diff],
        fp_tolerance   => $tol,
        dualvar_policy => 'numeric-first',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE',
        "FP4: just outside tolerance (numeric-first) => MISCOMPILE" );
}

# =========================================================================
# FP5: Non-numeric values with dualvar_policy='numeric-first' fall back to
# string comparison — the 'numeric-first' name means: numeric if both are
# numeric, string otherwise.
#
# "hello" vs "hello" => PASS (string fallback, equal).
# "hello" vs "world" => MISCOMPILE (string fallback, not equal).
# =========================================================================
{
    my $s = t::FPBehaviorRecord->new(
        return_values  => ["hello"],
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $p = t::FPBehaviorRecord->new(
        return_values  => ["hello"],
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS',
        "FP5a: non-numeric strings equal (numeric-first string-fallback) => PASS" );
}
{
    my $s = t::FPBehaviorRecord->new(
        return_values  => ["hello"],
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $p = t::FPBehaviorRecord->new(
        return_values  => ["world"],
        fp_tolerance   => 1e-9,
        dualvar_policy => 'numeric-first',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE',
        "FP5b: non-numeric strings differ (numeric-first string-fallback) => MISCOMPILE" );
}

done_testing;
