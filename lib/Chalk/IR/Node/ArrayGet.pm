# ABOUTME: Array element access node using context lookup
# ABOUTME: Performs context lookup using index: namespace for array element retrieval
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::IR::Context;

class Chalk::IR::Node::ArrayGet :isa(Chalk::IR::Node::Base) {
    field $array_id :param :reader;
    field $index_id :param :reader;

    method op() { 'ArrayGet' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArrayGet',
            inputs => $self->inputs,
            attributes => {
                array_id => $array_id,
                index_id => $index_id,
            },
        };
    }

    method execute($context) {
        # Get the array context from the array node
        my $array_ctx = $context->("node:$array_id");

        # Get the index value
        my $index = $context->("node:$index_id");

        # Lookup in array context using index: namespace
        my $label = Chalk::IR::Context->make_index_label($index);
        my $element_node = $array_ctx->($label);

        # Get the value from the node object
        my $value = $context->("node:" . $element_node->id);

        return $value;
    }
}

1;
