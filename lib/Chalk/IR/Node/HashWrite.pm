# ABOUTME: Hash element store node for the Chalk IR.
# ABOUTME: inputs->[0]=Hash, inputs->[1]=key (Str), inputs->[2]=value; repr=Hash (for chaining).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::HashWrite :isa(Chalk::IR::Node) {
    method operation() { 'HashWrite' }
}
