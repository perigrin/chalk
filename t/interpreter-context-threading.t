#!/usr/bin/env perl
# ABOUTME: Test context threading through Interpreter execution
# ABOUTME: Verify node results are stored in context during execution
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 3;
use Chalk::IR::Graph;
use Chalk::IR::Builder;
use Chalk::IR::Interpreter;

# Test 1: Simple constant execution stores result in context
{
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build: return 42;
    $builder->build_start_node();
    my $const = $builder->build_constant_node(42);
    $builder->build_return_node($const);

    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interp->execute();

    # After execution, context should contain node results
    my $const_id = $const->id;
    my $value_in_context = $interp->context->("node:$const_id");

    is($result, 42, 'execution returns correct result');
    is($value_in_context, 42, 'constant value stored in context with node: namespace');
}

# Test 2: Addition execution stores intermediate results in context
{
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build: return 10 + 32;
    $builder->build_start_node();
    my $left = $builder->build_constant_node(10);
    my $right = $builder->build_constant_node(32);
    my $add = $builder->build_add_node($left, $right);
    $builder->build_return_node($add);

    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interp->execute();

    # After execution, all node results should be in context
    my $add_id = $add->id;
    my $add_value = $interp->context->("node:$add_id");

    is($add_value, 42, 'addition result stored in context with node: namespace');
}
