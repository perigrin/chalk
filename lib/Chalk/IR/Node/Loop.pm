# ABOUTME: CFG loop header node for a Chalk computation graph.
# ABOUTME: Holds the entry control and a mutable backedge slot set after the loop body is built.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Loop :isa(Chalk::IR::Node) {
    method operation() { 'Loop' }

    method set_backedge_ctrl($ctrl) {
        $self->inputs()->[1] = $ctrl;
    }
}
