# ABOUTME: CFG normal-exit node for a Chalk computation graph.
# ABOUTME: Takes control and value inputs; represents a regular function return.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Return :isa(Chalk::IR::Node) {
    # Marks a Return synthesized by _finalize_body_graph for the
    # implicit fall-through case (the source had a bare trailing
    # expression). Codegen emits a synthetic Return as a bare value;
    # an explicit-source Return emits `return EXPR;`.
    field $synthetic :param :reader = false;

    method operation() { 'Return' }
}
