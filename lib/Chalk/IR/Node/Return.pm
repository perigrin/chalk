# ABOUTME: Return node representing function exit point in the IR graph
# ABOUTME: Terminates control flow and returns a value from a function
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Return :isa(Chalk::IR::Node::Base) {
    field $value_id   :param :reader;
    field $control_id :param :reader;

    method op() { 'Return' }

    # Writer method to update control_id after construction
    # Needed for wiring control edges in if/else statements
    method set_control_id($new_control_id) {
        $control_id = $new_control_id;
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Return',
            inputs => $self->inputs,
            attributes => {
                value_id   => $value_id,
                control_id => $control_id,
            },
        };
    }

    method execute($context) {
        # Check if this Return's control path is active
        # Control nodes return: Start (undef), Proj (0 or 1), Region (1)
        # 0 = inactive path (only from Proj)
        # 1 or undef = active path
        my $control_active = $context->("node:$control_id");

        # Skip execution if control is explicitly 0 (inactive Proj path)
        return undef if (defined($control_active) && $control_active == 0);

        # Return the value from the context
        return $context->("node:$value_id");
    }
}

1;
