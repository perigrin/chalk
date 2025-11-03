# ABOUTME: Array value node wrapping a context for array storage
# ABOUTME: Represents arrays as contexts with index: namespace for elements
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayValue :isa(Chalk::IR::Node::Base) {
    field $array_context :param :reader;

    method op() { 'ArrayValue' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArrayValue',
            inputs => $self->inputs,
            attributes => {
                array_context => $array_context,
            },
        };
    }

    method execute($context) {
        # Return the array context itself - it's already a closure
        # The context contains bindings like "index:0", "index:1", etc.
        return $array_context;
    }
}

1;
