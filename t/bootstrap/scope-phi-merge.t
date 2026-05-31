# ABOUTME: Tests for Scope::merge_with_phis() — creates Phis at merge points.
# ABOUTME: Verifies eager Phi creation for if/else branches with differing variables.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Bindings;
use Chalk::IR::Node::Phi;

my $factory = Chalk::IR::NodeFactory->new();

my $const1 = $factory->make('Constant', const_type => 'integer', value => '1');
my $const2 = $factory->make('Constant', const_type => 'integer', value => '2');
my $const3 = $factory->make('Constant', const_type => 'integer', value => '3');

my $pre_scope = Chalk::Bootstrap::Bindings->new();
$pre_scope = $pre_scope->define('$x', $const1);
$pre_scope = $pre_scope->define('$y', $const3);

my $region = $factory->make('Region', controls => []);

# Case 1: $x differs between branches, $y is same
{
    my $then_scope = $pre_scope->define('$x', $const2);
    my $else_scope = $pre_scope;  # unchanged

    my $merged = $pre_scope->merge_with_phis(
        $then_scope, $else_scope, $region, $factory,
    );

    my $x_val = $merged->lookup('$x');
    ok(defined $x_val, '$x is defined after merge');
    ok($x_val isa Chalk::IR::Node::Phi, '$x is a Phi node');
    is($x_val->region(), $region, 'Phi region is the Region node');
    is($x_val->inputs()->[0], $const2, 'Phi then-operand is Const(2)');
    is($x_val->inputs()->[1], $const1, 'Phi else-operand is Const(1)');

    my $y_val = $merged->lookup('$y');
    is($y_val, $const3, '$y is unchanged (no Phi)');
}

# Case 2: both branches assign different values
{
    my $then_scope = $pre_scope->define('$x', $const2);
    my $else_scope = $pre_scope->define('$x', $const3);

    my $merged = $pre_scope->merge_with_phis(
        $then_scope, $else_scope, $region, $factory,
    );

    my $x_val = $merged->lookup('$x');
    ok($x_val isa Chalk::IR::Node::Phi, 'both-assign: $x is Phi');
    is($x_val->inputs()->[0], $const2, 'then-operand');
    is($x_val->inputs()->[1], $const3, 'else-operand');
}

# Case 3: variable only in then-branch
{
    my $const4 = $factory->make('Constant', const_type => 'string', value => 'new');
    my $then_scope = $pre_scope->define('$z', $const4);
    my $else_scope = $pre_scope;

    my $merged = $pre_scope->merge_with_phis(
        $then_scope, $else_scope, $region, $factory,
    );

    my $z_val = $merged->lookup('$z');
    ok(defined $z_val, '$z exists after merge');
    ok($z_val isa Chalk::IR::Node::Phi, '$z is Phi (then-only)');
}

# Case 4: both branches unchanged — no Phis
{
    my $merged = $pre_scope->merge_with_phis(
        $pre_scope, $pre_scope, $region, $factory,
    );

    my $x_val = $merged->lookup('$x');
    is($x_val, $const1, 'both-unchanged: $x is original (no Phi)');
    my $y_val = $merged->lookup('$y');
    is($y_val, $const3, 'both-unchanged: $y is original (no Phi)');
}

done_testing();
