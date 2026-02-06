# ABOUTME: IR node for constructing Chalk::Grammar::Rule instances
# ABOUTME: Takes name constant and array of MakeExpression nodes
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::IR::Node::MakeRule :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'MakeRule';
    }
}
