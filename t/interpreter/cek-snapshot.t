#!/usr/bin/env perl
# ABOUTME: Tests CEK interpreter environment snapshot and restore functionality
# ABOUTME: Verifies that node bindings, variable bindings, and heap state can be captured and restored
use 5.42.0;
use lib 'lib';
use Test::More tests => 13;
use Chalk::Interpreter::Environment;
use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::ArrayStore;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;

# Test 1: Environment snapshot captures node bindings
my $env1 = Chalk::Interpreter::Environment->new();
$env1->set_node('node_1', 42);
$env1->set_node('node_2', 100);

my $snapshot1 = $env1->snapshot();
is($snapshot1->{node_bindings}{node_1}, 42, "Snapshot captures node_1 value");
is($snapshot1->{node_bindings}{node_2}, 100, "Snapshot captures node_2 value");

# Test 2: Environment restore recreates node bindings
my $env1_restored = $env1->restore_from_snapshot($snapshot1);
is($env1_restored->lookup_node('node_1'), 42, "Restored environment has node_1 value");
is($env1_restored->lookup_node('node_2'), 100, "Restored environment has node_2 value");

# Test 3: Environment snapshot captures variable bindings
my $env2 = Chalk::Interpreter::Environment->new();
$env2->set_variable('x', 10);
$env2->set_variable('y', 20);

my $snapshot2 = $env2->snapshot();
is($snapshot2->{var_bindings}{x}, 10, "Snapshot captures variable x");
is($snapshot2->{var_bindings}{y}, 20, "Snapshot captures variable y");

# Test 4: Environment restore recreates variable bindings
my $env2_restored = $env2->restore_from_snapshot($snapshot2);
is($env2_restored->lookup_variable('x'), 10, "Restored environment has variable x");
is($env2_restored->lookup_variable('y'), 20, "Restored environment has variable y");

# Test 5: Environment snapshot captures heap bindings
my $env3 = Chalk::Interpreter::Environment->new();
my $heap_id1 = $env3->allocate_heap_id();
my $heap_id2 = $env3->allocate_heap_id();
$env3->set_heap($heap_id1, 0, 'first');
$env3->set_heap($heap_id1, 1, 'second');
$env3->set_heap($heap_id2, 'key', 'value');

my $snapshot3 = $env3->snapshot();
is($snapshot3->{heap_bindings}{$heap_id1}{0}, 'first', "Snapshot captures heap element");
is($snapshot3->{heap_bindings}{$heap_id2}{key}, 'value', "Snapshot captures hash element");
is($snapshot3->{next_heap_id}, 3, "Snapshot captures next_heap_id counter");

# Test 6: Environment restore recreates heap bindings
my $env3_restored = $env3->restore_from_snapshot($snapshot3);
is($env3_restored->lookup_heap($heap_id1, 0), 'first', "Restored heap has array element");
is($env3_restored->lookup_heap($heap_id2, 'key'), 'value', "Restored heap has hash element");

