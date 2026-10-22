# ABOUTME: `wantarray` (B::SoN): the calling context, read inside the callee.
# ABOUTME: Resolved per call from the Call's want, not folded at translation.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Node::Access;
class Chalk::IR::Node::Wantarray :isa(Chalk::IR::Node::Access) {
    method operation() { 'Wantarray' }
    method staleness_kind() { 'opaque' }
}
