# ABOUTME: Hash element access node using context lookup
# ABOUTME: Performs context lookup using key: namespace for hash element retrieval
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::IR::Context;

class Chalk::IR::Node::HashGet :isa(Chalk::IR::Node::Base) {
    field $hash_id :param :reader;
    field $key_id  :param :reader;

    method op() { 'HashGet' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'HashGet',
            inputs => $self->inputs,
            attributes => {
                hash_id => $hash_id,
                key_id  => $key_id,
            },
        };
    }

    method execute($context) {
        # Get the hash context from the hash node
        my $hash_ctx = $context->("node:$hash_id");

        # Get the key value
        my $key = $context->("node:$key_id");

        # Lookup in hash context using key: namespace
        my $label = Chalk::IR::Context->make_key_label($key);
        my $node_id = $hash_ctx->($label);

        # Resolve the node ID to get the actual value
        my $value = $context->("node:$node_id");

        return $value;
    }
}

1;
