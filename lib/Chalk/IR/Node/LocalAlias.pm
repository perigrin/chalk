# ABOUTME: A foreach pass aliasing a package scalar to its element (B::SoN): `\\local $_ = \\$a[$i]`.
# ABOUTME: A callee reads or writes the topic by name; restored where the pass ends. name is the variable.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Value;
class Chalk::IR::Node::LocalAlias :isa(Chalk::IR::Value) {
    field $name :param :reader = '_';
    method operation() { 'LocalAlias' }
    method staleness_kind() { 'opaque' }
    method is_fixed() { return true }
}
