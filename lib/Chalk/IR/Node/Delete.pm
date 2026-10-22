# ABOUTME: B::SoN's `delete` -- removes a key or index from a container, yielding its value.
# ABOUTME: A write: it advances the memory chain; kind says array or hash.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Value;
class Chalk::IR::Node::Delete :isa(Chalk::IR::Value) {
    field $kind :param :reader = undef;
    method operation() { 'Delete' }
    method staleness_kind() { 'opaque' }
    method is_fixed() { return true }
}
