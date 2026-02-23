# ABOUTME: IR node representing a loop header in control flow
# ABOUTME: Loop nodes are special Region nodes with entry and backedge control inputs
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Loop :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'Loop';
    }
}
