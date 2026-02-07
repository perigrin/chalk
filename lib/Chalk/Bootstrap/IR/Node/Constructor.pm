# ABOUTME: IR node for constructing grammar objects (Symbol, Expression, Rule).
# ABOUTME: Parameterized by class field to determine target construction type.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Constructor :isa(Chalk::Bootstrap::IR::Node) {
    field $class :param :reader;

    method operation() {
        return 'Constructor';
    }
}

1;
