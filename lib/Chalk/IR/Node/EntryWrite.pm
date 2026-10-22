# ABOUTME: A write into a package (stash) variable (B::SoN), yielding a new memory version.
# ABOUTME: binds is set for a glob binding (`*g = \\@a`), which aliases the name rather than storing a value.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Value;
class Chalk::IR::Node::EntryWrite :isa(Chalk::IR::Value) {
    field $binds :param :reader = 0;
    method operation() { 'EntryWrite' }
    method staleness_kind() { 'opaque' }
    method is_fixed() { return true }
}
