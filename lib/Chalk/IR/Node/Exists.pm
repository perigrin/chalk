# ABOUTME: B::SoN's `exists` -- is the key or index PRESENT in the container.
# ABOUTME: inputs: container, key or index, memory; kind says array or hash. Membership, not definedness.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Node::Access;
class Chalk::IR::Node::Exists :isa(Chalk::IR::Node::Access) {
    field $kind :param :reader = undef;
    method operation() { 'Exists' }
    method staleness_kind() { 'opaque' }
}
