# ABOUTME: Hash reference constructor node in the Chalk IR.
# ABOUTME: Represents a list of key/value pairs assembled into a hash reference.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Aggregate;

class Chalk::IR::Node::HashRef :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'HashRef' }
}
