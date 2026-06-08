# ABOUTME: Hash dereference node for the Chalk IR.
# ABOUTME: inputs->[0] is a HashRef node; repr=Hash loads through the pointer.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::HashDeref :isa(Chalk::IR::Node) {
    method operation() { 'HashDeref' }
}
