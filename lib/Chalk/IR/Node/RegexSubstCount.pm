# ABOUTME: The match count a destructive s/// returns in scalar context (B::SoN).
# ABOUTME: Its operand is the RegexSubst; the substituted subject is that node.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Node::UnaryOp;
class Chalk::IR::Node::RegexSubstCount :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'RegexSubstCount' }
    method op_str() { 's-count' }
}
