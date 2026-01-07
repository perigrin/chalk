#!/usr/bin/env perl
# ABOUTME: Test Chalk::Semiring::ChalkIR - IR generation semiring wrapper
# ABOUTME: Verifies that ChalkIR properly encapsulates Composite(SPPF, Semantic) configuration
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use lib 'lib';
use Test::More;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;  # Pre-load Chalk rule classes for semantic actions
use Chalk::Semiring::ChalkIR;

# Load Chalk grammar from BNF
my $bnf_file = 'grammar/chalk.bnf';
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

# Test 1: ChalkIR can be instantiated with a grammar
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    ok($ir_semiring, 'ChalkIR semiring can be created');
    isa_ok($ir_semiring, 'Chalk::Semiring::ChalkIR', 'ChalkIR');
    # ChalkIR uses composition, not inheritance - it delegates to Composite
    ok($ir_semiring->composite, 'ChalkIR has a composite semiring');
    isa_ok($ir_semiring->composite, 'Chalk::Semiring::Composite', 'ChalkIR wraps a Composite');
}

# Test 2: ChalkIR has a scope accessor (new architecture - replaces builder)
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    my $scope = $ir_semiring->scope;
    ok($scope, 'ChalkIR has a scope');
    isa_ok($scope, 'Chalk::IR::Node::Scope', 'Scope is an IR::Node::Scope');
}

# Test 3: ChalkIR has mul_id and add_id (from Composite)
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    ok($ir_semiring->mul_id, 'ChalkIR has mul_id');
    ok($ir_semiring->add_id, 'ChalkIR has add_id');
    isa_ok($ir_semiring->mul_id, 'Chalk::Semiring::CompositeElement', 'mul_id is CompositeElement');
    isa_ok($ir_semiring->add_id, 'Chalk::Semiring::CompositeElement', 'add_id is CompositeElement');
}

# Test 4: ChalkIR can be used with Parser
{
    use Chalk::Parser;

    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $ir_semiring
    );

    ok($parser, 'Parser can be created with ChalkIR semiring');
}

# Test 5: ChalkIR grammar accessor works
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    is($ir_semiring->grammar, $grammar, 'ChalkIR returns the same grammar object');
}

# ==============================================================================
# NEW TESTS: Comprehensive parsing tests using Chalk grammar
# These tests verify that ChalkIR actually generates IR for Chalk code
# New architecture: IR nodes returned via parse result focus, not graph
# ==============================================================================

# Helper: Parse Chalk code with ChalkIR and return IR root node
sub parse_chalk_with_ir {
    my ($code) = @_;

    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $ir_semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $parse_result = $parser->parse_string($code);
    return (undef, undef) unless $parse_result;

    # Extract IR from parse result's context focus (new architecture)
    my $ir_root = undef;
    if ($parse_result->can('context')) {
        my $ctx = $parse_result->context;
        if ($ctx && $ctx->can('focus')) {
            $ir_root = $ctx->focus;
        }
    }

    return ($parse_result, $ir_root);
}

# Helper: Collect all nodes reachable from root by traversing control/value edges
sub collect_nodes {
    my ($root) = @_;
    return {} unless $root && ref($root) && $root->can('id');

    my %nodes;
    my @queue = ($root);
    my %seen;

    while (@queue) {
        my $node = shift @queue;
        next unless $node && ref($node) && $node->can('id');

        my $id = $node->id;
        next if $seen{$id}++;

        $nodes{$id} = $node;

        # Traverse control edge
        if ($node->can('control')) {
            my $ctrl = $node->control;
            push @queue, $ctrl if $ctrl && ref($ctrl);
        }

        # Traverse value edge
        if ($node->can('value')) {
            my $val = $node->value;
            push @queue, $val if $val && ref($val);
        }

        # Traverse return_nodes for Stop (per Chapter 18)
        if ($node->can('return_nodes') && $node->return_nodes) {
            for my $ret ($node->return_nodes->@*) {
                push @queue, $ret if $ret && ref($ret);
            }
        }
    }

    return \%nodes;
}

# Helper: Count nodes of specific types
sub count_node_types {
    my ($nodes, @types) = @_;
    my %counts;

    for my $type (@types) {
        my $count = grep {
            $_->can('op') && $_->op eq $type
        } values %$nodes;
        $counts{$type} = $count;
    }

    return \%counts;
}

# Test 6: Parse simple constant return and verify IR
{
    my $code = 'return 42;';
    my ($result, $ir_root) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: simple constant return parses');
    ok($ir_root, 'ChalkIR: IR root exists after parsing constant');

    if ($ir_root) {
        # Per Chapter 18: Program always returns Stop which collects all returns
        is($ir_root->op, 'Stop', 'ChalkIR: root is Stop node (per Chapter 18)');

        my $nodes = collect_nodes($ir_root);
        my $node_count = scalar(keys %$nodes);
        ok($node_count > 0, "ChalkIR: collected nodes (found $node_count)");

        my $counts = count_node_types($nodes, 'Constant', 'Return', 'Start', 'Stop');
        ok($counts->{Constant} > 0, "ChalkIR: has Constant node");
        ok($counts->{Return} > 0, "ChalkIR: has Return node");
        ok($counts->{Start} > 0, "ChalkIR: has Start node");
    }
}

# Test 7: Parse variable declaration and verify IR
{
    my $code = 'my $x = 5;';
    my ($result, $ir_root) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: variable declaration parses');
    ok($ir_root, 'ChalkIR: IR root exists after parsing variable');

    if ($ir_root) {
        # Per Chapter 18: Program always returns Stop which collects all returns
        is($ir_root->op, 'Stop', 'ChalkIR: root is Stop node (per Chapter 18)');

        my $nodes = collect_nodes($ir_root);
        my $node_count = scalar(keys %$nodes);
        ok($node_count > 0, "ChalkIR: collected nodes for variable (found $node_count)");

        # In SSA, assignments return RHS values (not Store nodes)
        # Store nodes are only for memory (heap) operations, not variable bindings
        # Note: Without explicit return, Start is not reachable from Stop
        my $counts = count_node_types($nodes, 'Constant', 'Stop');
        ok($counts->{Constant} > 0, "ChalkIR: has Constant node for value");
        ok($counts->{Stop} > 0, "ChalkIR: has Stop node");
    }
}

# Test 8: Verify Stop node structure (assignments without explicit return)
{
    my $code = 'my $x = 42;';
    my ($result, $ir_root) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: parse succeeds');
    ok($ir_root, 'ChalkIR: has IR root');

    # For statements without explicit return, ir_root is Stop (not Return)
    # In SSA, assignments don't create Store nodes - they just bind values in scope
    if ($ir_root && $ir_root->can('op')) {
        is($ir_root->op, 'Stop', 'ChalkIR: root is Stop for non-return statement');
    }
}

# Test 9: Verify explicit return value chain structure
{
    # Use explicit return to test Return node value chain
    my $code = 'return 42;';
    my ($result, $ir_root) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: parse succeeds');
    ok($ir_root, 'ChalkIR: has IR root');

    # For explicit return, Stop node has return_nodes containing Return
    if ($ir_root && $ir_root->can('return_nodes') && $ir_root->return_nodes) {
        my $return_node = $ir_root->return_nodes->[0];
        ok($return_node, 'ChalkIR: Stop has return node');

        if ($return_node && $return_node->can('value')) {
            my $value = $return_node->value;
            ok($value, 'ChalkIR: Return has value');

            if ($value && $value->can('op')) {
                is($value->op, 'Constant', 'ChalkIR: Return value is Constant');
                is($value->value, 42, 'ChalkIR: Constant value is 42');
            }
        }
    }
}

# Test 10: Verify refaddr-based node IDs
{
    my $code = 'my $x = 42;';
    my ($result, $ir_root) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: parse succeeds');
    ok($ir_root, 'ChalkIR: has IR root');

    if ($ir_root) {
        my $id = $ir_root->id;
        ok($id, 'ChalkIR: Return node has id');
        like($id, qr/^\d+$/, 'ChalkIR: Return id is numeric (refaddr)');
    }
}

# Test 11: Verify parse result has proper structure
{
    my $code = 'return 42;';
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $ir_semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $parse_result = $parser->parse_string($code);
    ok($parse_result, 'ChalkIR: parse returns result');

    if ($parse_result) {
        isa_ok($parse_result, 'Chalk::Semiring::CompositeElement', 'ChalkIR: parse result is CompositeElement');

        ok($parse_result->can('context'), 'ChalkIR: parse result has context method');

        if ($parse_result->can('context')) {
            my $ctx = $parse_result->context;
            ok(defined($ctx), 'ChalkIR: context is defined');

            if ($ctx && $ctx->can('focus')) {
                my $focus = $ctx->focus;
                ok(defined($focus), 'ChalkIR: focus is defined');
                ok($focus && $focus->can('id'), 'ChalkIR: focus has id method') if defined($focus);
            }
        }
    }
}

done_testing();
