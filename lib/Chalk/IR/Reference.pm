# ABOUTME: Reference operations integrating Context and Heap abstractions
# ABOUTME: Provides ref_new, ref_read, and ref_write for mutable reference semantics
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::IR::Context;

class Chalk::IR::Reference {
    # Creates new reference: allocates on heap, binds address in context
    # Returns (new_context, new_heap)
    sub ref_new($class, $ctx, $heap, $label, $value) {
        # Allocate value on heap
        my ($new_heap, $addr) = Chalk::IR::Heap->heap_alloc($heap, $value);

        # Bind address in context
        my $new_ctx = Chalk::IR::Context->extend_context($ctx, $label, $addr);

        return ($new_ctx, $new_heap);
    }

    # Dereferences label: looks up address, reads from heap
    # Returns value (or undef if label not found or address invalid)
    sub ref_read($class, $ctx, $heap, $label) {
        # Look up address in context
        my $addr = $ctx->($label);
        return undef unless defined $addr;

        # Read value from heap
        return Chalk::IR::Heap->heap_read($heap, $addr);
    }

    # Updates reference: looks up address, writes to heap
    # Returns new_heap (context unchanged since address stays same)
    sub ref_write($class, $ctx, $heap, $label, $new_value) {
        # Look up address in context
        my $addr = $ctx->($label);
        return $heap unless defined $addr;

        # Write new value to heap
        return Chalk::IR::Heap->heap_write($heap, $addr, $new_value);
    }
}