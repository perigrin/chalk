# ABOUTME: Test for Sea of Nodes IR generation - Chapter 2: Arithmetic expressions
# ABOUTME: Validates arithmetic operations (Add, Multiply, Subtract, Divide) with operator precedence

use lib 'lib';
use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Builder');
use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Grammar::Chalk');
use_ok('Chalk::Semiring::Semantic');
use_ok('Chalk::IR::Node::Scope');

# Helper to create parser for testing
# Returns (parser, builder, scope) for easy access to IR
sub make_parser {
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Can't open grammar: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
    my $builder = Chalk::IR::Builder->new();
    my $scope = Chalk::IR::Node::Scope->new();

    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => $grammar,
        env => { ir_builder => $builder, scope => $scope }
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    return ($parser, $builder, $scope);
}

# Parser integration tests - Chapter 2: Arithmetic Operations

subtest 'Parse: Simple addition - return 1+2' => sub {
    my ($parser, $builder, $scope) = make_parser();

    my $code = 'return 1+2;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = $builder->graph;
    ok($graph->node_count > 0, 'Graph has nodes');

    my @nodes = values %{$graph->nodes};

    # Should have Return node
    my @returns = grep { $_->op eq 'Return' } @nodes;
    is(scalar(@returns), 1, 'Has Return node');

    # Should have Add node for 1+2
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 1, 'Has Add node for 1+2');

    # Should have constant nodes for 1 and 2
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 2, 'Has constant nodes for operands');
};

subtest 'Parse: Operator precedence - return 1 + 2 * 3' => sub {
    my ($parser, $builder, $scope) = make_parser();

    # Chapter 2 key example: tests precedence (multiply before add)
    my $code = 'return 1 + 2 * 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = $builder->graph;
    my @nodes = values %{$graph->nodes};

    # Should have both Add and Multiply nodes
    my @adds = grep { $_->op eq 'Add' } @nodes;
    is(scalar(@adds), 1, 'Has Add node');

    my @muls = grep { $_->op eq 'Multiply' } @nodes;
    is(scalar(@muls), 1, 'Has Multiply node');

    # Multiply should be input to Add (precedence)
    # The Add node should reference the Multiply node's result
    my $add = $adds[0];
    my $mul = $muls[0];

    ok($add && $mul, 'Both Add and Multiply nodes exist');

    # Verify Multiply comes before Add in the graph
    # (Add should have Multiply's ID as one of its inputs)
    my @add_inputs = grep { $_ ne '__CONTROL_PLACEHOLDER__' } @{$add->inputs};
    ok((grep { $_ eq $mul->id } @add_inputs),
       'Add node uses Multiply node result (correct precedence)');
};

subtest 'Parse: Complex expression - return 1 + 2 * 3 + -5' => sub {
    my ($parser, $builder, $scope) = make_parser();

    # Chapter 2 complex example from README
    my $code = 'return 1 + 2 * 3 + -5;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = $builder->graph;
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

subtest 'Parse: Subtraction - return 10 - 3' => sub {
    my ($parser, $builder, $scope) = make_parser();

    my $code = 'return 10 - 3;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = $builder->graph;
    my @nodes = values %{$graph->nodes};

    # Should have Subtract node
    my @subs = grep { $_->op eq 'Subtract' } @nodes;
    is(scalar(@subs), 1, 'Has Subtract node');

    # Should have constants for 10 and 3
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 2, 'Has constant nodes for 10 and 3');
};

subtest 'Parse: Division - return 6 / 2' => sub {
    my ($parser, $builder, $scope) = make_parser();

    my $code = 'return 6 / 2;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded');

    my $graph = $builder->graph;
    my @nodes = values %{$graph->nodes};

    # Should have Divide node
    my @divs = grep { $_->op eq 'Divide' } @nodes;
    is(scalar(@divs), 1, 'Has Divide node');

    # Should have constants for 6 and 2
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 2, 'Has constant nodes for 6 and 2');
};

# TODO: Constant folding tests (future peephole optimization)
# These document what SHOULD happen when we implement constant folding
TODO: {
    local $TODO = 'Peephole optimization not implemented yet';

    subtest 'Constant folding: 1 + 2 should fold to 3' => sub {
        my ($parser, $builder, $scope) = make_parser();

        my $code = 'return 1 + 2;';
        my $result = $parser->parse_string($code);

        # With peephole optimization, the Add node with constant operands
        # should be replaced with a single Constant node containing 3
        my $graph = $builder->graph;
        my @nodes = values %{$graph->nodes};

        my @adds = grep { $_->op eq 'Add' } @nodes;
        is(scalar(@adds), 0, 'Add node should be folded away');

        my @constants = grep { $_->op eq 'Constant' && $_->value == 3 } @nodes;
        is(scalar(@constants), 1, 'Should have single Constant(3) node');
    };

    subtest 'Constant folding: 1 + 2 * 3 + -5 should fold to 2' => sub {
        my ($parser, $builder, $scope) = make_parser();

        # Chapter 2 README example: 1 + 6 + -5 = 2
        my $code = 'return 1 + 2 * 3 + -5;';
        my $result = $parser->parse_string($code);

        my $graph = $builder->graph;
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
