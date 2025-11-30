# ABOUTME: Return node representing function exit point in the IR graph
# ABOUTME: Terminates control flow and returns a value from a function
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Return {
    field $control :param :reader;
    field $value :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

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


    # Immutable reconstruction with new control edge
    method with_control($new_control) {
        return Chalk::IR::Node::Return->new(
            value   => $value,
            control => $new_control,
        );
    }
}

1;
