# ABOUTME: Post-increment node in the IR graph
# ABOUTME: Represents post-increment operation ($var++) - returns current value then increments
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PostIncrement :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'PostIncrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PostIncrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }
}

1;
