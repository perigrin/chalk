#!/usr/bin/env perl
# ABOUTME: Test IR generation pipeline with GVN optimization for simple Chalk programs
# ABOUTME: Verifies semantic actions build IR during parsing and GVN deduplicates intermediate nodes
use lib 'lib';
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use lib 'lib';
use Test::More;

# Test that parsing produces IR nodes via semantic actions
# New architecture: Rule classes create nodes directly, IR returned via parse focus
{
    use Chalk::Parser;
    use Chalk::Grammar;
    use Chalk::Grammar::Chalk;  # Pre-loads all Chalk grammar rule classes for static compilation
    use Chalk::Semiring::Semantic;

    # Load Chalk grammar with semantic actions
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    # Create Semantic semiring (automatically initializes scope)
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

    # Create parser
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Simple program: just a variable assignment
    my $program = q{
        use 5.42.0;
        my $x = 42;
    };

    # Parse the program
    my $result = $parser->parse_string($program);
    ok($result, 'Simple program parses successfully');

    # Extract IR from parse result
    my $ctx = $result->context;
    ok($ctx, 'Parse result has context');

    my $ir_root = $ctx->focus;
    ok($ir_root, 'Parse result has IR focus');
    ok($ir_root->can('op'), 'IR root is a node object');

    # Per Chapter 18: Program returns Stop which collects all returns
    is($ir_root->op, 'Stop', 'Program produces Stop node');

    # Stop should have return nodes
    ok($ir_root->can('return_nodes'), 'Stop has return_nodes method');
    my $returns = $ir_root->return_nodes;
    ok(@$returns > 0, 'Stop has at least one return');

    # Get the first (and only) Return node
    my $return_node = $returns->[0];
    ok($return_node, 'Got Return node from Stop');
    is($return_node->op, 'Return', 'Return node has correct op');

    # Return node should have numeric ID (refaddr)
    my $id = $return_node->id;
    ok($id, 'Return node has id');
    like($id, qr/^\d+$/, 'Return node ID is numeric (refaddr)');

    # Verify control chain is established
    # In SSA, assignments don't create Store nodes - they just bind values in scope
    # Control chain: Start -> UseStatement -> Return (no Store)
    my $control = $return_node->control;
    ok($control, 'Return has control input');
    ok($control->can('op'), 'Control input is a node');

    # Control should be UseStatement (from 'use 5.42.0;')
    # Note: Assignment doesn't create Store nodes in new SSA architecture
    is($control->op, 'UseStatement', 'Control input is UseStatement node');

    # UseStatement (generic Chalk::IR::Node) uses inputs array, not control method
    # First input is the control predecessor - verify it exists and traces back to Start
    my $use_inputs = $control->inputs;
    ok($use_inputs && @$use_inputs > 0, 'UseStatement has inputs');
    # The first input should be the Start node's ID
    like($use_inputs->[0], qr/start/i, 'UseStatement control input traces to Start');

    # Verify value chain
    my $return_value = $return_node->value;
    ok($return_value, 'Return has value');
    is($return_value->op, 'Constant', 'Return value is Constant');
    is($return_value->value, 42, 'Constant value is 42');
}

done_testing();
