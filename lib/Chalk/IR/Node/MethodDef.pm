# ABOUTME: MethodDef IR node — declares a method with its body sub-graph for use in a ClassDecl.
# ABOUTME: Inputs: [body_value_node]. ClassDecl is the owner; ClassDecl.inputs includes this MethodDef.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::MethodDef :isa(Chalk::IR::Node) {
    # Method name string (e.g. "greet")
    field $method_name :param :reader;

    method operation() { 'MethodDef' }

    method body_node() {
        # inputs[0] is the return-value node of the method body sub-graph
        return $self->inputs->[0];
    }

    method content_hash() {
        return join('|', 'MethodDef', "method_name=$method_name",
            $self->_serialize_inputs());
    }
}
