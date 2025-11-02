#!/usr/bin/env perl
# ABOUTME: Test heap operations threading through Interpreter context+heap
# ABOUTME: Verify Store/Load nodes use Interpreter's context+heap instead of passed hashes
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 2;
use Chalk::IR::Graph;
use Chalk::IR::Node::Store;
use Chalk::IR::Node::Load;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Return;
use Chalk::IR::Interpreter;
use Chalk::IR::Heap;

# Test 1: Store operation writes to Interpreter's heap
{
    my $graph = Chalk::IR::Graph->new();

    # Build: store 42 at address "heap:0", then return the store result
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'main', params => []);
    my $addr = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 'heap:0', type => 'Str');
    my $val = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 42, type => 'Int');
    my $store = Chalk::IR::Node::Store->new(id => 'node_3', inputs => ['node_0', 'node_1', 'node_2']);
    my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_3'], value_id => 'node_3', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($addr);
    $graph->add_node($val);
    $graph->add_node($store);
    $graph->add_node($ret);

    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    $interp->execute();

    # After execution, heap should contain the stored value
    my $stored_value = Chalk::IR::Heap->heap_read($interp->heap, 'heap:0');
    is($stored_value, 42, 'Store operation writes to Interpreter heap');
}

# Test 2: Load operation reads from Interpreter's heap
{
    my $graph = Chalk::IR::Graph->new();

    # Build: store 99 at "heap:1", load from "heap:1", return loaded value
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'main', params => []);
    my $addr = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 'heap:1', type => 'Str');
    my $val = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 99, type => 'Int');
    my $store = Chalk::IR::Node::Store->new(id => 'node_3', inputs => ['node_0', 'node_1', 'node_2']);
    my $load = Chalk::IR::Node::Load->new(id => 'node_4', inputs => ['node_3', 'node_1']);
    my $ret = Chalk::IR::Node::Return->new(id => 'node_5', inputs => ['node_4'], value_id => 'node_4', control_id => 'node_3');

    $graph->add_node($start);
    $graph->add_node($addr);
    $graph->add_node($val);
    $graph->add_node($store);
    $graph->add_node($load);
    $graph->add_node($ret);

    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interp->execute();

    # Load should return the value from heap
    is($result, 99, 'Load operation reads from Interpreter heap and returns value');
}
