# ABOUTME: IR node for array or hash subscript operations in the Sea of Nodes graph.
# ABOUTME: inputs->[0] is the container, inputs->[1] is the index or key.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::Subscript :isa(Chalk::IR::Node::Access) {
    method operation() { 'Subscript' }
}
