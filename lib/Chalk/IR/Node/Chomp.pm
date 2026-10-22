# ABOUTME: chomp or chop (B::SoN): the string with its tail trimmed; the store back is separate.
# ABOUTME: kind is chomp or chop.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Value;
class Chalk::IR::Node::Chomp :isa(Chalk::IR::Value) {
    field $kind :param :reader = 'chomp';
    method operation() { 'Chomp' }
}
