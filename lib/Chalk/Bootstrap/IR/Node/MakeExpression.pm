# ABOUTME: IR node for constructing sequences of symbols (expressions)
# ABOUTME: Takes an ordered array of MakeSymbol nodes as elements
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::IR::Node::MakeExpression :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'MakeExpression';
    }
}
