#!/usr/bin/env perl
# ABOUTME: Tests for unary operators (!, not, -) - Issue #109 Phase 1
# ABOUTME: Verifies IR Builder methods for Not and Negate operations

use 5.42.0;
use experimental qw(class);
use Test::More;
use lib 'lib';

plan tests => 11;

# Test 1-3: Builder can create Not and Negate nodes
{
    use_ok('Chalk::IR::Builder');
    use_ok('Chalk::IR::Node::Not');
    use_ok('Chalk::IR::Node::Negate');
}

# Test 4-7: IR::Builder should have build_not_node method
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

# Test 8-12: IR::Builder should have build_negate_node method
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
