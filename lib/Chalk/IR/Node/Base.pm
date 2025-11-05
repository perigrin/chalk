# ABOUTME: Abstract base class for polymorphic IR nodes
# ABOUTME: Defines common interface that all IR node subclasses must implement
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Base {
    use Chalk::IR::TransformRecord;

    field $id             :param :reader;
    field $inputs         :param :reader;
    field $source_info    :param :reader = undef;
    field $transform_chain :param :reader = [];

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

    # Record a transformation that created or modified this node
    method record_transform($operation, $name, %opts) {
        my $source_node_id = $opts{source_node} ? $opts{source_node}->id : undef;

        my $record = Chalk::IR::TransformRecord->new(
            operation      => $operation,
            name           => $name,
            source_node_id => $source_node_id,
            timestamp      => time(),
            context        => $opts{context},
        );

        push @$transform_chain, $record;
        return $record;
    }

    # Get all transformations for this node
    method get_transform_chain() {
        return [@$transform_chain];  # Return copy to prevent modification
    }

    # Get debug string showing transformation history
    method debug_transform_chain() {
        return "No transformations recorded" unless @$transform_chain;

        my @lines = ("Transformation history for node $id:");
        for my $i (0 .. $#$transform_chain) {
            my $record = $transform_chain->[$i];
            push @lines, "  [$i] " . $record->to_string();
        }

        return join("\n", @lines);
    }
}

1;
