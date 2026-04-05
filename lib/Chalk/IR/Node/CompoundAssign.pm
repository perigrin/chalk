# ABOUTME: Compound assignment node in the Chalk IR.
# ABOUTME: Carries the operator (+=, -=, .=, etc.) for the combined read-modify-write.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::CompoundAssign :isa(Chalk::IR::Node) {
    field $op :param :reader;

    method operation() { 'CompoundAssign' }
}
