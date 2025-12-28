# ABOUTME: Abstract base class for polymorphic IR nodes
# ABOUTME: Defines common interface that all IR node subclasses must implement
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Base {

    method id() { refaddr($self) }
    field $inputs         :param :reader;
    field $source_info    :param :reader = undef;
    field $transform_chain :param :reader = [];

    # Dependency tracking for peephole re-optimization (Issue #256)
    # When a peephole inspects a remote node and fails, it registers a dependency
    # so that when the remote node changes, this node gets re-added to the worklist.
    #
    # NOTE: This introduces mutability to otherwise immutable nodes. This is acceptable
    # because: (1) deps are optimization metadata, not part of node semantics/identity,
    # (2) GVN's value numbering ignores deps, (3) deps are append-only, and (4) this
    # matches Simple's Java implementation. If strict immutability is needed later,
    # deps could be stored externally in IterPeeps keyed by node ID.
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;  # Return copy (list context)
    }

    # Abstract method - subclasses must implement
    method op() {
        die "Abstract method op() must be implemented by subclass";
    }

    # Default to_hash implementation
    # Subclasses can override to include node-specific attributes
    method to_hash() {
        return {
            id     => $self->id,
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
    method peephole($graph = undef) {
        return $self;
    }

    # Default compute() returns TOP (unknown) - subclasses override for type inference
    method compute() {
        return Chalk::IR::Type::Top->top();
    }

    # Default idealize() returns nothing - subclasses override for algebraic simplification
    method idealize() {
        return;
    }

    # Record a transformation that created or modified this node
    method record_transform(@args) {
        # Support both calling styles for backward compatibility:
        # 1. Positional: record_transform($operation, $name, context => $desc)
        # 2. Named:      record_transform(operation => $op, rule_name => $name, description => $desc)

        my ($operation, $name, %opts);

        if (@args >= 2 && !ref($args[0]) && !ref($args[1]) && $args[0] !~ qr/^(operation|rule_name|description|context|source_node)$/) {
            # Positional style: first two args are scalars, not named params
            ($operation, $name, %opts) = @args;
        } else {
            # Named parameter style
            %opts = @args;
            $operation = $opts{operation};
            $name = $opts{rule_name} // $opts{name};  # Accept both 'rule_name' and 'name'
            # Accept both 'description' and 'context' for the description field
            $opts{context} //= $opts{description};
        }

        # Validate required parameters
        die "record_transform: operation parameter required and must be non-empty"
            unless defined($operation) && length($operation);
        die "record_transform: name parameter required and must be non-empty"
            unless defined($name) && length($name);

        # Validate source_node if provided
        my $source_node_id;
        my $sn = $opts{source_node};
        if ($sn) {
            die "record_transform: source_node must be an IR node object with id() method"
                unless ref($sn) && blessed($sn) && $sn->can('id');
            $source_node_id = $sn->id;
        }

        my $record = Chalk::IR::TransformRecord->new(
            operation      => $operation,
            name           => $name,
            source_node_id => $source_node_id,
            timestamp      => time(),
            context        => $opts{context},
        );

        push $transform_chain->@*, $record;
        return $record;
    }

    # Get all transformations for this node
    method get_transform_chain() {
        return [$transform_chain->@*];  # Return copy to prevent modification
    }

    # Get debug string showing transformation history
    method debug_transform_chain() {
        return "No transformations recorded" unless $transform_chain->@*;

        my @lines = ("Transformation history for node " . $self->id . ":");
        for my $i (0 .. $#$transform_chain) {
            my $record = $transform_chain->[$i];
            push @lines, "  [$i] " . $record->to_string();
        }

        return join("\n", @lines);
    }

    # Clone node with new inputs, preserving polymorphic class type
    # Used by GVN optimizer to reconstruct nodes while maintaining Phi, Region, etc. types
    # $node_map is old_id -> new_node mapping for looking up input nodes
    # $new_attributes allows passing subclass-specific attributes for reconstruction
    method clone_with_inputs($new_inputs, $node_map, $new_attributes = {}) {
        my $class = blessed($self);

        # Translate old input IDs to new node IDs using node_map
        my @translated_inputs;
        for my $input_id (@$new_inputs) {
            if (defined($input_id) && exists($node_map->{$input_id})) {
                push @translated_inputs, $node_map->{$input_id}->id;
            } else {
                push @translated_inputs, $input_id;
            }
        }

        # Build constructor args: inputs is required, merge in new_attributes
        my %args = (
            inputs      => \@translated_inputs,
            source_info => $source_info,
            %$new_attributes,
        );

        return $class->new(%args);
    }
}

1;
