# ABOUTME: Allocates a new object in the heap and returns its heap ID
# ABOUTME: Creates discrete heap context for object storage in CEK interpreter
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::NewObject :isa(Chalk::IR::Node::Base) {
    method op() { 'NewObject' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NewObject',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($context) {
        # Allocate a new heap ID for this object
        # The environment must be accessible via a special context key
        my $env = $context->('env:');
        my $heap_id = $env->allocate_heap_id();

        # Return the heap ID - this is the "object reference"
        return $heap_id;
    }
}

1;
