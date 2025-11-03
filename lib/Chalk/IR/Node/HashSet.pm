# ABOUTME: Hash element mutation node using context extension
# ABOUTME: Creates new hash context with extended key: binding (immutable semantics)
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::IR::Context;

class Chalk::IR::Node::HashSet :isa(Chalk::IR::Node::Base) {
    field $hash_id  :param :reader;
    field $key_id   :param :reader;
    field $value_id :param :reader;

    method op() { 'HashSet' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'HashSet',
            inputs => $self->inputs,
            attributes => {
                hash_id  => $hash_id,
                key_id   => $key_id,
                value_id => $value_id,
            },
        };
    }

    method execute($context) {
        # Get the old hash context
        my $old_hash_ctx = $context->("node:$hash_id");

        # Get key value
        my $key = $context->("node:$key_id");

        # Get value node object from graph: namespace
        my $value_node = $context->("graph:$value_id");

        # Create new context extending the old one with value node object
        my $label = Chalk::IR::Context->make_key_label($key);
        my $new_hash_ctx = Chalk::IR::Context->extend_context(
            $old_hash_ctx,
            $label,
            $value_node  # Store node object
        );

        # Return the new hash context (immutable + rebind)
        return $new_hash_ctx;
    }
}

1;
