# ABOUTME: Greater Than comparison node in the IR graph
# ABOUTME: Represents > comparison between two values
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::GT :isa(Chalk::IR::Node::Base) {
    field $left_id  :param :reader;
    field $right_id :param :reader;

    method op() { 'GT' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'GT',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left_id,
                right_id => $right_id,
            },
        };
    }
}

1;
