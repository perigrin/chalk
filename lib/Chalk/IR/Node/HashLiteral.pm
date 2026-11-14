# ABOUTME: Hash reference constructor node in the Chalk IR.
# ABOUTME: Represents a list of key/value pairs assembled into a hash reference.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Aggregate;

class Chalk::IR::Node::HashLiteral :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'HashLiteral' }
    method staleness_kind() { 'opaque' }

    # is_named_hash -> a `my %h = (...)`'s list (stamped Hash, not a {...}'s HashRef).
    method is_named_hash() { return ( $self->stamp // '' ) eq 'Hash' }  # static type

    # stored_whole_into -> the package hash this list is stored into whole.
    method stored_whole_into() { return Chalk::IR::Node::Aggregate::stored_whole($self) }
}
