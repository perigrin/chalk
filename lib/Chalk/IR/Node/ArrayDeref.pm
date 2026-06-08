# ABOUTME: Array dereference node for the Chalk IR.
# ABOUTME: inputs->[0] is an ArrayRef node; repr=Array loads through the pointer.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::ArrayDeref :isa(Chalk::IR::Node) {
    method operation() { 'ArrayDeref' }
}
