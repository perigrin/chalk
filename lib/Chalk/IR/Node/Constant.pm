# ABOUTME: Constant value node in the IR graph
# ABOUTME: Represents compile-time constant values (integers, strings, etc.)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Constant :isa(Chalk::IR::Node::Base) {
    field $value :param :reader;
    field $type  :param :reader;

    method op() { 'Constant' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Constant',
            inputs => $self->inputs,
            attributes => {
                value => $value,
                type  => $type,
            },
        };
    }

    method execute() {
        return $value;
    }
}

1;
