# ABOUTME: Arithmetic negation operation node in the Chalk IR.
# ABOUTME: Unary data node producing the numeric negation of its operand.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::Negate :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Negate' }
    method op_str()    { '-' }
}
