# ABOUTME: IR node representing a control flow merge point
# ABOUTME: Region nodes merge multiple control paths into a single continuation
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Region :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'Region';
    }
}
