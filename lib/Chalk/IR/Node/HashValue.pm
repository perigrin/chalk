# ABOUTME: Hash value node wrapping a context for hash storage
# ABOUTME: Represents hashes as contexts with key: namespace for elements
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::HashValue :isa(Chalk::IR::Node::Base) {
    field $hash_context :param :reader;

    method op() { 'HashValue' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'HashValue',
            inputs => $self->inputs,
            attributes => {
                hash_context => $hash_context,
            },
        };
    }

    method execute($context) {
        # Return the hash context itself - it's already a closure
        # The context contains bindings like "key:foo", "key:bar", etc.
        return $hash_context;
    }
}

1;
