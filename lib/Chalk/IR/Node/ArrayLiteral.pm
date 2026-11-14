# ABOUTME: Array reference constructor node in the Chalk IR.
# ABOUTME: Represents a list of elements assembled into an array reference.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Aggregate;

class Chalk::IR::Node::ArrayLiteral :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'ArrayLiteral' }
    method staleness_kind() { 'opaque' }

    # stored_whole_into -> the package array this list is stored into whole.
    method stored_whole_into() { return Chalk::IR::Node::Aggregate::stored_whole($self) }
}
