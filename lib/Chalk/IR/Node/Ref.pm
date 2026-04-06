# ABOUTME: Reference constructor operation node in the Chalk IR.
# ABOUTME: Unary data node wrapping the \ operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::Ref :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Ref' }
    method op_str()    { '\\' }
}
