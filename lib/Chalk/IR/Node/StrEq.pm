# ABOUTME: String equality comparison node in the Chalk IR.
# ABOUTME: Binary data node wrapping the eq operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::StrEq :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'StrEq' }
    method op_str()    { 'eq' }
}
