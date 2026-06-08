# ABOUTME: Hash element read node for the Chalk IR.
# ABOUTME: inputs->[0] is the Hash node, inputs->[1] is the key (Str); repr=Int or Slot.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::HashRead :isa(Chalk::IR::Node) {
    method operation() { 'HashRead' }
}
