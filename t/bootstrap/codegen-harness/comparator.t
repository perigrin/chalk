# ABOUTME: Tests for Chalk::CodeGen::Harness::Comparator — three-verdict classifier.
# ABOUTME: Verifies PASS/GAP/MISCOMPILE verdicts across all three canonical scenarios.
use 5.42.0;
use utf8;

use Test2::V0;
use lib 'lib';

use Chalk::CodeGen::Harness::Comparator;
use constant Comparator => 'Chalk::CodeGen::Harness::Comparator';

# -------------------------------------------------------------------------
# Test-fixture BehaviorRecord — same field/accessor contract as the real
# BehaviorRecord (sibling C1 agent), defined locally so this test is
# self-contained. Does NOT redefine the real package.
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

# Helper: build a matching pair of records (all axes identical, non-empty)
sub matching_records {
    my $s = t::BehaviorRecord->new(
        return_values     => [42],
        wantarray_context => 'scalar',
        stdout            => 'hello',
        stderr            => '',
        exception         => undef,
        object_state      => { x => 1 },
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $p = t::BehaviorRecord->new(
        return_values     => [42],
        wantarray_context => 'scalar',
        stdout            => 'hello',
        stderr            => '',
        exception         => undef,
        object_state      => { x => 1 },
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    return ($s, $p);
}

# =========================================================================
# Scenario 1: PASS — all axes match, complete emission
# =========================================================================
{
    my ($s, $p) = matching_records();
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };

    my $result = Comparator->verdict($s, $p, $meta);

    ok( defined $result, 'verdict returns a defined value' );
    is( $result->{verdict}, 'PASS', 'PASS when records fully match and emission complete' );
}

# =========================================================================
# Scenario 2: GAP — emission_meta signals incomplete emission
# =========================================================================
{
    # P record matches S on observed axes BUT emission was incomplete
    my ($s, $p) = matching_records();
    my $meta = { emitted_for_every_construct => 0, marked_unsupported => 0 };

    my $result = Comparator->verdict($s, $p, $meta);

    is( $result->{verdict}, 'GAP',
        'GAP when emitted_for_every_construct is false, even if observed axes match' );
}

# =========================================================================
# Scenario 2b: GAP — marked_unsupported true overrides any match
# =========================================================================
{
    my ($s, $p) = matching_records();
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 1 };

    my $result = Comparator->verdict($s, $p, $meta);

    is( $result->{verdict}, 'GAP',
        'GAP when marked_unsupported is true regardless of axis agreement' );
}

# =========================================================================
# Scenario 3: MISCOMPILE — complete emission but return_values diverge
# =========================================================================
{
    my $s = t::BehaviorRecord->new(
        return_values     => [42],
        wantarray_context => 'scalar',
        stdout            => '',
        stderr            => '',
        exception         => undef,
        object_state      => {},
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $p = t::BehaviorRecord->new(
        return_values     => [99],  # diverges from S
        wantarray_context => 'scalar',
        stdout            => '',
        stderr            => '',
        exception         => undef,
        object_state      => {},
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };

    my $result = Comparator->verdict($s, $p, $meta);

    is( $result->{verdict}, 'MISCOMPILE',
        'MISCOMPILE when complete-looking emission but return_values diverge' );
}

# =========================================================================
# Scenario 4: MISCOMPILE — complete emission but stdout diverges
# =========================================================================
{
    my $s = t::BehaviorRecord->new(
        return_values     => [1],
        wantarray_context => 'scalar',
        stdout            => 'expected output',
        stderr            => '',
        exception         => undef,
        object_state      => {},
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $p = t::BehaviorRecord->new(
        return_values     => [1],
        wantarray_context => 'scalar',
        stdout            => 'wrong output',  # diverges
        stderr            => '',
        exception         => undef,
        object_state      => {},
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };

    my $result = Comparator->verdict($s, $p, $meta);

    is( $result->{verdict}, 'MISCOMPILE',
        'MISCOMPILE when complete emission but stdout diverges' );
}

# =========================================================================
# Scenario 5: MISCOMPILE — exception presence differs
# =========================================================================
{
    my $s = t::BehaviorRecord->new(
        return_values     => [],
        wantarray_context => 'scalar',
        stdout            => '',
        stderr            => '',
        exception         => { kind => 'string', class => undef, message => 'oops' },
        object_state      => {},
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $p = t::BehaviorRecord->new(
        return_values     => [],
        wantarray_context => 'scalar',
        stdout            => '',
        stderr            => '',
        exception         => undef,  # S had an exception, P did not
        object_state      => {},
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };

    my $result = Comparator->verdict($s, $p, $meta);

    is( $result->{verdict}, 'MISCOMPILE',
        'MISCOMPILE when exception presence differs' );
}

# =========================================================================
# Verdict result structure
# =========================================================================
{
    my ($s, $p) = matching_records();
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0 };
    my $result = Comparator->verdict($s, $p, $meta);

    # Result must be a hashref with at least {verdict}
    ref_ok( $result, 'HASH', 'verdict returns a hashref' );
    ok( exists $result->{verdict}, 'result contains verdict key' );
}

# =========================================================================
# MISCOMPILE result carries implicated_layer
# =========================================================================
{
    my $s = t::BehaviorRecord->new(
        return_values     => [1],
        wantarray_context => 'scalar',
        stdout            => '',
        stderr            => '',
        exception         => undef,
        object_state      => {},
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $p = t::BehaviorRecord->new(
        return_values     => [2],
        wantarray_context => 'scalar',
        stdout            => '',
        stderr            => '',
        exception         => undef,
        object_state      => {},
        hash_order_policy => 'sorted',
        fp_tolerance      => 1e-9,
        dualvar_policy    => 'string',
        aliasing_topology => 'none',
    );
    my $meta = { emitted_for_every_construct => 1, marked_unsupported => 0, graph_source => 'hand' };
    my $result = Comparator->verdict($s, $p, $meta);

    is( $result->{verdict}, 'MISCOMPILE', 'MISCOMPILE verdict' );
    ok( exists $result->{implicated_layer}, 'result contains implicated_layer' );
    ok( defined $result->{implicated_layer}, 'implicated_layer is defined' );
}

done_testing;
