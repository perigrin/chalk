# ABOUTME: Return node representing function exit point in the IR graph
# ABOUTME: Terminates control flow and returns a value from a function
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Return :isa(Chalk::IR::Node::CFGNode) {

    field $control :param :reader;
    field $value :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    # Compute inputs from child nodes
    method inputs() {
        my @inputs;
        push @inputs, $control->id if defined $control && $control->can('id');
        push @inputs, $value->id if defined $value && $value->can('id');
        return \@inputs;
    }

    method op() { 'Return' }

    method to_hash() {
        my $ctrl_id = (defined $control && $control->can('id')) ? $control->id : undef;
        my $val_id = (defined $value && $value->can('id')) ? $value->id : undef;
        return {
            id     => $self->id,
            op     => 'Return',
            inputs => $self->inputs,
            attributes => {
                control    => $ctrl_id,
                control_id => $ctrl_id,
                value_id   => $val_id,
            },
        };
    }

    method execute($context) {
        return undef unless defined $control && $control->can('id');

        # Check if this Return's control path is active
        my $control_active = $context->("node:" . $control->id);

        # Skip execution if control is explicitly 0 (inactive Proj path)
        return undef if (defined($control_active) && $control_active == 0);

        # Return the value from the context
        return undef unless defined $value && $value->can('id');
        return $context->("node:" . $value->id);
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

    # Clone with new inputs from node_map, preserving polymorphic Return type
    # Used by GVN optimizer to reconstruct nodes
    # $node_map is old_id -> new_node mapping
    method clone_with_inputs($new_inputs, $node_map, $new_attributes = {}) {
        my $new_control;
        my $new_value;

        # Input order: control, value
        if (defined $new_inputs->[0] && exists $node_map->{$new_inputs->[0]}) {
            $new_control = $node_map->{$new_inputs->[0]};
        }
        if (defined $new_inputs->[1] && exists $node_map->{$new_inputs->[1]}) {
            $new_value = $node_map->{$new_inputs->[1]};
        }

        return Chalk::IR::Node::Return->new(
            control     => $new_control,
            value       => $new_value,
            source_info => $source_info,
        );
    }

    # Immutable reconstruction with new control edge
    method with_control($new_control) {
        return Chalk::IR::Node::Return->new(
            value   => $value,
            control => $new_control,
        );
    }

    # Dominator tree: Return's immediate dominator is its control input
    method idom() {
        return $control;
    }

    # Dominator depth: cached computation based on idom chain
    field $_idepth = undef;
    method idepth() {
        return $_idepth if defined $_idepth;

        my $idom = $self->idom;
        if (!defined $idom) {
            $_idepth = 0;
        } elsif ($idom->can('idepth')) {
            $_idepth = $idom->idepth + 1;
        } else {
            $_idepth = 1;
        }

        return $_idepth;
    }

    # Dominator check: walk up idom chain from $other to see if we reach $self
    method dominates($other) {
        return 1 if refaddr($self) == refaddr($other);

        my $current = $other;
        while (defined $current && $current->can('idom')) {
            my $idom = $current->idom;
            last unless defined $idom;

            return 1 if refaddr($self) == refaddr($idom);
            $current = $idom;
        }

        return 0;
    }
}

1;
