# ABOUTME: Loads a value from an array in the heap
# ABOUTME: Uses heap ID and index to retrieve element from discrete heap context
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayLoad :isa(Chalk::IR::Node::Base) {
    field $array_id :param :reader;
    field $index_id :param :reader;

    method op() { 'ArrayLoad' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArrayLoad',
            inputs => $self->inputs,
            attributes => {
                array_id => $array_id,
                index_id => $index_id,
            },
        };
    }

    method execute($context) {
        # Get the heap ID from the array node
        my $heap_id = $context->("node:$array_id");

        # Get the index value
        my $index = $context->("node:$index_id");

        # Get the environment
        my $env = $context->('env:');

        # Lookup the value in the heap at this index
        my $value = $env->lookup_heap($heap_id, $index);

        # Return the value (or undef if not found)
        return $value;
    }
}

1;
