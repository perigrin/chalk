# ABOUTME: Projection node in the IR graph
# ABOUTME: Represents extraction of a specific control or data path from a multi-way node
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Proj :isa(Chalk::IR::Node::Base) {
    field $index  :param :reader;
    field $label  :param :reader;

    method op() { 'Proj' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Proj',
            inputs => $self->inputs,
            attributes => {
                index => $index,
                label => $label,
            },
        };
    }
}

1;
