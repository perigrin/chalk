# ABOUTME: Type propagation pass for IR graphs
# ABOUTME: Implements forward data flow analysis to propagate types through IR nodes

use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::Union;

class Chalk::IR::TypePropagation {
    field $graph :param :reader;

    # Type map: node_id => Type object
    field $type_map = {};

    # Worklist for iterative propagation
    field $worklist = [];

    # Conflict tracking: node_id => { old_type => Type, new_type => Type, reason => String }
    field $conflicts = {};

    # Initialize the type map with known types from nodes
    method _initialize() {
        $type_map = {};
        $worklist = [];
        $conflicts = {};

        # Visit all nodes and initialize types
        for my $node_id (keys $graph->nodes->%*) {
            my $node = $graph->nodes->{$node_id};
            next unless defined $node;

            # Try to get initial type from the node
            my $type = $self->_compute_node_type($node);
            if (defined $type) {
                $type_map->{$node_id} = $type;
                # Add users of this node to worklist
                push $worklist->@*, $self->_get_users($node_id)->@*;
            }
        }
    }

    # Get all nodes that use a given node as input
    method _get_users($node_id) {
        my @users;
        for my $other_id (keys $graph->nodes->%*) {
            my $other = $graph->nodes->{$other_id};
            next unless defined $other;
            next unless $other->can('inputs');

            my $inputs = $other->inputs;
            next unless defined $inputs;

            for my $input_id ($inputs->@*) {
                if ($input_id == $node_id) {
                    push @users, $other_id;
                    last;
                }
            }
        }
        return \@users;
    }

    # Compute type for a node using its compute_type method
    method _compute_node_type($node) {
        return unless defined $node;

        # Try compute_type first (preferred for most nodes)
        if ($node->can('compute_type')) {
            # Try calling with graph parameter first (for Phi nodes)
            # If that fails, try without parameter (for Add, Subtract, etc.)
            my $type = eval { $node->compute_type($graph) };
            return $type if defined $type;

            # Fall back to calling without graph parameter
            $type = eval { $node->compute_type() };
            return $type if defined $type;
        }

        # Fall back to compute() for constant folding types
        if ($node->can('compute')) {
            return $node->compute();
        }

        # No type information available
        return;
    }

    # Propagate types through the graph using worklist algorithm
    method propagate() {
        $self->_initialize();

        my %visited;
        my $iterations = 0;
        my $max_iterations = 1000;  # Prevent infinite loops

        while ($worklist->@* && $iterations < $max_iterations) {
            $iterations++;

            my $node_id = shift $worklist->@*;
            next if $visited{$node_id};
            $visited{$node_id} = 1;

            my $node = $graph->nodes->{$node_id};
            next unless defined $node;

            # Compute new type for this node
            my $new_type = $self->_compute_node_type($node);
            next unless defined $new_type;

            # Check if type changed
            my $old_type = $type_map->{$node_id};
            my $changed = 0;

            if (!defined $old_type) {
                $changed = 1;
            } elsif (ref($old_type) ne ref($new_type)) {
                $changed = 1;
            } elsif ($old_type->can('equals')) {
                $changed = !$old_type->equals($new_type);
            } else {
                # Conservative: assume changed if we can't check equality
                $changed = 1;
            }

            if ($changed) {
                # Detect type conflict: if old_type exists and types are incompatible
                if (defined $old_type && !$self->_types_compatible($old_type, $new_type)) {
                    # Record the conflict
                    $conflicts->{$node_id} = {
                        old_type => $old_type,
                        new_type => $new_type,
                        reason => "Type changed from " . ref($old_type) . " to " . ref($new_type),
                    };

                    # Fall back to Top type (Any/SV*) for safety
                    $type_map->{$node_id} = Chalk::IR::Type::Top->top();
                } else {
                    $type_map->{$node_id} = $new_type;
                }

                # Add users to worklist since type changed
                push $worklist->@*, $self->_get_users($node_id)->@*;
            }
        }

        if ($iterations >= $max_iterations) {
            warn "Type propagation exceeded maximum iterations ($max_iterations)";
        }

        return $type_map;
    }

    # Get the propagated type for a node
    method get_type($node_id) {
        return $type_map->{$node_id};
    }

    # Get all type mappings
    method get_type_map() {
        return { $type_map->%* };  # Return copy
    }

    # Get all conflicts detected during propagation
    method get_conflicts() {
        return { $conflicts->%* };  # Return copy
    }

    # Check if two types are compatible for iterative refinement
    # Types are compatible if they are the same class or one is a subtype
    # Union types and Top are always compatible (they can absorb other types)
    method _types_compatible($type1, $type2) {
        # Top and Bottom are compatible with everything
        return 1 if $type1 isa Chalk::IR::Type::Top;
        return 1 if $type2 isa Chalk::IR::Type::Top;
        return 1 if $type1 isa Chalk::IR::Type::Bottom;
        return 1 if $type2 isa Chalk::IR::Type::Bottom;

        # Union types are compatible (they merge other types)
        return 1 if $type1 isa Chalk::IR::Type::Union;
        return 1 if $type2 isa Chalk::IR::Type::Union;

        # Same class = compatible
        return 1 if ref($type1) eq ref($type2);

        # Different concrete types = incompatible
        return 0;
    }
}

1;
