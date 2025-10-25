# ABOUTME: Abstract base class for polymorphic IR nodes
# ABOUTME: Defines common interface that all IR node subclasses must implement
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Base {
    field $id      :param :reader;
    field $inputs  :param :reader;

    # Abstract method - subclasses must implement
    method op() {
        die "Abstract method op() must be implemented by subclass";
    }

    # Default to_hash implementation
    # Subclasses can override to include node-specific attributes
    method to_hash() {
        return {
            id     => $id,
            op     => $self->op,
            inputs => $inputs,
        };
    }

    # Placeholder for optimization - subclasses can override
    method peephole($graph) {
        return $self;
    }
}

1;
