# ABOUTME: Unary plus (numeric coercion) operation node in the Chalk IR.
# ABOUTME: Unary data node wrapping the + operator in unary context.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::UnaryPlus :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'UnaryPlus' }
    method op_str()    { '+' }
}
