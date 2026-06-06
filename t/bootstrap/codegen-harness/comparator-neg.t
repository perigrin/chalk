# ABOUTME: Adversarial / false-green guard tests for Chalk::CodeGen::Harness::Comparator.
# ABOUTME: Guards against miscompile-laundered-as-gap, gap-as-pass, unobserved-axis false greens.
use 5.42.0;
use utf8;

use Test2::V0;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::Comparator;
use constant Comparator => 'Chalk::CodeGen::Harness::Comparator';

# -------------------------------------------------------------------------
# Local test-fixture record — same field/accessor contract as real BehaviorRecord.
# -------------------------------------------------------------------------
package t::BehaviorRecord {
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use feature 'class';

    class t::BehaviorRecord {
        field $return_values     :param :reader = [];
        field $wantarray_context :param :reader = 'scalar';
        field $stdout            :param :reader = '';
        field $stderr            :param :reader = '';
        field $exception         :param :reader = undef;
        field $object_state      :param :reader = {};
        field $hash_order_policy :param :reader = 'sorted';
        field $fp_tolerance      :param :reader = 1e-9;
        field $dualvar_policy    :param :reader = 'string';
        field $aliasing_topology :param :reader = 'none';
    }
}

package main;

# =========================================================================
# N1: Unobserved-axis false green — STDERR warning differs
#     Two records AGREE on return_values+stdout but DIFFER on stderr.
#     Must yield MISCOMPILE, not PASS.
# =========================================================================
{
    my $s = t::BehaviorRecord->new(
        return_values => [1],
        stdout        => 'ok',
        stderr        => '',
    );
    my $p = t::BehaviorRecord->new(
        return_values => [1],
        stdout        => 'ok',
        stderr        => 'Use of uninitialized value in print',  # extra warning
    );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS', 'N1a: STDERR warning diff must NOT verdict PASS' );
    is(   $r->{verdict}, 'MISCOMPILE', 'N1a: STDERR warning diff => MISCOMPILE' );
}

# =========================================================================
# N2: Unobserved-axis false green — wantarray context differs
# =========================================================================
{
    my $s = t::BehaviorRecord->new(
        return_values     => [1],
        wantarray_context => 'scalar',
    );
    my $p = t::BehaviorRecord->new(
        return_values     => [1],
        wantarray_context => 'list',   # context differs
    );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS', 'N2: wantarray context diff must NOT verdict PASS' );
    is(   $r->{verdict}, 'MISCOMPILE', 'N2: wantarray context diff => MISCOMPILE' );
}

# =========================================================================
# N3: Unobserved-axis false green — dualvar num-vs-str face differs
#     Records agree on return_values content seen one way but differ another.
# =========================================================================
{
    # dualvar_policy 'numeric': "3.0" vs 3 — both stringify to "3" but
    # numerically one is a string "3.0" which may parse differently.
    # We model this as S returns "3.0" (string) and P returns 3 (numeric).
    # Under numeric policy these ARE the same. Under string policy they differ.
    # Test the mismatch case: dualvar_policy 'string', "3.0" vs "3"
    my $s = t::BehaviorRecord->new(
        return_values  => ["3.0"],
        dualvar_policy => 'string',
    );
    my $p = t::BehaviorRecord->new(
        return_values  => ["3"],      # different string face
        dualvar_policy => 'string',
    );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS', 'N3: dualvar string-face diff must NOT verdict PASS' );
    is(   $r->{verdict}, 'MISCOMPILE', 'N3: dualvar string-face diff => MISCOMPILE' );
}

# =========================================================================
# N4: Unobserved-axis false green — FP beyond tolerance
#     return_values numerically close but outside tolerance boundary.
#     Uses dualvar_policy 'numeric' so FP tolerance is applied.
# =========================================================================
{
    my $tol  = 0.001;
    my $diff = 0.002;   # outside tolerance
    my $s = t::BehaviorRecord->new( return_values  => [1.0],
                                    fp_tolerance   => $tol,
                                    dualvar_policy => 'numeric' );
    my $p = t::BehaviorRecord->new( return_values  => [1.0 + $diff],
                                    fp_tolerance   => $tol,
                                    dualvar_policy => 'numeric' );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS', 'N4: FP outside tolerance must NOT verdict PASS' );
    is(   $r->{verdict}, 'MISCOMPILE', 'N4: FP outside tolerance => MISCOMPILE' );
}

# =========================================================================
# N4b: FP boundary — just inside tolerance => PASS (numeric policy)
# =========================================================================
{
    my $tol  = 0.001;
    my $diff = 0.0009;  # inside tolerance
    my $s = t::BehaviorRecord->new( return_values  => [1.0],
                                    fp_tolerance   => $tol,
                                    dualvar_policy => 'numeric' );
    my $p = t::BehaviorRecord->new( return_values  => [1.0 + $diff],
                                    fp_tolerance   => $tol,
                                    dualvar_policy => 'numeric' );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    is( $r->{verdict}, 'PASS', 'N4b: FP just inside tolerance => PASS' );
}

# =========================================================================
# N4c: FP outside tolerance — oracle token 'numeric-first' (production path)
#      The oracle (RunUnderPerl) always emits dualvar_policy='numeric-first'.
#      Confirms that 'numeric-first' also applies FP tolerance (not string-eq).
# =========================================================================
{
    my $tol  = 0.001;
    my $diff = 0.002;   # outside tolerance
    my $s = t::BehaviorRecord->new( return_values  => [1.0],
                                    fp_tolerance   => $tol,
                                    dualvar_policy => 'numeric-first' );
    my $p = t::BehaviorRecord->new( return_values  => [1.0 + $diff],
                                    fp_tolerance   => $tol,
                                    dualvar_policy => 'numeric-first' );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS',     'N4c: FP outside tolerance (numeric-first) must NOT verdict PASS' );
    is(   $r->{verdict}, 'MISCOMPILE','N4c: FP outside tolerance (numeric-first) => MISCOMPILE' );
}

# =========================================================================
# N4d: FP boundary — just inside tolerance => PASS (oracle token 'numeric-first')
# =========================================================================
{
    my $tol  = 0.001;
    my $diff = 0.0009;  # inside tolerance
    my $s = t::BehaviorRecord->new( return_values  => [1.0],
                                    fp_tolerance   => $tol,
                                    dualvar_policy => 'numeric-first' );
    my $p = t::BehaviorRecord->new( return_values  => [1.0 + $diff],
                                    fp_tolerance   => $tol,
                                    dualvar_policy => 'numeric-first' );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    is( $r->{verdict}, 'PASS', 'N4d: FP just inside tolerance (numeric-first) => PASS' );
}

# =========================================================================
# N5: Unobserved-axis false green — hash-identity (object_state) differs
#     return_values and stdout agree, but object_state differs.
# =========================================================================
{
    my $s = t::BehaviorRecord->new(
        return_values => [1],
        object_state  => { x => 10, y => 20 },
    );
    my $p = t::BehaviorRecord->new(
        return_values => [1],
        object_state  => { x => 10, y => 99 },  # y differs
    );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS', 'N5: object_state diff must NOT verdict PASS' );
    is(   $r->{verdict}, 'MISCOMPILE', 'N5: object_state diff => MISCOMPILE' );
}

# =========================================================================
# N6: Miscompile laundered as gap
#     P emitted COMPLETE code (no unsupported, every construct emitted)
#     but diverged from S. Must be MISCOMPILE, never GAP.
# =========================================================================
{
    my $s = t::BehaviorRecord->new( return_values => [100] );
    my $p = t::BehaviorRecord->new( return_values => [999] );  # diverges
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'GAP',  'N6: complete-but-wrong must NOT verdict GAP' );
    is(   $r->{verdict}, 'MISCOMPILE', 'N6: complete-but-wrong => MISCOMPILE not GAP' );
}

# =========================================================================
# N7: Gap misclassified as pass
#     P failed to emit (unsupported marker). Even if partial output
#     coincidentally matches S on observed axes, must verdict GAP not PASS.
# =========================================================================
{
    # S and P match on observed axes, but emission was marked unsupported.
    my $s = t::BehaviorRecord->new( return_values => [42] );
    my $p = t::BehaviorRecord->new( return_values => [42] );  # coincidental match
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 1 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS', 'N7: marked_unsupported must NOT verdict PASS' );
    is(   $r->{verdict}, 'GAP', 'N7: marked_unsupported => GAP despite coincidental match' );
}

# =========================================================================
# N7b: Gap misclassified as pass — emitted_for_every_construct false
# =========================================================================
{
    my $s = t::BehaviorRecord->new( return_values => [1] );
    my $p = t::BehaviorRecord->new( return_values => [1] );  # coincidental match
    my $meta = { emitted_for_every_construct => 0, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS', 'N7b: incomplete emission must NOT verdict PASS' );
    is(   $r->{verdict}, 'GAP', 'N7b: incomplete emission => GAP despite match' );
}

# =========================================================================
# N8: Empty-record collusion
#     Comparing two empty/degenerate records must NOT verdict PASS.
#     Guards against "nothing was captured, nothing differs, so pass."
# =========================================================================
{
    # Both records have empty return_values and empty everything
    my $s = t::BehaviorRecord->new(
        return_values => [],
        stdout        => '',
        stderr        => '',
        exception     => undef,
        object_state  => {},
    );
    my $p = t::BehaviorRecord->new(
        return_values => [],
        stdout        => '',
        stderr        => '',
        exception     => undef,
        object_state  => {},
    );
    # Complete emission but no actual behavior was observed
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $r = Comparator->verdict($s, $p, $meta);
    isnt( $r->{verdict}, 'PASS', 'N8: empty-record collusion must NOT verdict PASS' );
}

done_testing;
