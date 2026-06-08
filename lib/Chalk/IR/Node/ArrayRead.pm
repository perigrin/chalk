# ABOUTME: Array element read node for the Chalk IR.
# ABOUTME: inputs->[0] is the Array node, inputs->[1] is the index (Int); repr=Int or Slot.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::ArrayRead :isa(Chalk::IR::Node) {
    method operation() { 'ArrayRead' }
}
