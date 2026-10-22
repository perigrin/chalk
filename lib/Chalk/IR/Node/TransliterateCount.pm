# ABOUTME: The character count tr/// returns in non-void context (B::SoN).
# ABOUTME: Its operand is the Transliterate; the transliterated string is that node.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Node::UnaryOp;
class Chalk::IR::Node::TransliterateCount :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'TransliterateCount' }
    method op_str() { 'tr-count' }
}
