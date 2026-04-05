# ABOUTME: Variable declaration node in the Chalk IR.
# ABOUTME: Represents a my/our/local declaration, optionally with an initializer.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::VarDecl :isa(Chalk::IR::Node) {
    method operation() { 'VarDecl' }
}
