# ABOUTME: Test for Sea of Nodes IR generation - Chapter 2: Arithmetic expressions
# ABOUTME: Validates arithmetic operations (Add, Multiply, Subtract, Divide) with operator precedence

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

    # Materialize pending nodes into actual graph
    $graph->materialize_pending_nodes();

    return $graph;
}

# Parser integration tests - Chapter 2: Arithmetic Operations

subtest 'Parse: Simple addition - return 1+2 (constant folded)' => sub {
    my $parser = make_parser();

    my $code = 'return 1+2;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');
    ok($graph->node_count > 0, 'Graph has nodes');

    my @nodes = values %{$graph->nodes};

    # Should have Return node
    my @returns = grep { $_->op eq 'Return' } @nodes;
    is(scalar(@returns), 1, 'Has Return node');

    # With constant folding, 1+2 should be folded to Constant(3)
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 0, 'Add node folded away');

    # Should have single constant node with value 3
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    is(scalar(@constants), 1, 'Has single Constant node (folded result)');
    is($constants[0]->value, 3, 'Constant value is 3 (1+2 folded)');
};

SKIP: {
    skip 'Issue #199: Nested expressions not evaluated to IR nodes', 8;

    subtest 'Parse: Operator precedence - return 1 + 2 * 3' => sub {
        my $parser = make_parser();

        # Chapter 2 key example: tests precedence (multiply before add)
        my $code = 'return 1 + 2 * 3;';
        my $result = $parser->parse_string($code);
        ok($result, 'Parse succeeded');

        my $graph = build_graph_from_result($result);
        ok($graph, 'Graph built from result');
        my @nodes = values %{$graph->nodes};

        # Should have both Add and Multiply nodes
        my @adds = grep { $_->op eq 'Add' } @nodes;
        is(scalar(@adds), 1, 'Has Add node');

        my @muls = grep { $_->op eq 'Multiply' } @nodes;
        is(scalar(@muls), 1, 'Has Multiply node');

        # Multiply should be input to Add (precedence)
        my $add = $adds[0];
        my $mul = $muls[0];

        ok($add && $mul, 'Both Add and Multiply nodes exist');

        # Verify Multiply comes before Add in the graph
        # The Add node should reference Multiply via its left or right operand
        TODO: {
            local $TODO = 'Operator precedence not correctly implemented yet';
            my $add_uses_mul = 0;
            if ($add->can('left') && $add->left) {
                $add_uses_mul = 1 if blessed($add->left) && $add->left->id eq $mul->id;
            }
            if ($add->can('right') && $add->right) {
                $add_uses_mul = 1 if blessed($add->right) && $add->right->id eq $mul->id;
            }
            ok($add_uses_mul, 'Add node uses Multiply node result (correct precedence)');
        }
    };
}

SKIP: {
    skip 'Issue #199: Nested expressions not evaluated to IR nodes', 5;

    subtest 'Parse: Complex expression - return 1 + 2 * 3 + -5' => sub {
        my $parser = make_parser();

        # Chapter 2 complex example from README
        my $code = 'return 1 + 2 * 3 + -5;';
        my $result = $parser->parse_string($code);
        ok($result, 'Parse succeeded');

        my $graph = build_graph_from_result($result);
        ok($graph, 'Graph built from result');
        my @nodes = values %{$graph->nodes};

        # Should have two Add nodes (1 + (2*3), result + (-5))
        my @adds = grep { $_->op eq 'Add' } @nodes;
        ok(scalar(@adds) >= 1, 'Has Add nodes');

        # Should have Multiply node for 2*3
        my @muls = grep { $_->op eq 'Multiply' } @nodes;
        is(scalar(@muls), 1, 'Has Multiply node for 2*3');

        # Should have Negate node for -5
        my @negs = grep { $_->op eq 'Negate' } @nodes;
        is(scalar(@negs), 1, 'Has Negate node for -5');
    };
}

subtest 'Parse: Subtraction - return 10 - 3 (constant folded)' => sub {
    my $parser = make_parser();

    my $code = 'return 10 - 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');
    my @nodes = values %{$graph->nodes};

    # With constant folding, 10-3 should be folded to Constant(7)
    my @subs = grep { $_->op eq 'Subtract' } @nodes;
    is(scalar(@subs), 0, 'Subtract node folded away');

    # Should have single constant node with value 7
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    is(scalar(@constants), 1, 'Has single Constant node (folded result)');
    is($constants[0]->value, 7, 'Constant value is 7 (10-3 folded)');
};

subtest 'Parse: Division - return 6 / 2 (constant folded)' => sub {
    my $parser = make_parser();

    my $code = 'return 6 / 2;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');
    my @nodes = values %{$graph->nodes};

    # With constant folding, 6/2 should be folded to Constant(3)
    my @divs = grep { $_->op eq 'Divide' } @nodes;
    is(scalar(@divs), 0, 'Divide node folded away');

    # Should have single constant node with value 3
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    is(scalar(@constants), 1, 'Has single Constant node (folded result)');
    is($constants[0]->value, 3, 'Constant value is 3 (6/2 folded)');
};

# Nested expression constant folding - blocked by Issue #199
SKIP: {
    skip 'Issue #199: Nested expressions not evaluated to IR nodes', 2;

    subtest 'Constant folding: 1 + 2 * 3 + -5 should fold to 2' => sub {
        my $parser = make_parser();

        # Chapter 2 README example: 1 + 6 + -5 = 2
        my $code = 'return 1 + 2 * 3 + -5;';
        my $result = $parser->parse_string($code);

        my $graph = build_graph_from_result($result);
        my @nodes = values %{$graph->nodes};

        # With full constant folding, entire expression folds to 2
        my @constants = grep { $_->op eq 'Constant' && $_->value == 2 } @nodes;
        is(scalar(@constants), 1, 'Should fold to Constant(2)');

        # No arithmetic nodes should remain
        my @arith = grep { $_->op =~ /^(Add|Multiply|Negate)$/ } @nodes;
        is(scalar(@arith), 0, 'All arithmetic nodes folded away');
    };
}

done_testing();
