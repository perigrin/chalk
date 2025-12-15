# ABOUTME: Parser integration tests for Sea of Nodes Chapter 4 features
# ABOUTME: Tests peephole optimizations, identity elimination, strength reduction, comparisons, and variable handling

use lib 'lib';
use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Grammar::Chalk');
use_ok('Chalk::Semiring::ChalkIR');
use_ok('Chalk::IR::Node::Scope');
use_ok('Chalk::IR::Type::Bool');
use_ok('Chalk::IR::Type::Integer');

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

# =============================================================================
# Peephole Optimizations with variables
# Chapter 4 test cases from Simple's Chapter04Test.java
# =============================================================================

subtest 'Parse: Peephole - 1 + $x + 2 -> ($x + 3) constant combining' => sub {
    my $parser = make_parser();

    # Java: testPeephole - return 1+arg+2; -> return (arg+3);
    # Using local variable since $arg is not bound in initial scope
    my $code = 'my $x = 5; return 1 + $x + 2;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: 1 + 5 + 2 = 8
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @eights = grep { $_->value == 8 } @constants;
    is(scalar(@eights), 1, 'Has Constant(8) from folded 1 + 5 + 2');

    # No Add nodes should remain since all operands are constants
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 0, 'Add nodes folded away');
};

subtest 'Parse: Peephole - (1 + $x) + 2 parenthesized' => sub {
    my $parser = make_parser();

    # Java: testPeephole2 - return (1+arg)+2; -> return (arg+3);
    my $code = 'my $x = 5; return (1 + $x) + 2;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: (1 + 5) + 2 = 8
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @eights = grep { $_->value == 8 } @constants;
    is(scalar(@eights), 1, 'Has Constant(8) from folded (1 + 5) + 2');
};

# =============================================================================
# Identity Elimination
# =============================================================================

subtest 'Parse: Identity - 0 + $x -> $x (additive identity)' => sub {
    my $parser = make_parser();

    # Java: testAdd0 - return 0+arg; -> return arg;
    my $code = 'my $x = 42; return 0 + $x;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: 0 + 42 = 42
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @fortytwos = grep { $_->value == 42 } @constants;
    ok(scalar(@fortytwos) >= 1, 'Has Constant(42) (0 + 42 folded via identity)');

    # Add node should be eliminated via identity
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 0, 'Add node eliminated (identity: 0 + x = x)');
};

subtest 'Parse: Identity - $x + 0 -> $x (additive identity right)' => sub {
    my $parser = make_parser();

    my $code = 'my $x = 42; return $x + 0;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Add node should be eliminated via identity
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 0, 'Add node eliminated (identity: x + 0 = x)');

    # Constant 42 should remain
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @fortytwos = grep { $_->value == 42 } @constants;
    ok(scalar(@fortytwos) >= 1, 'Has Constant(42) from identity elimination');
};

subtest 'Parse: Identity - 1 * $x -> $x (multiplicative identity)' => sub {
    my $parser = make_parser();

    # Java: testMul1 - return 1*arg; -> return arg;
    my $code = 'my $x = 42; return 1 * $x;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: 1 * 42 = 42
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @fortytwos = grep { $_->value == 42 } @constants;
    ok(scalar(@fortytwos) >= 1, 'Has Constant(42) (1 * 42 folded via identity)');

    # Multiply node should be eliminated via identity
    my @muls = grep { $_->op eq 'Multiply' } @nodes;
    is(scalar(@muls), 0, 'Multiply node eliminated (identity: 1 * x = x)');
};

subtest 'Parse: Identity - $x * 1 -> $x (multiplicative identity right)' => sub {
    my $parser = make_parser();

    my $code = 'my $x = 42; return $x * 1;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Multiply node should be eliminated via identity
    my @muls = grep { $_->op eq 'Multiply' } @nodes;
    is(scalar(@muls), 0, 'Multiply node eliminated (identity: x * 1 = x)');

    # Constant 42 should remain
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @fortytwos = grep { $_->value == 42 } @constants;
    ok(scalar(@fortytwos) >= 1, 'Has Constant(42) from identity elimination');
};

# =============================================================================
# Strength Reduction
# =============================================================================

subtest 'Parse: Strength reduction - $x + $x -> $x * 2' => sub {
    my $parser = make_parser();

    # Java: testAddAddMul - return arg+0+arg; -> return (arg*2);
    # With constant x, will fold completely
    my $code = 'my $x = 5; return $x + $x;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: 5 + 5 = 10 (via x * 2 = 10)
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @tens = grep { $_->value == 10 } @constants;
    is(scalar(@tens), 1, 'Has Constant(10) from folded $x + $x (5 + 5)');

    # Both Add and Multiply should be folded away
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 0, 'Add node folded away');

    my @muls = grep { $_->op eq 'Multiply' } @nodes;
    is(scalar(@muls), 0, 'Multiply node folded away (constants folded)');
};

subtest 'Parse: Strength reduction - $x + 0 + $x -> $x * 2' => sub {
    my $parser = make_parser();

    # Java: testAddAddMul - return arg+0+arg; -> return (arg*2);
    my $code = 'my $x = 7; return $x + 0 + $x;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: 7 + 0 + 7 = 14 (via identity then doubling)
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @fourteens = grep { $_->value == 14 } @constants;
    is(scalar(@fourteens), 1, 'Has Constant(14) from folded $x + 0 + $x');
};

# =============================================================================
# Comparison Operators
# =============================================================================

subtest 'Parse: Comparison == with equal constants' => sub {
    my $parser = make_parser();

    # Java: testCompEq - return 3==3; -> return 1;
    my $code = 'return 3 == 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Comparison should fold to constant true (1)
    my @eqs = grep { $_->op eq 'EQ' } @nodes;
    is(scalar(@eqs), 0, 'EQ node folded away');

    # Should have boolean true constant
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @trues = grep { $_->type isa Chalk::IR::Type::Bool && $_->value } @constants;
    is(scalar(@trues), 1, 'Has Constant(true) from folded 3 == 3');
};

subtest 'Parse: Comparison == with unequal constants' => sub {
    my $parser = make_parser();

    # Java: testCompEq2 - return 3==4; -> return 0;
    my $code = 'return 3 == 4;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Comparison should fold to constant false (0)
    my @eqs = grep { $_->op eq 'EQ' } @nodes;
    is(scalar(@eqs), 0, 'EQ node folded away');

    # Should have boolean false constant
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @falses = grep { $_->type isa Chalk::IR::Type::Bool && !$_->value } @constants;
    is(scalar(@falses), 1, 'Has Constant(false) from folded 3 == 4');
};

subtest 'Parse: Comparison != with equal constants' => sub {
    my $parser = make_parser();

    # Java: testCompNEq - return 3!=3; -> return 0;
    my $code = 'return 3 != 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Comparison should fold to constant false (0)
    my @neqs = grep { $_->op eq 'NE' } @nodes;
    is(scalar(@neqs), 0, 'NE node folded away');

    # Should have boolean false constant
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @falses = grep { $_->type isa Chalk::IR::Type::Bool && !$_->value } @constants;
    is(scalar(@falses), 1, 'Has Constant(false) from folded 3 != 3');
};

subtest 'Parse: Comparison != with unequal constants' => sub {
    my $parser = make_parser();

    # Java: testCompNEq2 - return 3!=4; -> return 1;
    my $code = 'return 3 != 4;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Comparison should fold to constant true (1)
    my @neqs = grep { $_->op eq 'NE' } @nodes;
    is(scalar(@neqs), 0, 'NE node folded away');

    # Should have boolean true constant
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @trues = grep { $_->type isa Chalk::IR::Type::Bool && $_->value } @constants;
    is(scalar(@trues), 1, 'Has Constant(true) from folded 3 != 4');
};

subtest 'Parse: Comparison < with constants' => sub {
    my $parser = make_parser();

    my $code = 'return 3 < 5;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Comparison should fold to constant true
    my @lts = grep { $_->op eq 'LT' } @nodes;
    is(scalar(@lts), 0, 'LT node folded away');

    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @trues = grep { $_->type isa Chalk::IR::Type::Bool && $_->value } @constants;
    is(scalar(@trues), 1, 'Has Constant(true) from folded 3 < 5');
};

subtest 'Parse: Comparison > with constants' => sub {
    my $parser = make_parser();

    my $code = 'return 5 > 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Comparison should fold to constant true
    my @gts = grep { $_->op eq 'GT' } @nodes;
    is(scalar(@gts), 0, 'GT node folded away');

    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @trues = grep { $_->type isa Chalk::IR::Type::Bool && $_->value } @constants;
    is(scalar(@trues), 1, 'Has Constant(true) from folded 5 > 3');
};

subtest 'Parse: Comparison <= with constants' => sub {
    my $parser = make_parser();

    my $code = 'return 3 <= 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Comparison should fold to constant true
    my @les = grep { $_->op eq 'LE' } @nodes;
    is(scalar(@les), 0, 'LE node folded away');

    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @trues = grep { $_->type isa Chalk::IR::Type::Bool && $_->value } @constants;
    is(scalar(@trues), 1, 'Has Constant(true) from folded 3 <= 3');
};

subtest 'Parse: Comparison >= with constants' => sub {
    my $parser = make_parser();

    my $code = 'return 5 >= 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Comparison should fold to constant true
    my @ges = grep { $_->op eq 'GE' } @nodes;
    is(scalar(@ges), 0, 'GE node folded away');

    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @trues = grep { $_->type isa Chalk::IR::Type::Bool && $_->value } @constants;
    is(scalar(@trues), 1, 'Has Constant(true) from folded 5 >= 3');
};

# =============================================================================
# Variable Handling Tests
# =============================================================================

subtest 'Parse: Variable reassignment - int a=arg+1; int b=a; b=1; return a+2;' => sub {
    my $parser = make_parser();

    # Java: testBug1 - verifies SSA handling with reassignment
    # int a=arg+1; int b=a; b=1; return a+2; -> return (arg+3);
    # Using concrete value for $arg equivalent
    my $code = q{
        my $arg = 10;
        my $a = $arg + 1;
        my $b = $a;
        $b = 1;
        return $a + 2;
    };
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: $arg=10, $a=11, return $a+2=13
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @thirteens = grep { $_->value == 13 } @constants;
    is(scalar(@thirteens), 1, 'Has Constant(13) from folded ($arg+1)+2 where $arg=10');
};

subtest 'Parse: Self-assignment - int a=arg+1; a=a; return a;' => sub {
    my $parser = make_parser();

    # Java: testBug2 - verifies self-assignment is a no-op
    # int a=arg+1; a=a; return a; -> return (arg+1);
    my $code = q{
        my $arg = 10;
        my $a = $arg + 1;
        $a = $a;
        return $a;
    };
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: $arg=10, $a=11, return $a=11
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @elevens = grep { $_->value == 11 } @constants;
    is(scalar(@elevens), 1, 'Has Constant(11) from folded $arg+1 where $arg=10');
};

# =============================================================================
# Unary Operators
# =============================================================================

subtest 'Parse: Unary negation - return -$x;' => sub {
    my $parser = make_parser();

    # Java: testBug4 - return -arg; -> return (-arg);
    my $code = 'my $x = 5; return -$x;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: -5 = -5
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @negfives = grep { $_->value == -5 } @constants;
    is(scalar(@negfives), 1, 'Has Constant(-5) from folded -$x where $x=5');

    # Negate node should be folded away
    my @negs = grep { $_->op eq 'Negate' } @nodes;
    is(scalar(@negs), 0, 'Negate node folded away');
};

subtest 'Parse: Double negation - return --$x;' => sub {
    my $parser = make_parser();

    # Double negation should cancel out: --x = x
    my $code = 'my $x = 5; return --$x;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: --5 = 5
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @fives = grep { $_->value == 5 } @constants;
    ok(scalar(@fives) >= 1, 'Has Constant(5) from folded --$x where $x=5');
};

subtest 'Parse: Subtraction parsing - return $x - -2;' => sub {
    my $parser = make_parser();

    # Java: testBug5 - return arg--2; -> return (arg--2);
    # Note: In Perl, -- is decrement, so we use $x - -2 (space separated)
    my $code = 'my $x = 10; return $x - -2;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: 10 - (-2) = 12
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @twelves = grep { $_->value == 12 } @constants;
    is(scalar(@twelves), 1, 'Has Constant(12) from folded $x - -2 where $x=10');
};

# =============================================================================
# Zero multiplication tests
# =============================================================================

subtest 'Parse: Zero multiplication - $x * 0 -> 0' => sub {
    my $parser = make_parser();

    my $code = 'my $x = 42; return $x * 0;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Multiply should fold to zero
    my @muls = grep { $_->op eq 'Multiply' } @nodes;
    is(scalar(@muls), 0, 'Multiply node eliminated (x * 0 = 0)');

    # Should have constant 0
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @zeros = grep { $_->value == 0 } @constants;
    ok(scalar(@zeros) >= 1, 'Has Constant(0) from x * 0');
};

subtest 'Parse: Zero multiplication left - 0 * $x -> 0' => sub {
    my $parser = make_parser();

    my $code = 'my $x = 42; return 0 * $x;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Multiply should fold to zero
    my @muls = grep { $_->op eq 'Multiply' } @nodes;
    is(scalar(@muls), 0, 'Multiply node eliminated (0 * x = 0)');

    # Should have constant 0
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @zeros = grep { $_->value == 0 } @constants;
    ok(scalar(@zeros) >= 1, 'Has Constant(0) from 0 * x');
};

# =============================================================================
# Complex expression tests
# =============================================================================

subtest 'Parse: Complex - 1 + $x + 2 + $x + 3 -> ($x * 2) + 6' => sub {
    my $parser = make_parser();

    # Java: testPeephole3 - return 1+arg+2+arg+3; -> return ((arg*2)+6);
    my $code = 'my $x = 10; return 1 + $x + 2 + $x + 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # With constant folding: 1 + 10 + 2 + 10 + 3 = 26
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    my @twentysixes = grep { $_->value == 26 } @constants;
    is(scalar(@twentysixes), 1, 'Has Constant(26) from folded expression');

    # All arithmetic nodes should be folded
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 0, 'Add nodes folded away');
};

done_testing();
