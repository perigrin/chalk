# ABOUTME: Tests for _remove_trivial_phi() — collapses Phis with identical operands.
# ABOUTME: Tests both the function directly and its integration into merge_with_phis().
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Scope;
use Chalk::IR::Node::Phi;
use Scalar::Util 'refaddr';

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

my $const1 = $factory->make('Constant', const_type => 'integer', value => '1');
my $const2 = $factory->make('Constant', const_type => 'integer', value => '2');
my $const3 = $factory->make('Constant', const_type => 'integer', value => '3');

my $region = $factory->make('Region', controls => []);

# --- Direct unit tests for _remove_trivial_phi() ---

# Case 1: Phi with two identical operands — trivial, returns the value
{
    my $phi = $factory->make('Phi',
        region => $region,
        values => [$const1, $const1],
    );
    my $result = Chalk::Bootstrap::Scope::_remove_trivial_phi($phi);
    ok(!($result isa Chalk::IR::Node::Phi),
        'direct: Phi with two identical operands is trivial');
    is(refaddr($result), refaddr($const1),
        'direct: trivial Phi returns the common value');
}

# Case 2: Phi with self-reference + one other value — trivial (self-ref skipped)
{
    my $phi = $factory->make('Phi',
        region => $region,
        values => [undef, undef],
    );
    # Wire in: const1 as first operand, phi itself as second (self-reference)
    $phi->inputs()->[0] = $const1;
    $phi->inputs()->[1] = $phi;

    my $result = Chalk::Bootstrap::Scope::_remove_trivial_phi($phi);
    ok(!($result isa Chalk::IR::Node::Phi),
        'direct: Phi with self-ref + one value is trivial (self-ref ignored)');
    is(refaddr($result), refaddr($const1),
        'direct: trivial Phi (self-ref case) returns the non-self value');
}

# Case 3: Phi with two different values — non-trivial, returns the Phi unchanged
{
    my $phi = $factory->make('Phi',
        region => $region,
        values => [$const1, $const2],
    );
    my $result = Chalk::Bootstrap::Scope::_remove_trivial_phi($phi);
    ok($result isa Chalk::IR::Node::Phi,
        'direct: Phi with different operands is non-trivial');
    is(refaddr($result), refaddr($phi),
        'direct: non-trivial Phi returns the Phi itself');
}

# Case 4: Phi with undef operand + a value — non-trivial (undef path exists)
{
    my $phi = $factory->make('Phi',
        region => $region,
        values => [$const1, undef],
    );
    my $result = Chalk::Bootstrap::Scope::_remove_trivial_phi($phi);
    ok($result isa Chalk::IR::Node::Phi,
        'direct: Phi with undef operand is non-trivial');
    is(refaddr($result), refaddr($phi),
        'direct: non-trivial Phi (undef path) returns the Phi itself');
}

# --- Integration tests: merge_with_phis() wires in _remove_trivial_phi() ---

# Case 5: both branches unchanged — merge returns original value, not a Phi
{
    my $pre_scope = Chalk::Bootstrap::Scope->new();
    $pre_scope = $pre_scope->define('$x', $const1);

    my $merged = $pre_scope->merge_with_phis(
        $pre_scope, $pre_scope, $region, $factory,
    );

    my $x_val = $merged->lookup('$x');
    ok(!($x_val isa Chalk::IR::Node::Phi),
        'integration: both-unchanged merge returns original value, not a Phi');
    is(refaddr($x_val), refaddr($const1),
        'integration: returned value is the original node');
}

# Case 6: both branches assign different values — non-trivial Phi remains
{
    my $pre_scope = Chalk::Bootstrap::Scope->new();
    $pre_scope = $pre_scope->define('$x', $const1);

    my $then_scope = $pre_scope->define('$x', $const2);
    my $else_scope = $pre_scope->define('$x', $const3);

    my $merged = $pre_scope->merge_with_phis(
        $then_scope, $else_scope, $region, $factory,
    );

    my $x_val = $merged->lookup('$x');
    ok($x_val isa Chalk::IR::Node::Phi,
        'integration: different values produce a non-trivial Phi');
}

# Case 7: variable only in one branch (other undef) — Phi remains
{
    my $base_scope = Chalk::Bootstrap::Scope->new();
    my $then_scope = $base_scope->define('$z', $const1);
    my $else_scope = $base_scope;

    my $merged = $base_scope->merge_with_phis(
        $then_scope, $else_scope, $region, $factory,
    );

    my $z_val = $merged->lookup('$z');
    ok($z_val isa Chalk::IR::Node::Phi,
        'integration: one-branch-only variable produces a Phi');
}

# Case 8: both branches assign same value (same node) — trivial, returns value
{
    my $pre_scope = Chalk::Bootstrap::Scope->new();
    $pre_scope = $pre_scope->define('$x', $const1);

    my $then_scope = $pre_scope->define('$x', $const2);
    my $else_scope = $pre_scope->define('$x', $const2);  # same node

    my $merged = $pre_scope->merge_with_phis(
        $then_scope, $else_scope, $region, $factory,
    );

    my $x_val = $merged->lookup('$x');
    ok(!($x_val isa Chalk::IR::Node::Phi),
        'integration: both-same-value returns the value, not a Phi');
    is(refaddr($x_val), refaddr($const2),
        'integration: returned value is the shared node');
}

done_testing();
