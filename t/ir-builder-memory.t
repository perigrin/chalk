#!/usr/bin/env perl
# ABOUTME: Test IR Builder integration with Context+Heap+Reference memory model
# ABOUTME: Verify Builder initializes and manages context/heap for variable storage
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 6;
use Chalk::IR::Builder;
use Chalk::IR::Context;
use Chalk::IR::Heap;

# Test 1: Builder initializes with context and heap
{
    my $builder = Chalk::IR::Builder->new();

    ok(defined($builder->context), 'Builder has context accessor');
    ok(defined($builder->heap), 'Builder has heap accessor');
}

# Test 2: Builder context and heap are proper types
{
    my $builder = Chalk::IR::Builder->new();

    ok(ref($builder->context) eq 'CODE', 'context is a closure');
    ok(ref($builder->heap) eq 'CODE', 'heap is a closure');
}

# Test 3: Builder context starts empty
{
    my $builder = Chalk::IR::Builder->new();

    my $value = $builder->context->('nonexistent');
    is($value, undef, 'empty context returns undef for any lookup');
}

# Test 4: Builder heap starts empty
{
    my $builder = Chalk::IR::Builder->new();

    my $value = Chalk::IR::Heap->heap_read($builder->heap, 'heap:0');
    is($value, undef, 'empty heap returns undef for unallocated address');
}
