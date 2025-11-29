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

    field $id :reader = "return_" . $control->id . "_" . $value->id;

    # Compute inputs from child nodes
    method inputs() {
        return [ $control->id, $value->id ];
    }

    method op() { 'Return' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Return',
            inputs => $self->inputs,
            attributes => {
                control    => $control->id,
                control_id => $control->id,
                value_id   => $value->id,
            },
        };
    }

    method execute($context) {
        # Check if this Return's control path is active
        my $control_active = $context->("node:" . $control->id);

        # Skip execution if control is explicitly 0 (inactive Proj path)
        return undef if (defined($control_active) && $control_active == 0);

        # Return the value from the context
        return $context->("node:" . $value->id);
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph) {
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
