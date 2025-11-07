#!/usr/bin/env perl
# ABOUTME: Test CEK dataflow interpreter basic structure and instantiation
# ABOUTME: Tests CEKDataflow class constructor and basic methods
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 4;
use Chalk::IR::Graph;
use Chalk::Interpreter::CEKDataflow;

# Test module can be loaded
use_ok('Chalk::Interpreter::CEKDataflow');

# Create a simple graph for testing
my $graph = Chalk::IR::Graph->new();

# Test CEKDataflow can be instantiated with a graph
my $interpreter = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
ok(defined $interpreter, 'CEKDataflow interpreter instantiated');
isa_ok($interpreter, 'Chalk::Interpreter::CEKDataflow', 'correct class');

# Test interpreter has execute method
can_ok($interpreter, 'execute');
