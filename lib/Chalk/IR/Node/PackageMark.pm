# ABOUTME: A point on the control chain where the statements change package (B::SoN).
# ABOUTME: package is the package the following statements are compiled in; it computes nothing.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Node;
class Chalk::IR::Node::PackageMark :isa(Chalk::IR::Node) {
    field $package :param :reader;
    method operation() { 'PackageMark' }
    method is_fixed() { return true }
}
