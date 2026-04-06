# ABOUTME: String/list repetition operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the x operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::Repeat :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Repeat' }
    method op_str()    { 'x' }
}
