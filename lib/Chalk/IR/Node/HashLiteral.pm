# ABOUTME: Hash literal constructor node for the Chalk IR.
# ABOUTME: Inputs are interleaved key/value nodes (k0,v0,k1,v1,...); repr=Hash.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::HashLiteral :isa(Chalk::IR::Node) {
    method operation() { 'HashLiteral' }
}
