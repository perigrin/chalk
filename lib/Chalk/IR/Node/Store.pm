# ABOUTME: Stores a value into a scalar variable
# ABOUTME: Represents variable assignment in Sea of Nodes IR with control + data edges
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Store {
    # v2-style direct node references
    field $control :param :reader = undef;  # Control predecessor node
    field $var :param :reader = undef;      # Variable name (v2 style)
    field $value :param :reader = undef;    # Value node (v2 style)

    # v1 backward compat: allow var_name as alias for var
    field $var_name :param :reader = undef;

    # v1 backward compat: allow node and id params
    field $value_node :param :reader = undef;
    field $control_node :param :reader = undef;
    field $value_id :param :reader = undef;
    field $control_id :param :reader = undef;

    # Accept but ignore legacy id/inputs params
    field $id :param = undef;
    field $inputs :param = undef;
    field $source_info :param :reader = undef;

    field $computed_id;

    ADJUST {
        # Normalize: var_name <-> var (both names for same thing)
        $var //= $var_name;
        $var_name //= $var;

        # Normalize: value <-> value_node
        $value //= $value_node;
        $value_node //= $value;

        # Normalize: control <-> control_node
        $control //= $control_node;
        $control_node //= $control;
    }

    # Content-addressable ID computed from var name and child node IDs
    method id() {
        return $computed_id if defined $computed_id;

        my $ctrl_id = defined($control) && $control->can('id') ? $control->id : ($control_id // 'none');
        my $val_id = defined($value) && $value->can('id') ? $value->id : ($value_id // 'none');
        my $vname = $var // $var_name // 'unknown';

        return $computed_id = "store_${vname}_${ctrl_id}_${val_id}";
    }

    # Compute inputs from child nodes
    method inputs() {
        my @inputs;
        if (defined($control) && $control->can('id')) {
            push @inputs, $control->id;
        } elsif (defined($control_id)) {
            push @inputs, $control_id;
        }
        if (defined($value) && $value->can('id')) {
            push @inputs, $value->id;
        } elsif (defined($value_id)) {
            push @inputs, $value_id;
        }
        return \@inputs;
    }

    method op() { 'Store' }

    method to_hash() {
        my $vname = $var // $var_name;
        my $ctrl_id = defined($control) && $control->can('id') ? $control->id : $control_id;
        my $val_id = defined($value) && $value->can('id') ? $value->id : $value_id;

        return {
            id     => $self->id,
            op     => 'Store',
            inputs => $self->inputs,
            attributes => {
                var        => $vname,
                var_name   => $vname,  # backward compat
                control    => $ctrl_id,
                control_id => $ctrl_id,  # backward compat
                value_id   => $val_id,
            },
        };
    }

    method execute($context) {
        # Get the value to store
        my $vid = defined($value) && $value->can('id') ? $value->id : $value_id;
        my $val = $context->("node:$vid");

        # Store in scope/context (implementation depends on runtime)
        # For now, just return the value (assignment evaluates to assigned value)
        return $val;
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
        return Chalk::IR::Node::Store->new(
            var     => $self->var // $self->var_name,
            value   => $self->value,
            control => $new_control,
        );
    }
}

1;
