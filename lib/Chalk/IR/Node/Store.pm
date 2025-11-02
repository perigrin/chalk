# ABOUTME: Store node for heap memory write operations - currently unused by Builder
# ABOUTME: Reserved for future heap-allocated data (arrays, hashes, objects); lexically scoped variables use SSA-style data flow
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::IR::Heap;

class Chalk::IR::Node::Store :isa(Chalk::IR::Node::Base) {
    method op() { 'Store' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Store',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($context, $heap) {
        # Store writes value to heap at address using Heap abstraction
        # inputs[0] = memory_in (dependency token)
        # inputs[1] = address node
        # inputs[2] = value node
        my @inputs = $self->inputs->@*;

        my $address = $context->("node:$inputs[1]");
        my $value = $context->("node:$inputs[2]");

        # Check if address exists; if not, allocate it
        my $existing = Chalk::IR::Heap->heap_read($heap, $address);
        my $new_heap;

        if (not defined $existing) {
            # Address doesn't exist, allocate with value
            ($new_heap, my $allocated_addr) = Chalk::IR::Heap->heap_alloc($heap, $value);
            # Note: heap_alloc generates address, but we're using our own address
            # So we need to manually create the storage entry
            my $state = $heap->();
            my $new_storage = { %{$state->{storage}}, $address => $value };
            $new_heap = sub () {
                return { storage => $new_storage, next_addr => $state->{next_addr} };
            };
        } else {
            # Address exists, update it
            $new_heap = Chalk::IR::Heap->heap_write($heap, $address, $value);
        }

        # Return memory state token and updated context/heap
        return (1, $context, $new_heap);
    }
}
