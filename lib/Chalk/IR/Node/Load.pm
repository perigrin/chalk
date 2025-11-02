# ABOUTME: Load node for heap memory read operations - currently unused by Builder
# ABOUTME: Reserved for future heap-allocated data (arrays, hashes, objects); lexically scoped variables use SSA-style data flow
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::IR::Heap;

class Chalk::IR::Node::Load :isa(Chalk::IR::Node::Base) {
    method op() { 'Load' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Load',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($context, $heap) {
        # Load reads value from heap at address using Heap abstraction
        # inputs[0] = memory_in (dependency token from prior Store)
        # inputs[1] = address node
        my @inputs = $self->inputs->@*;

        my $address = $context->("node:$inputs[1]");

        # Read from heap using Heap->heap_read
        my $value = Chalk::IR::Heap->heap_read($heap, $address);

        # Return value and unchanged context/heap
        return ($value, $context, $heap);
    }
}

1;
