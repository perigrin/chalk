# ABOUTME: AdjustBlock IR node — represents an ADJUST block body within a class declaration.
# ABOUTME: Inputs: [body_node_1, body_node_2, ...] (the statements executed in the ADJUST block).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::AdjustBlock :isa(Chalk::IR::Node) {
    method operation() { 'AdjustBlock' }

    method body_nodes() {
        # All inputs are the body statements (FieldWrite / other side-effect nodes)
        return $self->inputs // [];
    }

    method content_hash() {
        return join('|', 'AdjustBlock', $self->_serialize_inputs());
    }
}
