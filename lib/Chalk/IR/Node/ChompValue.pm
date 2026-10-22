# ABOUTME: What chomp or chop returns (B::SoN): the count chomp removed, or the character chop removed.
# ABOUTME: kind is chomp or chop; the trimmed string is the Chomp.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Value;
class Chalk::IR::Node::ChompValue :isa(Chalk::IR::Value) {
    field $kind :param :reader = 'chomp';
    method operation() { 'ChompValue' }
}
