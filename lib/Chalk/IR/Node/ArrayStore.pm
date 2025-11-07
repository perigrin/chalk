# ABOUTME: Stores a value into an array in the heap
# ABOUTME: Uses heap ID, index, and value to store element in discrete heap context
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayStore :isa(Chalk::IR::Node::Base) {
    field $array_id :param :reader;
    field $index_id :param :reader;
    field $value_id :param :reader;

    method op() { 'ArrayStore' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArrayStore',
            inputs => $self->inputs,
            attributes => {
                array_id => $array_id,
                index_id => $index_id,
                value_id => $value_id,
            },
        };
    }

    method execute($context) {
        # Get the heap ID from the array node
        my $heap_id = $context->("node:$array_id");

        # Get the index value
        my $index = $context->("node:$index_id");

        # Get the value to store
        my $value = $context->("node:$value_id");

        # Get the environment
        my $env = $context->('env:');

        # Store the value in the heap at this index
        $env->set_heap($heap_id, $index, $value);

        # Return the heap ID (the array reference)
        return $heap_id;
    }
}

1;
