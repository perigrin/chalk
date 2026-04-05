# ABOUTME: Definedness test operation node in the Chalk IR.
# ABOUTME: Unary data node testing whether its operand is defined.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::Defined :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Defined' }
    method op_str()    { 'defined' }
}
