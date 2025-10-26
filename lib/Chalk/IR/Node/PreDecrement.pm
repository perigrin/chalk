# ABOUTME: Pre-decrement node in the IR graph
# ABOUTME: Represents pre-decrement operation (--$var) - decrements then returns new value
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PreDecrement :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'PreDecrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PreDecrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }
}

1;
