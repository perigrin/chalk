# ABOUTME: Try/catch control flow node in the Chalk IR.
# ABOUTME: Represents a try block paired with one or more catch handlers.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::TryCatch :isa(Chalk::IR::Node) {
    method operation() { 'TryCatch' }
}
