# ABOUTME: Variable declaration node in the Chalk IR.
# ABOUTME: Side-effect-shaped: inputs[0]=control, inputs[1]=name Constant, inputs[2]=init (or undef).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::VarDecl :isa(Chalk::IR::Node) {
    field $scope :param :reader = 'my';

    method operation() { 'VarDecl' }

    method content_hash() {
        return join('|', 'VarDecl', "scope=$scope", $self->_serialize_inputs());
    }

    # Convenience accessors for the standard input slots.
    method control() { return $self->inputs->[0] }
    method name()    { return $self->inputs->[1] }
    method init()    { return $self->inputs->[2] }
}
