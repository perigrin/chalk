# ABOUTME: Stores a value into a hash in the heap
# ABOUTME: Uses heap ID, key, and value to store element in discrete heap context
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::HashStore :isa(Chalk::IR::Node::Base) {
    field $hash_id :param :reader;
    field $key_id :param :reader;
    field $value_id :param :reader;

    method op() { 'HashStore' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'HashStore',
            inputs => $self->inputs,
            attributes => {
                hash_id => $hash_id,
                key_id => $key_id,
                value_id => $value_id,
            },
        };
    }

    method execute($context) {
        # Get the heap ID from the hash node
        my $heap_id = $context->("node:$hash_id");

        # Get the key value
        my $key = $context->("node:$key_id");

        # Get the value to store
        my $value = $context->("node:$value_id");

        # Get the environment
        my $env = $context->('env:');

        # Store the value in the heap at this key
        $env->set_heap($heap_id, $key, $value);

        # Return the heap ID (the hash reference)
        return $heap_id;
    }
}

1;
