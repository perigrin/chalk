# ABOUTME: Sea of Nodes IR node representation for Chalk compiler
# ABOUTME: Represents a single node in the IR graph with operation type, inputs, and attributes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

# Preload all polymorphic node classes for from_hash() factory
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::GT;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::EQ;
use Chalk::IR::Node::NE;
use Chalk::IR::Node::GE;
use Chalk::IR::Node::LE;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::Reference;
use Chalk::IR::Node::ArrayValue;
use Chalk::IR::Node::HashValue;
use Chalk::IR::Node::ArrayGet;
use Chalk::IR::Node::ArraySet;
use Chalk::IR::Node::HashGet;
use Chalk::IR::Node::HashSet;

class Chalk::IR::Node {
    field $id             :param :reader;
    field $op             :param :reader;
    field $inputs         :param :reader;
    field $attributes     :param :reader;
    field $source_info    :param :reader = undef;
    field $transform_chain :param :reader = undef;

    method to_hash() {
        return {
            id              => $id,
            op              => $op,
            inputs          => $inputs,
            attributes      => $attributes,
            source_info     => $source_info,
            transform_chain => $transform_chain,
        };
    }

    # Get formatted source location string for error messages
    method source_location() {
        return $source_info ? $source_info->to_string() : undef;
    }

    # Record a transformation and return a new node with updated chain
    method record_transform(%args) {
        my $operation   = $args{operation}   // die "operation required";
        my $rule_name   = $args{rule_name}   // undef;
        my $description = $args{description} // undef;

        # Create transform record
        my $transform = {
            operation      => $operation,
            rule_name      => $rule_name,
            description    => $description,
            timestamp      => time(),
            source_node_id => $id,
        };

        # Build new chain: copy existing + new transform
        my $new_chain = $transform_chain ? [$transform_chain->@*] : [];
        push $new_chain->@*, $transform;

        # Return new node with updated chain (immutable pattern)
        return ref($self)->new(
            id              => $id,
            op              => $op,
            inputs          => $inputs,
            attributes      => $attributes,
            source_info     => $source_info,
            transform_chain => $new_chain,
        );
    }

    # Get formatted transformation history for debugging
    method transform_history() {
        return undef unless $transform_chain && $transform_chain->@*;

        my @lines;
        for my $transform ($transform_chain->@*) {
            my $line = sprintf(
                "%s: %s",
                $transform->{operation},
                $transform->{rule_name} // 'unknown'
            );
            if ($transform->{description}) {
                $line .= " - $transform->{description}";
            }
            push @lines, $line;
        }

        return join("\n", @lines);
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
            Not      => 'Chalk::IR::Node::Not',
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
            Return     => 'Chalk::IR::Node::Return',
            Loop       => 'Chalk::IR::Node::Loop',
            Reference  => 'Chalk::IR::Node::Reference',
            ArrayValue => 'Chalk::IR::Node::ArrayValue',
            HashValue  => 'Chalk::IR::Node::HashValue',
            ArrayGet   => 'Chalk::IR::Node::ArrayGet',
            ArraySet   => 'Chalk::IR::Node::ArraySet',
            HashGet    => 'Chalk::IR::Node::HashGet',
            HashSet    => 'Chalk::IR::Node::HashSet',
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

        # All classes are preloaded at compile-time, no runtime loading needed
        # Extract constructor parameters from attributes
        my %params = (
            id     => $id,
            inputs => $inputs,
        );

        # Add source_info if present
        if ($hash->{source_info}) {
            $params{source_info} = $hash->{source_info};
        }

        # Add transform_chain if present
        if ($hash->{transform_chain}) {
            $params{transform_chain} = $hash->{transform_chain};
        }

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
