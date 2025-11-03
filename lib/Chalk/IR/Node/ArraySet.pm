# ABOUTME: Array element mutation node using context extension
# ABOUTME: Creates new array context with extended index: binding (immutable semantics)
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::IR::Context;

class Chalk::IR::Node::ArraySet :isa(Chalk::IR::Node::Base) {
    field $array_id :param :reader;
    field $index_id :param :reader;
    field $value_id :param :reader;

    method op() { 'ArraySet' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArraySet',
            inputs => $self->inputs,
            attributes => {
                array_id => $array_id,
                index_id => $index_id,
                value_id => $value_id,
            },
        };
    }

    method execute($context) {
        # Get the old array context
        my $old_array_ctx = $context->("node:$array_id");

        # Get index value
        my $index = $context->("node:$index_id");

        # Get value node object from graph: namespace
        my $value_node = $context->("graph:$value_id");

        # Create new context extending the old one with value node object
        my $label = Chalk::IR::Context->make_index_label($index);
        my $new_array_ctx = Chalk::IR::Context->extend_context(
            $old_array_ctx,
            $label,
            $value_node  # Store node object
        );

        # Return the new array context (immutable + rebind)
        return $new_array_ctx;
    }
}

1;
