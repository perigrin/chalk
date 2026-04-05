# ABOUTME: Logical negation operation node in the Chalk IR.
# ABOUTME: Unary data node producing the logical inverse of its operand.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::Not :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Not' }
    method op_str()    { '!' }
}
