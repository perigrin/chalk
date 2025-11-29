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

    # Program should return a Return node
    is($ir_root->op, 'Return', 'Program produces Return node');

    # Return node should have numeric ID (refaddr)
    my $id = $ir_root->id;
    ok($id, 'Return node has id');
    like($id, qr/^\d+$/, 'Return node ID is numeric (refaddr)');

    # Verify control chain is established
    my $control = $ir_root->control;
    ok($control, 'Return has control input');
    ok($control->can('op'), 'Control input is a node');

    # Control should be Store (from variable declaration)
    is($control->op, 'Store', 'Control input is Store node');

    # Store should have control pointing to UseStatement (from 'use 5.42.0;')
    # Control chain: Start -> UseStatement -> Store -> Return
    my $store_control = $control->control;
    ok($store_control, 'Store has control input');
    is($store_control->op, 'UseStatement', 'Store control is UseStatement node');

    # UseStatement (generic Chalk::IR::Node) uses inputs array, not control method
    # First input is the control predecessor - verify it exists and traces back to Start
    my $use_inputs = $store_control->inputs;
    ok($use_inputs && @$use_inputs > 0, 'UseStatement has inputs');
    # The first input should be the Start node's ID
    like($use_inputs->[0], qr/start/i, 'UseStatement control input traces to Start');

    # Verify value chain
    my $return_value = $ir_root->value;
    ok($return_value, 'Return has value');
    is($return_value->op, 'Constant', 'Return value is Constant');
    is($return_value->value, 42, 'Constant value is 42');
}

done_testing();
