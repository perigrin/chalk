# ABOUTME: Slice operation node in the Chalk IR.
# ABOUTME: Aggregate data node taking a container and index list, producing a slice.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Aggregate;

class Chalk::IR::Node::Slice :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'Slice' }
}
