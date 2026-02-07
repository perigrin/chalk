# ABOUTME: IR node representing the exit point of a computation graph
# ABOUTME: Return nodes have one input (the value being returned)
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Return :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'Return';
    }
}
