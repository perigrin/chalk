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

    # Factory method: create polymorphic node from hash representation
    # Used by GVN to reconstruct nodes while preserving polymorphic types
    sub from_hash($class, $hash) {
        my $op = $hash->{op};
        my $id = $hash->{id};
        my $inputs = $hash->{inputs};
        my $attrs = $hash->{attributes} // {};

        # Map op to polymorphic class
        my %op_to_class = (
            Start      => 'Chalk::IR::Node::Start',
            Constant   => 'Chalk::IR::Node::Constant',
            Add        => 'Chalk::IR::Node::Add',
            Subtract   => 'Chalk::IR::Node::Subtract',
            Multiply   => 'Chalk::IR::Node::Multiply',
            Divide     => 'Chalk::IR::Node::Divide',
            GT         => 'Chalk::IR::Node::GT',
            LT         => 'Chalk::IR::Node::LT',
            EQ         => 'Chalk::IR::Node::EQ',
            NE         => 'Chalk::IR::Node::NE',
            GE         => 'Chalk::IR::Node::GE',
            LE         => 'Chalk::IR::Node::LE',
            Negate     => 'Chalk::IR::Node::Negate',
            Not        => 'Chalk::IR::Node::Not',
            If         => 'Chalk::IR::Node::If',
            Proj       => 'Chalk::IR::Node::Proj',
            Region     => 'Chalk::IR::Node::Region',
            Phi        => 'Chalk::IR::Node::Phi',
            Return     => 'Chalk::IR::Node::Return',
            Loop       => 'Chalk::IR::Node::Loop',
        );

        my $node_class = $op_to_class{$op};
        if (!$node_class) {
            # Fallback to generic node for unknown ops
            return Chalk::IR::Node->new(
                id => $id,
                op => $op,
                inputs => $inputs,
                attributes => $attrs,
            );
        }

        # Load the class
        eval "require $node_class";
        die $@ if $@;

        # Extract parameters for polymorphic node construction
        my %params = (
            id => $id,
            inputs => $inputs,
        );

        # Add node-specific parameters from attributes
        for my $key (keys %$attrs) {
            $params{$key} = $attrs->{$key};
        }

        # Try to create polymorphic node
        # If it fails (missing required params), fall back to generic node
        my $node;
        eval {
            $node = $node_class->new(%params);
        };

        if ($@ || !$node) {
            # Failed to create polymorphic node - fall back to generic
            return Chalk::IR::Node->new(
                id => $id,
                op => $op,
                inputs => $inputs,
                attributes => $attrs,
            );
        }

        return $node;
    }
}

1;
