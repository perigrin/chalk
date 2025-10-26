# ABOUTME: Binary addition node in the IR graph
# ABOUTME: Represents addition of two operands (left + right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Add :isa(Chalk::IR::Node::Base) {
    field $left_id  :param :reader;
    field $right_id :param :reader;

    method op() { 'Add' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Add',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left_id,
                right_id => $right_id,
            },
        };
    }
}

1;
