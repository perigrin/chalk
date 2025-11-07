# ABOUTME: Allocates a new array in the heap and returns its heap ID
# ABOUTME: Creates discrete heap context for array storage in CEK interpreter
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::NewArray :isa(Chalk::IR::Node::Base) {
    method op() { 'NewArray' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NewArray',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($context) {
        # Allocate a new heap ID for this array
        # The environment must be accessible via a special context key
        my $env = $context->('env:');
        my $heap_id = $env->allocate_heap_id();

        # Return the heap ID - this is the "array reference"
        return $heap_id;
    }
}

1;
