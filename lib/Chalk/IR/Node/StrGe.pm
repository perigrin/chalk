# ABOUTME: String greater-or-equal comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the ge operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::StrGe :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'StrGe' }
    method op_str()    { 'ge' }
}
