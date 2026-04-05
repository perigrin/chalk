# ABOUTME: Intermediate base class for unary operation IR nodes.
# ABOUTME: Provides operand() and abstract op_str() accessors.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::UnaryOp :isa(Chalk::IR::Node) {
    field $operand :param :reader = undef;

    ADJUST {
        if (!defined $operand && $self->inputs()->@*) {
            $operand = $self->inputs()->[0];
        }
    }

    method op_str() {
        die "Subclass must implement op_str()";
    }
}
