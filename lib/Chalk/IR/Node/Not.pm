# ABOUTME: Logical negation node in the IR graph
# ABOUTME: Represents boolean negation of a single operand (!operand or not operand)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Not :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'Not' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Not',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }
}

1;
