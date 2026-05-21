# ABOUTME: Unit tests for Scope SSA (Static Single Assignment) reassignment behavior
# ABOUTME: Verifies that define() overwrites bindings and that Scope is immutable
use 5.42.0;
use utf8;

use Test2::V0;
use Scalar::Util 'refaddr';

use lib 'lib';
use Chalk::Bootstrap::Scope;
use Chalk::IR::NodeFactory;

my $factory = Chalk::IR::NodeFactory->new;

# Test 1: define() overwrites an existing binding
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_a = $factory->make('Constant', const_type => 'int', value => 1);
    my $node_b = $factory->make('Constant', const_type => 'int', value => 2);

    my $scope2 = $scope->define('$x', $node_a);
    my $scope3 = $scope2->define('$x', $node_b);

    is($scope3->lookup('$x'), $node_b, 'define() overwrites existing binding');
}

# Test 2: original scope is unchanged after overwrite (immutability)
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_a = $factory->make('Constant', const_type => 'int', value => 10);
    my $node_b = $factory->make('Constant', const_type => 'int', value => 20);

    my $scope2 = $scope->define('$x', $node_a);
    my $scope3 = $scope2->define('$x', $node_b);

    is($scope2->lookup('$x'), $node_a, 'original scope unchanged after overwrite');
    is($scope->lookup('$x'), undef, 'base scope still has no binding');
}

# Test 3: define() with sigil-prefixed name works for all sigils
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $scalar_node = $factory->make('Constant', const_type => 'int', value => 1);
    my $array_node  = $factory->make('Constant', const_type => 'int', value => 2);
    my $hash_node   = $factory->make('Constant', const_type => 'int', value => 3);

    my $scope2 = $scope->define('$x', $scalar_node)
                       ->define('@arr', $array_node)
                       ->define('%h', $hash_node);

    is($scope2->lookup('$x'),    $scalar_node, 'scalar variable binding works');
    is($scope2->lookup('@arr'),  $array_node,  'array variable binding works');
    is($scope2->lookup('%h'),    $hash_node,   'hash variable binding works');
}

# Test 4: Overwriting a binding does not affect other bindings in the same scope
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_x = $factory->make('Constant', const_type => 'int', value => 1);
    my $node_y = $factory->make('Constant', const_type => 'int', value => 2);
    my $node_x2 = $factory->make('Constant', const_type => 'int', value => 99);

    my $scope2 = $scope->define('$x', $node_x)->define('$y', $node_y);
    my $scope3 = $scope2->define('$x', $node_x2);

    is($scope3->lookup('$x'), $node_x2, 'overwritten binding has new value');
    is($scope3->lookup('$y'), $node_y,  'other binding unchanged after overwrite');
}

done_testing();
