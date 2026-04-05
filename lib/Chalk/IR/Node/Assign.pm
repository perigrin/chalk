# ABOUTME: Assignment operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the = operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::Assign :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Assign' }
    method op_str()    { '=' }
}
