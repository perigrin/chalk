# ABOUTME: Sea of Nodes IR node representation for Chalk compiler
# ABOUTME: Represents a single node in the IR graph with operation type, inputs, and attributes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Node {
    field $id           :param :reader;
    field $op           :param :reader;
    field $inputs       :param :reader;
    field $attributes   :param :reader;

    method to_hash() {
        return {
            id           => $id,
            op           => $op,
            inputs       => $inputs,
            attributes   => $attributes,
        };
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
            Start    => 'Chalk::IR::Node::Start',
            Constant => 'Chalk::IR::Node::Constant',
            Add      => 'Chalk::IR::Node::Add',
            Subtract => 'Chalk::IR::Node::Subtract',
            Multiply => 'Chalk::IR::Node::Multiply',
            Divide   => 'Chalk::IR::Node::Divide',
            Negate   => 'Chalk::IR::Node::Negate',
            GT       => 'Chalk::IR::Node::GT',
            LT       => 'Chalk::IR::Node::LT',
            EQ       => 'Chalk::IR::Node::EQ',
            NE       => 'Chalk::IR::Node::NE',
            GE       => 'Chalk::IR::Node::GE',
            LE       => 'Chalk::IR::Node::LE',
            If       => 'Chalk::IR::Node::If',
            Region   => 'Chalk::IR::Node::Region',
            Phi      => 'Chalk::IR::Node::Phi',
            Proj     => 'Chalk::IR::Node::Proj',
            Return   => 'Chalk::IR::Node::Return',
            Store    => 'Chalk::IR::Node::Store',
            Load     => 'Chalk::IR::Node::Load',
        );

        my $node_class = $op_to_class{$op};
        if (!$node_class) {
            # Fallback to generic node for unknown ops
            return $class->new(
                id         => $id,
                op         => $op,
                inputs     => $inputs,
                attributes => $attrs,
            );
        }

        # Load the class at runtime (avoids circular dependency with compile-time use)
        {
            my $file = $node_class;
            $file =~ s{::}{/}g;
            $file .= '.pm';
            require $file;
        }

        # Extract constructor parameters from attributes
        my %params = (
            id     => $id,
            inputs => $inputs,
        );

        # Add attributes as constructor parameters
        # Parser compat: keys() requires parentheses around argument
        my @attr_keys = keys($attrs->%*);
        for my $key (@attr_keys) {
            $params{$key} = $attrs->{$key};
        }

        # Create polymorphic node with proper class
        my $node;
        eval {
            $node = $node_class->new(%params);
        };

        # If construction fails, fall back to generic node
        if ($@ || !$node) {
            return $class->new(
                id         => $id,
                op         => $op,
                inputs     => $inputs,
                attributes => $attrs,
            );
        }

        return $node;
    }
}

1;
