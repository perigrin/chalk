# ABOUTME: Abstract base class for polymorphic IR nodes
# ABOUTME: Defines common interface that all IR node subclasses must implement
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Base {
    field $id          :param :reader;
    field $inputs      :param :reader;
    field $source_info :param :reader = undef;

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

    # Attributes accessor for compatibility with GVN optimizer
    # Returns the attributes hash from to_hash()
    method attributes() {
        my $hash = $self->to_hash();
        return $hash->{attributes} // {};
    }

    # Placeholder for optimization - subclasses can override
    method peephole($graph) {
        return $self;
    }
}

1;
