#!/usr/bin/env perl
# ABOUTME: Tests CEK interpreter environment immutability guarantees
# ABOUTME: Verifies that extend_node, extend_variable, and extend_heap create new environments without mutating originals
use 5.42.0;
use lib 'lib';
use Test::More tests => 13;
use Chalk::Interpreter::Environment;

# Test 1: extend_node creates new environment
my $env1 = Chalk::Interpreter::Environment->new();
$env1->set_node('x', 10);
my $env2 = $env1->extend_node('y', 20);
isnt($env1, $env2, "extend_node should create new environment object");

# Test 2: extend_node preserves old environment
my $env3 = Chalk::Interpreter::Environment->new();
$env3->set_node('x', 10);
my $env4 = $env3->extend_node('x', 20);
is($env3->lookup_node('x'), 10, "Original environment unchanged after extend_node");
is($env4->lookup_node('x'), 20, "New environment has new value");

# Test 3: extend_variable creates new environment
my $env5 = Chalk::Interpreter::Environment->new();
$env5->set_variable('x', 10);
my $env6 = $env5->extend_variable('y', 20);
isnt($env5, $env6, "extend_variable should create new environment object");

# Test 4: extend_variable preserves old environment
my $env7 = Chalk::Interpreter::Environment->new();
$env7->set_variable('x', 10);
my $env8 = $env7->extend_variable('x', 20);
is($env7->lookup_variable('x'), 10, "Original environment unchanged after extend_variable");
is($env8->lookup_variable('x'), 20, "New environment has new value");

# Test 5: extend_heap creates new environment
my $env9 = Chalk::Interpreter::Environment->new();
my $heap_id = $env9->allocate_heap_id();
$env9->set_heap($heap_id, 'key1', 100);
my $env10 = $env9->extend_heap($heap_id, 'key2', 200);
isnt($env9, $env10, "extend_heap should create new environment object");

# Test 6: extend_heap preserves old environment
my $env11 = Chalk::Interpreter::Environment->new();
my $heap_id2 = $env11->allocate_heap_id();
$env11->set_heap($heap_id2, 'key1', 100);
my $env12 = $env11->extend_heap($heap_id2, 'key1', 200);
is($env11->lookup_heap($heap_id2, 'key1'), 100, "Original environment unchanged after extend_heap");
is($env12->lookup_heap($heap_id2, 'key1'), 200, "New environment has new value");

# Test 7: Multiple heap mutations with immutability
my $env13 = Chalk::Interpreter::Environment->new();
my $heap_id3 = $env13->allocate_heap_id();
$env13->set_heap($heap_id3, 'x', 10);

my $env14 = $env13->extend_heap($heap_id3, 'y', 20);
my $env15 = $env14->extend_heap($heap_id3, 'z', 30);

is($env13->lookup_heap($heap_id3, 'x'), 10, "First environment has only x");
is($env13->lookup_heap($heap_id3, 'y'), undef, "First environment doesn't have y");

is($env14->lookup_heap($heap_id3, 'y'), 20, "Second environment has y");
is($env15->lookup_heap($heap_id3, 'z'), 30, "Third environment has z");
