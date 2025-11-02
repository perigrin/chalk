#!/usr/bin/env perl
# ABOUTME: Test pure context threading without %values hash dependency
# ABOUTME: Verify nodes read inputs from context, not from separate hash
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 1;
use Chalk::IR::Builder;
use Chalk::IR::Interpreter;

# Test: Complex expression using only context threading
# Build: return (10 + 20) * 2;
# This tests that intermediate results flow through context
{
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    $builder->build_start_node();
    my $ten = $builder->build_constant_node(10);
    my $twenty = $builder->build_constant_node(20);
    my $add = $builder->build_add_node($ten, $twenty);      # 30
    my $two = $builder->build_constant_node(2);
    my $mult = $builder->build_multiply_node($add, $two);   # 60
    $builder->build_return_node($mult);

    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interp->execute();

    is($result, 60, 'Complex expression executes correctly using context threading');
}
