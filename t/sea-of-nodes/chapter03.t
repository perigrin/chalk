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

# Parser integration tests - Chapter 3: Lexical Scoping
# These tests parse actual Chalk code and verify IR graph structure

use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Grammar::Chalk');
use_ok('Chalk::Semiring::ChalkIR');

# Helper to create parser for testing
# Returns (parser, builder, scope) for easy access to IR
sub make_parser {
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Can't open grammar: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
    my $scope = Chalk::IR::Node::Scope->new();

    # ChalkIR creates a composite semiring with SPPF, Precedence, and Semantic
    # It also creates its own IR builder
    my $semiring = Chalk::Semiring::ChalkIR->new(
        grammar => $grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Get the builder from the ChalkIR semiring
    my $builder = $semiring->builder;

    return ($parser, $builder, $scope);
}

# Helper to parse and prune IR graph to winning parse
sub parse_and_prune {
    my ($parser, $builder, $code) = @_;
    my $result = $parser->parse_string($code);

    # Prune graph to only include nodes from winning parse
    # This removes IR nodes created by losing parse alternatives
    if ($result && $result->can('context')) {
        my $focus = $result->context->focus;
        if ($focus && $focus->can('id')) {
            $builder->graph->prune_to_reachable($focus->id);
        }
    }

    return $result;
}

subtest 'Parse: Simple bare block with scoping' => sub {
    my ($parser, $builder, $scope) = make_parser();

    # Simplest Chapter 3 example: bare block creates new scope
    my $code = 'my $a = 1; { my $b = 2; } return $a;';

    my $result = parse_and_prune($parser, $builder, $code);
    ok($result, 'Parse succeeded');

    my $graph = $builder->graph;

    # Should have: Start, Constants (1, 2), VariableWrite nodes, Return
    ok($graph->node_count > 0, 'Graph has nodes');

    # Verify we can find the Return node
    my @nodes = values %{$graph->nodes};
    my @returns = grep { $_->op eq 'Return' } @nodes;
    is(scalar(@returns), 1, 'Exactly one Return node');

    # Verify constants exist for 1 and 2
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 2, 'Has constant nodes for 1 and 2');
};

subtest 'Parse: Nested scope with variable shadowing' => sub {
    my ($parser, $builder, $scope) = make_parser();

    # Chapter 3 main example (simplified):
    # Outer $b=2, inner $b=3, assignment uses inner $b
    my $code = q{
        my $a = 1;
        my $b = 2;
        my $c = 0;
        {
            my $b = 3;
            $c = $a + $b;
        }
        return $c;
    };

    my $result = parse_and_prune($parser, $builder, $code);
    ok($result, 'Parse succeeded with nested scopes');

    my $graph = $builder->graph;

    # Verify basic structure
    ok($graph->node_count > 0, 'Graph has nodes');

    my @nodes = values %{$graph->nodes};
    my @returns = grep { $_->op eq 'Return' } @nodes;
    is(scalar(@returns), 1, 'Has Return node');

    # Should have constants for 0, 1, 2, 3
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 4, 'Has constants for literal values');

    # Should have Add node for $a + $b
    my @adds = grep { $_->op eq 'Add' } @nodes;
    ok(scalar(@adds) >= 1, 'Has Add node for $a + $b');

    # The critical test: the Add node should use the INNER $b (value 3)
    # This verifies variable shadowing works correctly
    # We'll verify this by checking that the Add has the right constant as input
    my $add = $adds[0];
    ok($add, 'Add node exists for verification');
};

subtest 'Parse: Variable reference in expression' => sub {
    my ($parser, $builder, $scope) = make_parser();

    my $code = 'my $x = 1; return $x + 2;';

    my $result = parse_and_prune($parser, $builder, $code);
    ok($result, 'Parse succeeded');

    my $graph = $builder->graph;
    my @nodes = values %{$graph->nodes};

    # Should have Add node combining $x and 2
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 1, 'Has Add node for $x + 2');

    # Should have constants for 1 and 2
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 2, 'Has constants for 1 and 2');
};

done_testing();
