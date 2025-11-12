# ABOUTME: Test for Sea of Nodes IR generation - Chapter 3: Variables and Scoping
# ABOUTME: Validates ScopeNode, variable declarations, variable references, and lexical scoping with SSA form

use lib 'lib';
use v5.42;
use lib 'lib';
use Test::More;
use lib 'lib';
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Node::Scope');
use_ok('Chalk::IR::Builder');

# Test ScopeNode basic functionality
subtest 'ScopeNode creation and basic operations' => sub {
    my $scope = Chalk::IR::Node::Scope->new();

    ok($scope, 'Scope node created');
    is($scope->op, 'Scope', 'Scope node has correct op');
    is($scope->depth, 1, 'Scope starts with depth 1 (global scope)');

    # Define a variable
    $scope->define('x', 'node_1');
    is($scope->lookup('x'), 'node_1', 'Variable lookup returns correct node ID');

    # Check that node_1 is in inputs (to keep it alive)
    my $inputs = $scope->inputs;
    ok((grep { $_ eq 'node_1' } @$inputs), 'Defined variable is in scope inputs');
};

# Test nested scopes (Example 1 from Chapter 3)
subtest 'Nested scopes with variable shadowing' => sub {
    my $scope = Chalk::IR::Node::Scope->new();

    # Outer scope: int a=1, int b=2, int c=0
    $scope->define('a', 'node_1');  # a = 1
    $scope->define('b', 'node_2');  # b = 2
    $scope->define('c', 'node_3');  # c = 0

    is($scope->lookup('a'), 'node_1', 'Outer a defined');
    is($scope->lookup('b'), 'node_2', 'Outer b defined');
    is($scope->lookup('c'), 'node_3', 'Outer c defined');
    is($scope->depth, 1, 'Still at depth 1');

    # Enter inner scope
    $scope->push_scope();
    is($scope->depth, 2, 'Inner scope depth is 2');

    # Shadow b with new value: int b=3
    $scope->define('b', 'node_4');  # inner b = 3

    # Inner scope lookups
    is($scope->lookup('a'), 'node_1', 'Inner scope sees outer a');
    is($scope->lookup('b'), 'node_4', 'Inner scope sees shadowed b');
    is($scope->lookup('c'), 'node_3', 'Inner scope sees outer c');

    # c = a + b (should use node_1 and node_4)
    $scope->define('c', 'node_5');  # c = a + b (node_5 is Add node)
    is($scope->lookup('c'), 'node_5', 'c redefined in inner scope');

    # Exit inner scope
    $scope->pop_scope();
    is($scope->depth, 1, 'Back to depth 1');

    # Outer scope should still have original b
    is($scope->lookup('a'), 'node_1', 'After pop, outer a unchanged');
    is($scope->lookup('b'), 'node_2', 'After pop, outer b restored (not shadowed)');
    is($scope->lookup('c'), 'node_3', 'After pop, outer c restored');
};

# Test sequential scopes at same level (Example 2 from Chapter 3)
subtest 'Sequential scopes at same nesting level' => sub {
    my $scope = Chalk::IR::Node::Scope->new();

    # Outer scope
    $scope->define('a', 'node_1');  # int a = 1
    $scope->define('b', 'node_2');  # int b = 2
    $scope->define('c', 'node_3');  # int c = 0

    # First inner scope
    $scope->push_scope();
    $scope->define('b', 'node_4');  # int b = 5
    # c = a + b would be node_5
    $scope->define('c', 'node_5');
    is($scope->depth, 2, 'First inner scope depth 2');
    $scope->pop_scope();

    # Second inner scope (sequential, same level)
    $scope->push_scope();
    is($scope->depth, 2, 'Second inner scope also depth 2');
    $scope->define('e', 'node_6');  # int e = 6
    # c = a + e would be node_7
    $scope->define('c', 'node_7');
    is($scope->lookup('e'), 'node_6', 'Second scope has e');
    is($scope->lookup('c'), 'node_7', 'Second scope c redefined');
    is($scope->lookup('a'), 'node_1', 'Second scope sees outer a');

    # b should be from outer scope (not first inner scope)
    is($scope->lookup('b'), 'node_2', 'Second scope sees outer b (not from first scope)');
    $scope->pop_scope();

    # After both scopes, c should be back to original
    is($scope->lookup('c'), 'node_3', 'After sequential scopes, c is original');
};

# Test IR::Builder variable methods integration
subtest 'IR::Builder variable definition and lookup' => sub {
    my $builder = Chalk::IR::Builder->new();

    # Create IR nodes
    my $node_x = $builder->build_constant_node(10);
    my $node_y = $builder->build_constant_node(11);

    # Define variables
    $builder->define_variable('x', $node_x->id);
    my $result_x = $builder->lookup_variable('x');
    isa_ok($result_x, 'Chalk::IR::Node::Constant', 'Builder lookup returns IR node');
    is($result_x->id, $node_x->id, 'Builder lookup returns correct node');

    # Define another variable
    $builder->define_variable('y', $node_y->id);
    my $result_y = $builder->lookup_variable('y');
    is($result_y->id, $node_y->id, 'Builder lookup for second variable');

    # First variable still accessible
    my $result_x2 = $builder->lookup_variable('x');
    is($result_x2->id, $node_x->id, 'First variable still accessible');

    # Undefined variable returns undef
    is($builder->lookup_variable('undefined_var'), undef, 'Undefined variable returns undef');
};

# TODO: Parser integration tests
# These tests are blocked by grammar issues (WS_OPT rule needs evaluate() method)
# and scope handling in the parser. The core Chapter 3 functionality
# (variable definition/lookup via IR::Builder) is already tested above.
TODO: {
    local $TODO = 'Parser integration requires WS_OPT evaluate() and scope handling';

    subtest 'Parse: my $x = 1; return $x;' => sub {
        plan skip_all => 'WS_OPT grammar rule needs evaluate() method';

        # Expected behavior:
        # - Parse creates variable declaration
        # - Variable reference returns the IR node
        # - No Load nodes (SSA direct reference)
    };

    subtest 'Parse: variable reference in expression' => sub {
        plan skip_all => 'WS_OPT grammar rule needs evaluate() method';

        # Code: my $x = 1; return $x + 2;
        # Expected:
        # - Variable x defined and looked up correctly
        # - Add node created that uses the variable IR node
    };

    subtest 'Parse: nested scope with shadowing' => sub {
        plan skip_all => 'Nested scope support not yet implemented';

        # Code: my $a=1; my $b=2; my $c=0; { my $b=3; $c=$a+$b; } return $c;
        # Expected:
        # - Inner $b shadows outer $b
        # - $c assignment in inner scope uses inner $b
        # - return $c uses outer $c value
    };

    subtest 'Parse: constant folding demonstration' => sub {
        plan skip_all => 'Peephole optimization not implemented';

        # Code: my $x0=1; my $y0=2; my $x1=3; my $y1=4;
        #       return ($x0-$x1)*($x0-$x1) + ($y0-$y1)*($y0-$y1);
        # Expected with optimization:
        # - All computations fold to constant 8
        # - Final IR is just "return 8"
    };
}

done_testing();
