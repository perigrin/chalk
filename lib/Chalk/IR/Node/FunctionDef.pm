# ABOUTME: FunctionDef node representing function/subroutine definitions
# ABOUTME: Stores function name, parameters, and body IR graph for dispatch
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::FunctionDef {
    field $name :param :reader;                   # Function name (string)
    field $parameters :param :reader = [];        # Parameter names (array of strings)
    field $body_graph :param :reader = undef;     # IR graph for function body
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    # FunctionDef has no data inputs - it defines rather than uses
    method inputs() {
        return [];
    }

    method op() { 'FunctionDef' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'FunctionDef',
            inputs => [],
            attributes => {
                name       => $name,
                parameters => $parameters,
                has_body   => defined($body_graph) ? 1 : 0,
            },
        };
    }

    method execute($context) {
        # Return a descriptor for function dispatch
        # This is used by the function registry to look up functions
        return {
            name       => $name,
            parameters => $parameters,
            body_graph => $body_graph,
        };
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # FunctionDef cannot be optimized away
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;
