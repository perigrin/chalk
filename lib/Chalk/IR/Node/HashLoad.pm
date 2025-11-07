# ABOUTME: Loads a value from a hash in the heap
# ABOUTME: Uses heap ID and key to retrieve element from discrete heap context
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::HashLoad :isa(Chalk::IR::Node::Base) {
    field $hash_id :param :reader;
    field $key_id :param :reader;

    method op() { 'HashLoad' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'HashLoad',
            inputs => $self->inputs,
            attributes => {
                hash_id => $hash_id,
                key_id => $key_id,
            },
        };
    }

    method execute($context) {
        # Get the heap ID from the hash node
        my $heap_id = $context->("node:$hash_id");

        # Get the key value
        my $key = $context->("node:$key_id");

        # Get the environment
        my $env = $context->('env:');

        # Lookup the value in the heap at this key
        my $value = $env->lookup_heap($heap_id, $key);

        # Return the value (or undef if not found)
        return $value;
    }
}

1;
