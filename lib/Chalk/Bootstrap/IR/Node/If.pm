# ABOUTME: IR node representing a conditional branch in control flow
# ABOUTME: If nodes split control flow based on a boolean condition
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::If :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'If';
    }
}
