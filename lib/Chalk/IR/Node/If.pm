# ABOUTME: CFG conditional branch node for a Chalk computation graph.
# ABOUTME: Takes control and condition inputs; produces two Proj outputs (true/false).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::If :isa(Chalk::IR::Node) {
    method operation() { 'If' }
}
