# ABOUTME: Per-axis normalization policy tests for Chalk::CodeGen::Harness::Comparator.
# ABOUTME: Each axis (FP tolerance, hash-order, dualvar, exception, wantarray, stderr) tested independently.
use 5.42.0;
use utf8;

use Test2::V0;
use lib 'lib';

use Chalk::CodeGen::Harness::Comparator;
use constant Comparator => 'Chalk::CodeGen::Harness::Comparator';

# -------------------------------------------------------------------------
# Local test-fixture record — same contract as the real BehaviorRecord.
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

# Complete-emission meta — we test axis logic, not the gap rule here.
my $COMPLETE_META = { emitted_for_every_construct => 1, marked_unsupported => 0 };

# =========================================================================
# Axis: FP tolerance (numeric dualvar_policy — tolerance applies)
# =========================================================================
{
    # Two floats within tolerance => PASS (numeric policy, tolerance 1e-6)
    my $s = t::BehaviorRecord->new( return_values => [1.0000000001], fp_tolerance => 1e-6,
                                    dualvar_policy => 'numeric' );
    my $p = t::BehaviorRecord->new( return_values => [1.0000000002], fp_tolerance => 1e-6,
                                    dualvar_policy => 'numeric' );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS', 'FP within tolerance (numeric policy) => PASS' );
}
{
    # Two floats outside tolerance => MISCOMPILE (numeric policy)
    my $s = t::BehaviorRecord->new( return_values => [1.0], fp_tolerance => 1e-9,
                                    dualvar_policy => 'numeric' );
    my $p = t::BehaviorRecord->new( return_values => [2.0], fp_tolerance => 1e-9,
                                    dualvar_policy => 'numeric' );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'FP outside tolerance (numeric policy) => MISCOMPILE' );
}

# =========================================================================
# Axis: FP tolerance boundary (just inside vs just outside, numeric policy)
# =========================================================================
{
    my $tol = 0.001;
    # Just inside: diff = 0.0009 < 0.001
    my $s_in = t::BehaviorRecord->new( return_values => [1.0000], fp_tolerance => $tol,
                                       dualvar_policy => 'numeric' );
    my $p_in = t::BehaviorRecord->new( return_values => [1.0009], fp_tolerance => $tol,
                                       dualvar_policy => 'numeric' );
    my $r_in = Comparator->verdict($s_in, $p_in, $COMPLETE_META);
    is( $r_in->{verdict}, 'PASS', 'FP just inside tolerance => PASS' );

    # Just outside: diff = 0.0011 > 0.001
    my $s_out = t::BehaviorRecord->new( return_values => [1.0000], fp_tolerance => $tol,
                                        dualvar_policy => 'numeric' );
    my $p_out = t::BehaviorRecord->new( return_values => [1.0011], fp_tolerance => $tol,
                                        dualvar_policy => 'numeric' );
    my $r_out = Comparator->verdict($s_out, $p_out, $COMPLETE_META);
    is( $r_out->{verdict}, 'MISCOMPILE', 'FP just outside tolerance => MISCOMPILE' );
}

# =========================================================================
# Axis: hash-order normalization
# =========================================================================
{
    # object_state hashes with same key/value pairs but different insertion order => PASS
    # (hash_order_policy 'sorted' means we compare sorted keys)
    my $s = t::BehaviorRecord->new(
        object_state      => { a => 1, b => 2, c => 3 },
        hash_order_policy => 'sorted',
    );
    my $p = t::BehaviorRecord->new(
        object_state      => { c => 3, a => 1, b => 2 },  # same content, different source order
        hash_order_policy => 'sorted',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS', 'hash_order_policy sorted: same content different order => PASS' );
}
{
    # Different values => MISCOMPILE regardless of policy
    my $s = t::BehaviorRecord->new(
        object_state      => { a => 1 },
        hash_order_policy => 'sorted',
    );
    my $p = t::BehaviorRecord->new(
        object_state      => { a => 2 },
        hash_order_policy => 'sorted',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'hash object_state value mismatch => MISCOMPILE' );
}

# =========================================================================
# Axis: dualvar policy (numeric vs string face)
# =========================================================================
{
    # dualvar_policy 'string': compare string face only
    # If both stringize to "42" but one has numeric 42 and the other "42"
    # They should PASS under string policy
    my $s = t::BehaviorRecord->new(
        return_values  => ["42"],
        dualvar_policy => 'string',
    );
    my $p = t::BehaviorRecord->new(
        return_values  => [42],    # numeric — stringizes to "42"
        dualvar_policy => 'string',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS', 'dualvar string policy: same string face => PASS' );
}
{
    # dualvar_policy 'numeric': compare numeric face only
    my $s = t::BehaviorRecord->new(
        return_values  => [42],
        dualvar_policy => 'numeric',
    );
    my $p = t::BehaviorRecord->new(
        return_values  => [42.0],   # same numeric value
        dualvar_policy => 'numeric',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS', 'dualvar numeric policy: same numeric face => PASS' );
}
{
    # dualvar_policy 'string': different string face => MISCOMPILE
    my $s = t::BehaviorRecord->new(
        return_values  => ["hello"],
        dualvar_policy => 'string',
    );
    my $p = t::BehaviorRecord->new(
        return_values  => ["world"],
        dualvar_policy => 'string',
    );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'dualvar string policy: different string face => MISCOMPILE' );
}

# =========================================================================
# Axis: exception type + message
# =========================================================================
{
    # Both die with same kind/message => PASS
    my $exc = { kind => 'string', class => undef, message => 'error occurred' };
    my $s = t::BehaviorRecord->new( exception => $exc );
    my $p = t::BehaviorRecord->new( exception => { kind => 'string', class => undef, message => 'error occurred' } );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS', 'exception same kind+message => PASS' );
}
{
    # S dies, P does not => MISCOMPILE
    my $s = t::BehaviorRecord->new( exception => { kind => 'string', class => undef, message => 'oops' } );
    my $p = t::BehaviorRecord->new( exception => undef );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'S throws P does not => MISCOMPILE' );
}
{
    # P dies, S does not => MISCOMPILE
    my $s = t::BehaviorRecord->new( exception => undef );
    my $p = t::BehaviorRecord->new( exception => { kind => 'string', class => undef, message => 'unexpected' } );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'P throws S does not => MISCOMPILE' );
}
{
    # Both throw but different messages => MISCOMPILE
    my $s = t::BehaviorRecord->new( exception => { kind => 'string', class => undef, message => 'error A' } );
    my $p = t::BehaviorRecord->new( exception => { kind => 'string', class => undef, message => 'error B' } );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'same exception kind but different message => MISCOMPILE' );
}
{
    # Both throw but different kind => MISCOMPILE
    my $s = t::BehaviorRecord->new( exception => { kind => 'string', class => undef, message => 'e' } );
    my $p = t::BehaviorRecord->new( exception => { kind => 'object', class => 'MyError', message => 'e' } );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'exception kind mismatch => MISCOMPILE' );
}

# =========================================================================
# Axis: wantarray / context
# =========================================================================
{
    # Different wantarray context => MISCOMPILE
    my $s = t::BehaviorRecord->new( wantarray_context => 'scalar', return_values => [1] );
    my $p = t::BehaviorRecord->new( wantarray_context => 'list',   return_values => [1] );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'wantarray context mismatch => MISCOMPILE' );
}
{
    # Same wantarray context => contributes to PASS
    my $s = t::BehaviorRecord->new( wantarray_context => 'list', return_values => [1, 2] );
    my $p = t::BehaviorRecord->new( wantarray_context => 'list', return_values => [1, 2] );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS', 'wantarray same context + matching values => PASS' );
}

# =========================================================================
# Axis: STDERR / warnings
# =========================================================================
{
    # STDERR differs => MISCOMPILE
    my $s = t::BehaviorRecord->new( stderr => '' );
    my $p = t::BehaviorRecord->new( stderr => 'Use of uninitialized value' );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'STDERR differs => MISCOMPILE' );
}
{
    # STDERR matches => PASS contribution
    my $s = t::BehaviorRecord->new( stderr => 'some warning' );
    my $p = t::BehaviorRecord->new( stderr => 'some warning' );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS', 'STDERR same => PASS' );
}

# =========================================================================
# Axis: return_values list comparison
# =========================================================================
{
    # Different length => MISCOMPILE
    my $s = t::BehaviorRecord->new( return_values => [1, 2, 3] );
    my $p = t::BehaviorRecord->new( return_values => [1, 2] );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'MISCOMPILE', 'return_values different length => MISCOMPILE' );
}
{
    # Same multi-value list => PASS
    my $s = t::BehaviorRecord->new( return_values => [1, 2, 3] );
    my $p = t::BehaviorRecord->new( return_values => [1, 2, 3] );
    my $r = Comparator->verdict($s, $p, $COMPLETE_META);
    is( $r->{verdict}, 'PASS', 'return_values same multi-value => PASS' );
}

done_testing;
