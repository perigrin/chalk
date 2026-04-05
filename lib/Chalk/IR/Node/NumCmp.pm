# ABOUTME: Numeric three-way comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the <=> operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::NumCmp :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'NumCmp' }
    method op_str()    { '<=>' }
}
