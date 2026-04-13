# ABOUTME: Length operation node in the Chalk IR.
# ABOUTME: Unary data node producing the length of its operand (string or array).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::Length :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Length' }
    method op_str()    { 'length' }
}
