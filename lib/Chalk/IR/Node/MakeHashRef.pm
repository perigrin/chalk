# ABOUTME: Hash reference constructor node for the Chalk IR.
# ABOUTME: inputs->[0] is the Hash node; repr=HashRef produces a pointer + ref tag.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::MakeHashRef :isa(Chalk::IR::Node) {
    method operation() { 'MakeHashRef' }
}
