# ABOUTME: CFG exceptional-exit node for a Chalk computation graph.
# ABOUTME: Takes control and exception-value inputs; represents a die/throw exit.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Unwind :isa(Chalk::IR::Node) {
    method operation() { 'Unwind' }
}
