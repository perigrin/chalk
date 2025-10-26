# ABOUTME: Pre-increment node in the IR graph
# ABOUTME: Represents pre-increment operation (++$var) - increments then returns new value
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PreIncrement :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'PreIncrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PreIncrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }
}

1;
