# ABOUTME: Intermediate base class for binary operation IR nodes.
# ABOUTME: Provides left(), right(), and abstract op_str() accessors.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::BinOp :isa(Chalk::IR::Node) {
    field $left  :param :reader = undef;
    field $right :param :reader = undef;

    ADJUST {
        $left  //= $self->inputs()->[0];
        $right //= $self->inputs()->[1];
    }

    method op_str() {
        die "Subclass must implement op_str()";
    }
}
