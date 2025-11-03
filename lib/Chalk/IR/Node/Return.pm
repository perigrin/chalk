# ABOUTME: Return node representing function exit point in the IR graph
# ABOUTME: Terminates control flow and returns a value from a function
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Return :isa(Chalk::IR::Node::Base) {
    field $value_id   :param :reader;
    field $control_id :param :reader;

    method op() { 'Return' }

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
        # Return node returns the value from the context
        return $context->("node:$value_id");
    }
}

1;
