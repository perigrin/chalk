# ABOUTME: String three-way comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the cmp operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::StrCmp :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'StrCmp' }
    method op_str()    { 'cmp' }
}
