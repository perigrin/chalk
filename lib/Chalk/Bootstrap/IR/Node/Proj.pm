# ABOUTME: IR node representing projection from a tuple-valued node
# ABOUTME: Proj nodes extract one output from multi-output nodes like If
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Proj :isa(Chalk::Bootstrap::IR::Node) {
    # Index of the output to project (0 for true branch, 1 for false branch in If nodes)
    field $index :param :reader;

    method operation() {
        return 'Proj';
    }
}
