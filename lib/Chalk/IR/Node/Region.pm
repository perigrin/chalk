# ABOUTME: CFG merge node for a Chalk computation graph.
# ABOUTME: Joins multiple control-flow paths into one; inputs are Proj or other control nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Region :isa(Chalk::IR::Node) {
    method operation() { 'Region' }
}
