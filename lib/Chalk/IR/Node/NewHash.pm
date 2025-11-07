# ABOUTME: Allocates a new hash in the heap and returns its heap ID
# ABOUTME: Creates discrete heap context for hash storage in CEK interpreter
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::NewHash :isa(Chalk::IR::Node::Base) {
    method op() { 'NewHash' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NewHash',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($context) {
        # Allocate a new heap ID for this hash
        # The environment must be accessible via a special context key
        my $env = $context->('env:');
        my $heap_id = $env->allocate_heap_id();

        # Return the heap ID - this is the "hash reference"
        return $heap_id;
    }
}

1;
