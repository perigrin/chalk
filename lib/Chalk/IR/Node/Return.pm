# ABOUTME: Return node representing function exit point in the IR graph
# ABOUTME: Terminates control flow and returns a value from a function
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Return {
    # v2-style direct node references
    field $control :param :reader = undef;  # Control predecessor node
    field $value :param :reader = undef;    # Value node to return

    # v1 backward compat: allow node params
    field $value_node   :param :reader = undef;
    field $control_node :param :reader = undef;

    # v1 backward compat: allow id params
    field $value_id   :param :reader = undef;
    field $control_id :param :reader = undef;

    # Accept but ignore legacy id/inputs params
    field $id :param = undef;
    field $inputs :param = undef;
    field $source_info :param :reader = undef;

    field $computed_id;

    ADJUST {
        # Normalize: value <-> value_node
        $value //= $value_node;
        $value_node //= $value;

        # Normalize: control <-> control_node
        $control //= $control_node;
        $control_node //= $control;
    }

    # Content-addressable ID computed from child node IDs
    method id() {
        return $computed_id if defined $computed_id;

        my $ctrl_id = defined($control) && blessed($control) && $control->can('id') ? $control->id : ($control_id // 'none');
        my $val_id = defined($value) && blessed($value) && $value->can('id') ? $value->id : ($value_id // 'none');

        return $computed_id = "return_${ctrl_id}_${val_id}";
    }

    # Compute inputs from child nodes
    method inputs() {
        my @inputs;
        if (defined($control) && blessed($control) && $control->can('id')) {
            push @inputs, $control->id;
        } elsif (defined($control_id)) {
            push @inputs, $control_id;
        }
        if (defined($value) && blessed($value) && $value->can('id')) {
            push @inputs, $value->id;
        } elsif (defined($value_id)) {
            push @inputs, $value_id;
        }
        return \@inputs;
    }

    method op() { 'Return' }

    method to_hash() {
        my $ctrl_id = defined($control) && blessed($control) && $control->can('id') ? $control->id : $control_id;
        my $val_id = defined($value) && blessed($value) && $value->can('id') ? $value->id : $value_id;

        return {
            id     => $self->id,
            op     => 'Return',
            inputs => $self->inputs,
            attributes => {
                control    => $ctrl_id,
                control_id => $ctrl_id,  # backward compat
                value_id   => $val_id,
            },
        };
    }

    method execute($context) {
        # Check if this Return's control path is active
        # Control nodes return: Start (undef), Proj (0 or 1), Region (1)
        # 0 = inactive path (only from Proj)
        # 1 or undef = active path
        my $ctrl_id = defined($control) && blessed($control) && $control->can('id') ? $control->id : $control_id;
        my $control_active = $context->("node:$ctrl_id");

        # Skip execution if control is explicitly 0 (inactive Proj path)
        return undef if (defined($control_active) && $control_active == 0);

        # Return the value from the context
        my $val_id = defined($value) && blessed($value) && $value->can('id') ? $value->id : $value_id;
        return $context->("node:$val_id");
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph) {
        return $self;
    }

    # Stub for transform tracking (not used in v2 but called by Builder)
    method record_transform(@args) {
        # No-op for compatibility
        return;
    }

    method get_transform_chain() {
        return [];
    }

    # Immutable reconstruction with new control edge
    method with_control($new_control) {
        return Chalk::IR::Node::Return->new(
            value   => $self->value,
            control => $new_control,
        );
    }
}

1;
