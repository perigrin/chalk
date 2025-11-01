#!/usr/bin/env perl
# ABOUTME: Integration tests for Context+Heap+Reference working together
# ABOUTME: Verify complex scenarios including aliasing, namespacing, and immutability
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 15;
use Chalk::IR::Context;
use Chalk::IR::Heap;
use Chalk::IR::Reference;

# Test 1: Aliasing - multiple labels pointing to same heap cell
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    # Create initial reference
    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'x', 100);

    # Create alias by manually binding same address
    my $addr = $ctx1->('x');
    my $ctx2 = Chalk::IR::Context->extend_context($ctx1, 'y', $addr);

    # Both labels should read same value
    is(Chalk::IR::Reference->ref_read($ctx2, $heap1, 'x'), 100, 'x reads original value');
    is(Chalk::IR::Reference->ref_read($ctx2, $heap1, 'y'), 100, 'y reads same value (aliasing)');

    # Writing through one alias affects the other
    my $heap2 = Chalk::IR::Reference->ref_write($ctx2, $heap1, 'x', 999);
    is(Chalk::IR::Reference->ref_read($ctx2, $heap2, 'x'), 999, 'x updated');
    is(Chalk::IR::Reference->ref_read($ctx2, $heap2, 'y'), 999, 'y sees update (aliasing)');
}

# Test 2: Namespace isolation with references
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my $var_x = Chalk::IR::Context->make_label('var', 'x');
    my $temp_x = Chalk::IR::Context->make_label('temp', 'x');

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, $var_x, 'var_value');
    my ($ctx2, $heap2) = Chalk::IR::Reference->ref_new($ctx1, $heap1, $temp_x, 'temp_value');

    # Namespaces prevent collision
    is(Chalk::IR::Reference->ref_read($ctx2, $heap2, $var_x), 'var_value', 'var:x has correct value');
    is(Chalk::IR::Reference->ref_read($ctx2, $heap2, $temp_x), 'temp_value', 'temp:x has correct value');

    # Updates are independent
    my $heap3 = Chalk::IR::Reference->ref_write($ctx2, $heap2, $var_x, 'updated_var');
    is(Chalk::IR::Reference->ref_read($ctx2, $heap3, $var_x), 'updated_var', 'var:x updated');
    is(Chalk::IR::Reference->ref_read($ctx2, $heap3, $temp_x), 'temp_value', 'temp:x unchanged');
}

# Test 3: Complex workflow - simulating local variables and updates
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    # Initialize counter and accumulator
    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'counter', 0);
    my ($ctx2, $heap2) = Chalk::IR::Reference->ref_new($ctx1, $heap1, 'accum', 0);

    # Simulate loop: counter++, accum += counter (3 iterations)
    my $heap3 = Chalk::IR::Reference->ref_write($ctx2, $heap2, 'counter', 1);
    $heap3 = Chalk::IR::Reference->ref_write($ctx2, $heap3, 'accum', 1);

    my $heap4 = Chalk::IR::Reference->ref_write($ctx2, $heap3, 'counter', 2);
    $heap4 = Chalk::IR::Reference->ref_write($ctx2, $heap4, 'accum', 3);

    my $heap5 = Chalk::IR::Reference->ref_write($ctx2, $heap4, 'counter', 3);
    $heap5 = Chalk::IR::Reference->ref_write($ctx2, $heap5, 'accum', 6);

    is(Chalk::IR::Reference->ref_read($ctx2, $heap5, 'counter'), 3, 'counter = 3');
    is(Chalk::IR::Reference->ref_read($ctx2, $heap5, 'accum'), 6, 'accum = 6');
}

# Test 4: Time-travel through heap history
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'value', 'v1');
    my $heap2 = Chalk::IR::Reference->ref_write($ctx1, $heap1, 'value', 'v2');
    my $heap3 = Chalk::IR::Reference->ref_write($ctx1, $heap2, 'value', 'v3');

    # Can read from any historical heap state
    is(Chalk::IR::Reference->ref_read($ctx1, $heap1, 'value'), 'v1', 'heap1 has v1');
    is(Chalk::IR::Reference->ref_read($ctx1, $heap2, 'value'), 'v2', 'heap2 has v2');
    is(Chalk::IR::Reference->ref_read($ctx1, $heap3, 'value'), 'v3', 'heap3 has v3');
}

# Test 5: Mixed direct heap access and references
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    # Create reference via high-level API
    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'x', 'ref_value');

    # Also directly allocate on heap (lower level)
    my ($heap2, $direct_addr) = Chalk::IR::Heap->heap_alloc($heap1, 'direct_value');

    # Both should work
    is(Chalk::IR::Reference->ref_read($ctx1, $heap2, 'x'), 'ref_value', 'reference works');
    is(Chalk::IR::Heap->heap_read($heap2, $direct_addr), 'direct_value', 'direct heap access works');
}
