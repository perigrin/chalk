#!/usr/bin/env perl
# ABOUTME: Test basic Heap abstraction (closure-based mutable storage)
# ABOUTME: Verify empty_heap, heap_alloc, heap_read, and heap_write operations work correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 26;
use Chalk::IR::Heap;

# Test 1: empty_heap returns a closure
{
    my $heap = Chalk::IR::Heap->empty_heap();

    ok(ref($heap) eq 'CODE', 'empty_heap returns a code reference');
}

# Test 2: heap_alloc allocates a cell and returns new heap + address
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my ($heap1, $addr) = Chalk::IR::Heap->heap_alloc($heap, 42);

    ok(ref($heap1) eq 'CODE', 'heap_alloc returns new heap as code reference');
    ok(defined($addr), 'heap_alloc returns an address');
    like($addr, qr/^heap:\d+$/, 'address has correct format (heap:N)');
}

# Test 3: heap_read retrieves allocated value
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my ($heap1, $addr) = Chalk::IR::Heap->heap_alloc($heap, 100);

    is(Chalk::IR::Heap->heap_read($heap1, $addr), 100, 'heap_read retrieves allocated value');
}

# Test 4: heap_read on unallocated address returns undef
{
    my $heap = Chalk::IR::Heap->empty_heap();

    is(Chalk::IR::Heap->heap_read($heap, 'heap:999'), undef, 'heap_read on unallocated address returns undef');
}

# Test 5: multiple allocations work correctly
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my ($heap1, $addr1) = Chalk::IR::Heap->heap_alloc($heap, 'first');
    my ($heap2, $addr2) = Chalk::IR::Heap->heap_alloc($heap1, 'second');
    my ($heap3, $addr3) = Chalk::IR::Heap->heap_alloc($heap2, 'third');

    is(Chalk::IR::Heap->heap_read($heap3, $addr1), 'first', 'first allocation readable');
    is(Chalk::IR::Heap->heap_read($heap3, $addr2), 'second', 'second allocation readable');
    is(Chalk::IR::Heap->heap_read($heap3, $addr3), 'third', 'third allocation readable');

    # Verify addresses are different
    isnt($addr1, $addr2, 'first and second addresses are different');
    isnt($addr2, $addr3, 'second and third addresses are different');
    isnt($addr1, $addr3, 'first and third addresses are different');
}

# Test 6: heap_write updates a cell and returns new heap
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my ($heap1, $addr) = Chalk::IR::Heap->heap_alloc($heap, 'original');
    my $heap2 = Chalk::IR::Heap->heap_write($heap1, $addr, 'updated');

    ok(ref($heap2) eq 'CODE', 'heap_write returns new heap as code reference');
    is(Chalk::IR::Heap->heap_read($heap2, $addr), 'updated', 'heap_write updates the value');
}

# Test 7: heap immutability - old heap unchanged after alloc
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my ($heap1, $addr) = Chalk::IR::Heap->heap_alloc($heap, 42);

    # Old heap should still return undef for the address
    is(Chalk::IR::Heap->heap_read($heap, $addr), undef, 'original heap unchanged after alloc');
    # New heap should have the value
    is(Chalk::IR::Heap->heap_read($heap1, $addr), 42, 'new heap has allocated value');
}

# Test 8: heap immutability - old heap unchanged after write
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my ($heap1, $addr) = Chalk::IR::Heap->heap_alloc($heap, 'original');
    my $heap2 = Chalk::IR::Heap->heap_write($heap1, $addr, 'modified');

    is(Chalk::IR::Heap->heap_read($heap1, $addr), 'original', 'heap1 unchanged after write');
    is(Chalk::IR::Heap->heap_read($heap2, $addr), 'modified', 'heap2 has new value');
}

# Test 9: heap stores various value types
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my ($h1, $a1) = Chalk::IR::Heap->heap_alloc($heap, 'string');
    my ($h2, $a2) = Chalk::IR::Heap->heap_alloc($h1, 3.14);
    my ($h3, $a3) = Chalk::IR::Heap->heap_alloc($h2, { key => 'value' });
    my ($h4, $a4) = Chalk::IR::Heap->heap_alloc($h3, [1, 2, 3]);

    is(Chalk::IR::Heap->heap_read($h4, $a1), 'string', 'heap stores strings');
    is(Chalk::IR::Heap->heap_read($h4, $a2), 3.14, 'heap stores numbers');
    is_deeply(Chalk::IR::Heap->heap_read($h4, $a3), { key => 'value' }, 'heap stores hash refs');
    is_deeply(Chalk::IR::Heap->heap_read($h4, $a4), [1, 2, 3], 'heap stores array refs');
}

# Test 10: writing to unallocated address has no effect
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my $heap1 = Chalk::IR::Heap->heap_write($heap, 'heap:999', 'value');

    is(Chalk::IR::Heap->heap_read($heap1, 'heap:999'), undef, 'writing to unallocated address has no effect');
}

# Test 11: sequential writes to same address
{
    my $heap = Chalk::IR::Heap->empty_heap();
    my ($h1, $addr) = Chalk::IR::Heap->heap_alloc($heap, 'v1');
    my $h2 = Chalk::IR::Heap->heap_write($h1, $addr, 'v2');
    my $h3 = Chalk::IR::Heap->heap_write($h2, $addr, 'v3');

    is(Chalk::IR::Heap->heap_read($h3, $addr), 'v3', 'latest write wins');
    is(Chalk::IR::Heap->heap_read($h2, $addr), 'v2', 'intermediate heap preserved');
    is(Chalk::IR::Heap->heap_read($h1, $addr), 'v1', 'original heap preserved');
}
