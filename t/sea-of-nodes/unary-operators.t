#!/usr/bin/env perl
# ABOUTME: Tests for unary operators (!, not, -, \) - Issue #109 Phases 1 & 3
# ABOUTME: Verifies IR Builder methods for Not, Negate, and Reference operations

use 5.42.0;
use experimental qw(class);
use Test::More;
use lib 'lib';

plan tests => 16;

# Test 1-4: Builder can create Not, Negate, and Reference nodes
{
    use_ok('Chalk::IR::Builder');
    use_ok('Chalk::IR::Node::Not');
    use_ok('Chalk::IR::Node::Negate');
    use_ok('Chalk::IR::Node::Reference');
}

# Test 5-8: IR::Builder should have build_not_node method
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $operand = $builder->build_constant_node(1);

    my $not_node = $builder->build_not_node($operand);
    ok($not_node, 'build_not_node returns a node');
    is($not_node->op, 'Not', 'Node op is Not');
    is($not_node->operand_id, $operand->id, 'Not node has correct operand_id');

    # Test that Not node is added to graph
    my $graph_node = $builder->graph->nodes->{$not_node->id};
    ok($graph_node, 'Not node is added to graph');
}

# Test 9-11: IR::Builder should have build_negate_node method
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $operand = $builder->build_constant_node(42);

    my $negate_node = $builder->build_negate_node($operand);
    ok($negate_node, 'build_negate_node returns a node');
    is($negate_node->op, 'Negate', 'Node op is Negate');
    is($negate_node->operand_id, $operand->id, 'Negate node has correct operand_id');

    # Test that Negate node is added to graph
    my $graph_node = $builder->graph->nodes->{$negate_node->id};
    ok($graph_node, 'Negate node is added to graph');
}

# Test 12-15: IR::Builder should have build_reference_node method
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $operand = $builder->build_constant_node(5);

    my $reference_node = $builder->build_reference_node($operand);
    ok($reference_node, 'build_reference_node returns a node');
    is($reference_node->op, 'Reference', 'Node op is Reference');
    is($reference_node->operand_id, $operand->id, 'Reference node has correct operand_id');

    # Test that Reference node is added to graph
    my $graph_node = $builder->graph->nodes->{$reference_node->id};
    ok($graph_node, 'Reference node is added to graph');
}
