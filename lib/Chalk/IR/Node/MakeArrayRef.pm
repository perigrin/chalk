# ABOUTME: Array reference constructor node for the Chalk IR.
# ABOUTME: inputs->[0] is the Array node; repr=ArrayRef produces a pointer + ref tag.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::MakeArrayRef :isa(Chalk::IR::Node) {
    method operation() { 'MakeArrayRef' }
}
