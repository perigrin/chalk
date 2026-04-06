# ABOUTME: Logical exclusive or operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the xor operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::Xor :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Xor' }
    method op_str()    { 'xor' }
}
