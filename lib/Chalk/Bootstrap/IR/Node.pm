# ABOUTME: Base class for all IR nodes in the Sea of Nodes representation
# ABOUTME: Provides use-def chains and common node interface
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node {

    # Stable content-based ID for the node
    field $id :param :reader;

    # Producer nodes - nodes that produce values consumed by this node
    field $inputs :param :reader = [];

    # Consumer nodes - nodes that consume values produced by this node
    # This is mutable to allow building the graph
    field $consumers :reader = [];

    # Add a consumer to this node's consumer list
    method add_consumer($node) {
        push $consumers->@*, $node;
    }

    # Remove a consumer from this node's consumer list
    method remove_consumer($node) {
        my $target_addr = refaddr($node);
        $consumers->@* = grep { refaddr($_) != $target_addr } $consumers->@*;
    }

    # Abstract method - subclasses must implement
    method operation() {
        die "Subclass must implement operation()";
    }
}
