# ABOUTME: Perl's `++` on a value that may be a string (B::SoN): magic increment, "Az" -> "Ba".
# ABOUTME: Numeric for anything that is not a string matching /^[a-zA-Z]*[0-9]*$/.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Node::UnaryOp;
class Chalk::IR::Node::Increment :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Increment' }
    method op_str() { '++' }
}
