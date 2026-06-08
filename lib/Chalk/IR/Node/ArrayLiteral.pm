# ABOUTME: Array literal constructor node for the Chalk IR.
# ABOUTME: Inputs are the element value nodes; repr=Array produces a {len,cap,Slot*} vector.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::ArrayLiteral :isa(Chalk::IR::Node) {
    method operation() { 'ArrayLiteral' }
}
