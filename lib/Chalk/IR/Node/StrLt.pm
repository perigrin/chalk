# ABOUTME: String less-than comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the lt operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::StrLt :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'StrLt' }
    method op_str()    { 'lt' }
}
