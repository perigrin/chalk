# ABOUTME: IR node representing the entry point of a computation graph
# ABOUTME: Start nodes have no inputs or attributes, only mark graph beginning
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::IR::Node::Start :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'Start';
    }
}
