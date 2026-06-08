# ABOUTME: Scalar-len operation node for the Chalk IR.
# ABOUTME: inputs->[0] is the Array node; repr=Int returns the element count.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::ScalarLen :isa(Chalk::IR::Node) {
    method operation() { 'ScalarLen' }
}
