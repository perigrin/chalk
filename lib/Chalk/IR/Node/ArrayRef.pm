# ABOUTME: Array reference constructor node in the Chalk IR.
# ABOUTME: Represents a list of elements assembled into an array reference.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Aggregate;

class Chalk::IR::Node::ArrayRef :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'ArrayRef' }
}
