# ABOUTME: Test for Sea of Nodes IR generation - Chapter 3: Variables and Scoping
# ABOUTME: Validates ScopeNode, variable declarations, variable references, and lexical scoping with SSA form

use lib 'lib';
use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Node::Scope');

# Test ScopeNode basic functionality
subtest 'ScopeNode creation and basic operations' => sub {
    my $scope = Chalk::IR::Node::Scope->new();

    ok($scope, 'Scope node created');
    is($scope->op, 'Scope', 'Scope node has correct op');
    is($scope->depth, 1, 'Scope starts with depth 1 (global scope)');

    # Define a variable (immutable - returns new scope)
    $scope = $scope->with_binding('x', 'node_1');
    is($scope->lookup('x'), 'node_1', 'Variable lookup returns correct node ID');

    # Check that node_1 is in inputs (to keep it alive)
    my $inputs = $scope->inputs;
    ok((grep { $_ eq 'node_1' } @$inputs), 'Defined variable is in scope inputs');
};

# Test nested scopes (Example 1 from Chapter 3)
subtest 'Nested scopes with variable shadowing' => sub {
    # Outer scope: int a=1, int b=2, int c=0
    my $outer = Chalk::IR::Node::Scope->new();
    $outer = $outer->with_binding('a', 'node_1');  # a = 1
    $outer = $outer->with_binding('b', 'node_2');  # b = 2
    $outer = $outer->with_binding('c', 'node_3');  # c = 0

    is($outer->lookup('a'), 'node_1', 'Outer a defined');
    is($outer->lookup('b'), 'node_2', 'Outer b defined');
    is($outer->lookup('c'), 'node_3', 'Outer c defined');
    is($outer->depth, 1, 'Outer scope at depth 1');

    # Enter inner scope (immutable - creates new child scope)
    my $inner = $outer->child_scope();
    is($inner->depth, 2, 'Inner scope depth is 2');

    # Shadow b with new value: int b=3
    $inner = $inner->with_binding('b', 'node_4');  # inner b = 3

    # Inner scope lookups
    is($inner->lookup('a'), 'node_1', 'Inner scope sees outer a');
    is($inner->lookup('b'), 'node_4', 'Inner scope sees shadowed b');
    is($inner->lookup('c'), 'node_3', 'Inner scope sees outer c');

    # c = a + b (should use node_1 and node_4)
    $inner = $inner->with_binding('c', 'node_5');  # c = a + b (node_5 is Add node)
    is($inner->lookup('c'), 'node_5', 'c redefined in inner scope');

    # Outer scope is unchanged (immutable)
    is($outer->depth, 1, 'Outer scope still at depth 1');
    is($outer->lookup('a'), 'node_1', 'Outer a unchanged');
    is($outer->lookup('b'), 'node_2', 'Outer b unchanged (not affected by inner shadow)');
    is($outer->lookup('c'), 'node_3', 'Outer c unchanged');
};

# Test sequential scopes at same level (Example 2 from Chapter 3)
subtest 'Sequential scopes at same nesting level' => sub {
    # Outer scope
    my $outer = Chalk::IR::Node::Scope->new();
    $outer = $outer->with_binding('a', 'node_1');  # int a = 1
    $outer = $outer->with_binding('b', 'node_2');  # int b = 2
    $outer = $outer->with_binding('c', 'node_3');  # int c = 0

    # First inner scope
    my $first_inner = $outer->child_scope();
    $first_inner = $first_inner->with_binding('b', 'node_4');  # int b = 5
    # c = a + b would be node_5
    $first_inner = $first_inner->with_binding('c', 'node_5');
    is($first_inner->depth, 2, 'First inner scope depth 2');

    # Second inner scope (sequential, same level - branched from outer, not first_inner)
    my $second_inner = $outer->child_scope();
    is($second_inner->depth, 2, 'Second inner scope also depth 2');
    $second_inner = $second_inner->with_binding('e', 'node_6');  # int e = 6
    # c = a + e would be node_7
    $second_inner = $second_inner->with_binding('c', 'node_7');
    is($second_inner->lookup('e'), 'node_6', 'Second scope has e');
    is($second_inner->lookup('c'), 'node_7', 'Second scope c redefined');
    is($second_inner->lookup('a'), 'node_1', 'Second scope sees outer a');

    # b should be from outer scope (not first inner scope)
    is($second_inner->lookup('b'), 'node_2', 'Second scope sees outer b (not from first scope)');

    # Outer scope is unchanged (immutable)
    is($outer->lookup('c'), 'node_3', 'Outer scope c unchanged');
};

# Parser integration tests - Chapter 3: Lexical Scoping
# These tests parse actual Chalk code and verify IR graph structure

use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Grammar::Chalk');
use_ok('Chalk::Semiring::ChalkIR');

# Helper to create parser for testing
sub make_parser {
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Can't open grammar: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkIR->new(
        grammar => $grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    return $parser;
}

# Helper to build graph from winning parse node
sub build_graph_from_result {
    my ($result) = @_;
    return undef unless $result && $result->can('context');

    my $ctx = $result->context;
    return undef unless $ctx && $ctx->can('focus');

    my $winning_node = $ctx->focus;
    return undef unless blessed($winning_node) && $winning_node->can('id');

    # Build graph by traversing from winning node
    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);

    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        my $node_id = $node->id;
        next if $visited{$node_id}++;

        $graph->add_node($node);

        # Traverse via object references
        for my $accessor (qw(value_node value control left right operand condition source)) {
            next unless $node->can($accessor);
            # Skip value for Constant nodes (it's not a node reference)
            next if $accessor eq 'value' && $node->can('op') && $node->op eq 'Constant';
            my $ref = $node->$accessor;
            push @queue, $ref if blessed($ref) && $ref->can('id') && !$visited{$ref->id};
        }
        # Traverse Stop's returns
        if ($node->can('return_nodes') && $node->return_nodes) {
            for my $ret ($node->return_nodes->@*) {
                push @queue, $ret if blessed($ret) && $ret->can('id') && !$visited{$ret->id};
            }
        }
    }


    return $graph;
}

subtest 'Parse: Simple bare block with scoping' => sub {
    my $parser = make_parser();

    # Simplest Chapter 3 example: bare block creates new scope
    my $code = 'my $a = 1; { my $b = 2; } return $a;';

    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    # Should have nodes (only reachable ones)
    ok($graph->node_count > 0, 'Graph has nodes');

    # Verify we can find the Return node
    my @nodes = values %{$graph->nodes};
    my @returns = grep { $_->op eq 'Return' } @nodes;
    is(scalar(@returns), 1, 'Exactly one Return node');

    # Verify constant for 1 exists (2 is in dead code block, may not be reachable)
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 1, 'Has constant node for 1');
};

subtest 'Parse: Nested scope with variable shadowing (constant folded)' => sub {
    my $parser = make_parser();

    # Chapter 3 main example (simplified):
    # Outer $b=2, inner $b=3, assignment uses inner $b
    # With constant folding: $a + $b = 1 + 3 = 4
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

    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded with nested scopes');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    # Verify basic structure
    ok($graph->node_count > 0, 'Graph has nodes');

    my @nodes = values %{$graph->nodes};
    my @returns = grep { $_->op eq 'Return' } @nodes;
    is(scalar(@returns), 1, 'Has Return node');

    # With constant folding, $a + $b (1 + 3) folds to Constant(4)
    # So we should have constants including the folded result
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 1, 'Has constant nodes');

    # The Add should be folded away since both operands are constant
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 0, 'Add node folded away (1+3=4)');

    # Verify that the folded constant 4 exists (from $a + inner $b = 1 + 3)
    my @fours = grep { $_->op eq 'Constant' && $_->value == 4 } @constants;
    ok(scalar(@fours) >= 1, 'Constant(4) exists (1+3 folded, proves inner $b=3 used)');
};

subtest 'Parse: Variable reference in expression (constant folded)' => sub {
    my $parser = make_parser();

    my $code = 'my $x = 1; return $x + 2;';

    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');
    my @nodes = values %{$graph->nodes};

    # With constant folding, $x + 2 = 1 + 2 = 3 folds to Constant(3)
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 0, 'Add node folded away ($x + 2 = 1 + 2 = 3)');

    # Should have constant with value 3 (the folded result)
    my @threes = grep { $_->op eq 'Constant' && $_->value == 3 } @nodes;
    ok(scalar(@threes) >= 1, 'Has Constant(3) from folded $x + 2');
};

done_testing();
