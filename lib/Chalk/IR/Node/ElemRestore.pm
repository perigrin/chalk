# ABOUTME: The restore a `local` on an element makes at its block's exit (B::SoN).
# ABOUTME: Puts the saved value back, or deletes a key that did not exist; a write. kind: array or hash.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Value;
class Chalk::IR::Node::ElemRestore :isa(Chalk::IR::Value) {
    field $kind :param :reader = undef;
    method operation() { 'ElemRestore' }
    method staleness_kind() { 'opaque' }
    method is_fixed() { return true }
}
