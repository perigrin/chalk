# ABOUTME: Less Than or Equal comparison node in the IR graph
# ABOUTME: Represents <= comparison between two values
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::LE :isa(Chalk::IR::Node::Base) {
    field $left_id  :param :reader;
    field $right_id :param :reader;

    method op() { 'LE' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'LE',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left_id,
                right_id => $right_id,
            },
        };
    }
}

1;
