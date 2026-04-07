# ABOUTME: Variable declaration node in the Chalk IR.
# ABOUTME: Represents a my/our/state declaration with an explicit scope qualifier.
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
}
