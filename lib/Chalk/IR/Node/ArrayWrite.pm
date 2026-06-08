# ABOUTME: Array element store node for the Chalk IR.
# ABOUTME: inputs->[0]=Array, inputs->[1]=index (Int), inputs->[2]=value; repr=Array (for chaining).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::ArrayWrite :isa(Chalk::IR::Node) {
    method operation() { 'ArrayWrite' }
}
