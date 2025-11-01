#!/usr/bin/env perl
# ABOUTME: Test reference operations integrating Context and Heap
# ABOUTME: Verify ref_new, ref_read, and ref_write operations work correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 22;
use Chalk::IR::Context;
use Chalk::IR::Heap;
use Chalk::IR::Reference;

# Test 1: ref_new creates reference (allocates + binds)
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'x', 42);

    ok(ref($ctx1) eq 'CODE', 'ref_new returns new context as closure');
    ok(ref($heap1) eq 'CODE', 'ref_new returns new heap as closure');
}

# Test 2: ref_read retrieves value through reference
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'x', 100);
    my $value = Chalk::IR::Reference->ref_read($ctx1, $heap1, 'x');

    is($value, 100, 'ref_read retrieves correct value');
}

# Test 3: ref_write updates value through reference
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'x', 'original');
    my $heap2 = Chalk::IR::Reference->ref_write($ctx1, $heap1, 'x', 'updated');

    ok(ref($heap2) eq 'CODE', 'ref_write returns new heap');
    is(Chalk::IR::Reference->ref_read($ctx1, $heap2, 'x'), 'updated', 'ref_write updates value');
}

# Test 4: multiple references work independently
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'x', 10);
    my ($ctx2, $heap2) = Chalk::IR::Reference->ref_new($ctx1, $heap1, 'y', 20);
    my ($ctx3, $heap3) = Chalk::IR::Reference->ref_new($ctx2, $heap2, 'z', 30);

    is(Chalk::IR::Reference->ref_read($ctx3, $heap3, 'x'), 10, 'first reference readable');
    is(Chalk::IR::Reference->ref_read($ctx3, $heap3, 'y'), 20, 'second reference readable');
    is(Chalk::IR::Reference->ref_read($ctx3, $heap3, 'z'), 30, 'third reference readable');
}

# Test 5: ref_write preserves other references
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'x', 100);
    my ($ctx2, $heap2) = Chalk::IR::Reference->ref_new($ctx1, $heap1, 'y', 200);

    my $heap3 = Chalk::IR::Reference->ref_write($ctx2, $heap2, 'x', 999);

    is(Chalk::IR::Reference->ref_read($ctx2, $heap3, 'x'), 999, 'written reference updated');
    is(Chalk::IR::Reference->ref_read($ctx2, $heap3, 'y'), 200, 'other reference unchanged');
}

# Test 6: reference immutability - old heap unchanged
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'x', 'v1');
    my $heap2 = Chalk::IR::Reference->ref_write($ctx1, $heap1, 'x', 'v2');

    is(Chalk::IR::Reference->ref_read($ctx1, $heap1, 'x'), 'v1', 'old heap unchanged');
    is(Chalk::IR::Reference->ref_read($ctx1, $heap2, 'x'), 'v2', 'new heap has new value');
}

# Test 7: ref_read on non-existent label returns undef
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my $value = Chalk::IR::Reference->ref_read($ctx, $heap, 'nonexistent');
    is($value, undef, 'ref_read on non-existent label returns undef');
}

# Test 8: ref_write on non-existent label returns unchanged heap
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my $heap1 = Chalk::IR::Reference->ref_write($ctx, $heap, 'nonexistent', 'value');
    ok($heap1 == $heap, 'ref_write on non-existent label returns same heap');
}

# Test 9: references work with various value types
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'str', 'text');
    my ($ctx2, $heap2) = Chalk::IR::Reference->ref_new($ctx1, $heap1, 'num', 3.14);
    my ($ctx3, $heap3) = Chalk::IR::Reference->ref_new($ctx2, $heap2, 'hash', { k => 'v' });
    my ($ctx4, $heap4) = Chalk::IR::Reference->ref_new($ctx3, $heap3, 'array', [1, 2, 3]);

    is(Chalk::IR::Reference->ref_read($ctx4, $heap4, 'str'), 'text', 'string reference works');
    is(Chalk::IR::Reference->ref_read($ctx4, $heap4, 'num'), 3.14, 'number reference works');
    is_deeply(Chalk::IR::Reference->ref_read($ctx4, $heap4, 'hash'), { k => 'v' }, 'hash ref works');
    is_deeply(Chalk::IR::Reference->ref_read($ctx4, $heap4, 'array'), [1, 2, 3], 'array ref works');
}

# Test 10: sequential writes to same reference
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, 'counter', 0);
    my $heap2 = Chalk::IR::Reference->ref_write($ctx1, $heap1, 'counter', 1);
    my $heap3 = Chalk::IR::Reference->ref_write($ctx1, $heap2, 'counter', 2);
    my $heap4 = Chalk::IR::Reference->ref_write($ctx1, $heap3, 'counter', 3);

    is(Chalk::IR::Reference->ref_read($ctx1, $heap4, 'counter'), 3, 'sequential writes work');
    is(Chalk::IR::Reference->ref_read($ctx1, $heap2, 'counter'), 1, 'intermediate heap preserved');
}

# Test 11: namespaced references work correctly
{
    my $ctx = Chalk::IR::Context->empty_context();
    my $heap = Chalk::IR::Heap->empty_heap();

    my $var_x = Chalk::IR::Context->make_label('var', 'x');
    my $temp_x = Chalk::IR::Context->make_label('temp', 'x');

    my ($ctx1, $heap1) = Chalk::IR::Reference->ref_new($ctx, $heap, $var_x, 100);
    my ($ctx2, $heap2) = Chalk::IR::Reference->ref_new($ctx1, $heap1, $temp_x, 200);

    is(Chalk::IR::Reference->ref_read($ctx2, $heap2, $var_x), 100, 'var:x has correct value');
    is(Chalk::IR::Reference->ref_read($ctx2, $heap2, $temp_x), 200, 'temp:x has correct value');
}
