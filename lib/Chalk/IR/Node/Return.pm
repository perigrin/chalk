# ABOUTME: CFG normal-exit node for a Chalk computation graph.
# ABOUTME: Takes control and value inputs; represents a regular function return.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Return :isa(Chalk::IR::Node) {
    method operation() { 'Return' }
}
