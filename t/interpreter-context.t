#!/usr/bin/env perl
# ABOUTME: Test Interpreter integration with Context+Heap+Reference memory model
# ABOUTME: Verify Interpreter initializes and manages context/heap for execution
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 6;
use Chalk::IR::Graph;
use Chalk::IR::Interpreter;
use Chalk::IR::Context;
use Chalk::IR::Heap;

# Test 1: Interpreter has context accessor
{
    my $graph = Chalk::IR::Graph->new();
    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    ok(defined($interp->context), 'Interpreter has context accessor');
}

# Test 2: Interpreter has heap accessor
{
    my $graph = Chalk::IR::Graph->new();
    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    ok(defined($interp->heap), 'Interpreter has heap accessor');
}

# Test 3: Interpreter context is a closure
{
    my $graph = Chalk::IR::Graph->new();
    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    ok(ref($interp->context) eq 'CODE', 'context is a closure');
}

# Test 4: Interpreter heap is a closure
{
    my $graph = Chalk::IR::Graph->new();
    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    ok(ref($interp->heap) eq 'CODE', 'heap is a closure');
}

# Test 5: Interpreter context starts empty
{
    my $graph = Chalk::IR::Graph->new();
    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    my $value = $interp->context->('nonexistent');
    is($value, undef, 'empty context returns undef for any lookup');
}

# Test 6: Interpreter heap starts empty
{
    my $graph = Chalk::IR::Graph->new();
    my $interp = Chalk::IR::Interpreter->new(graph => $graph);
    my $value = Chalk::IR::Heap->heap_read($interp->heap, 'heap:0');
    is($value, undef, 'empty heap returns undef for unallocated address');
}
