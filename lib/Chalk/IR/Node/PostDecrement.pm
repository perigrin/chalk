# ABOUTME: Post-decrement node in the IR graph
# ABOUTME: Represents post-decrement operation ($var--) - returns current value then decrements
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PostDecrement :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'PostDecrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PostDecrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }
}

1;
