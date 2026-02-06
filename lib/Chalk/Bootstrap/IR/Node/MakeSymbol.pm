# ABOUTME: IR node for constructing Chalk::Grammar::Symbol instances
# ABOUTME: Takes type, value, and optional quantifier as inputs
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::IR::Node::MakeSymbol :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'MakeSymbol';
    }
}
