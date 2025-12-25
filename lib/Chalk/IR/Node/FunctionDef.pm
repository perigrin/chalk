# ABOUTME: FunctionDef node representing function/subroutine definitions
# ABOUTME: Stores function name, parameters, and body IR graph for dispatch
# ABOUTME: Exposes body statements via inputs() for graph traversal
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::FunctionDef {
    field $name :param :reader;                   # Function name (string)
    field $parameters :param :reader = [];        # Parameter names (array of strings)
    field $body_graph :param :reader = undef;     # IR graph for function body
    field $body_node :param :reader = undef;      # Raw body IR node (before graph extraction)
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    # Cached body statement IDs for graph traversal
    field $_body_input_ids = undef;

    # Set body node after construction
    method set_body_node($node) {
        $body_node = $node;
        # Clear cached IDs so they're recomputed on next inputs() call
        $_body_input_ids = undef;
    }

    # Extract IR node IDs from body for graph traversal
    method _compute_body_input_ids() {
        return [] unless defined $body_node;

        my @ids;

        # Body is a hash with {type => 'block', statements => [...IR nodes...]}
        if (ref($body_node) eq 'HASH' && $body_node->{statements}) {
            for my $stmt ($body_node->{statements}->@*) {
                if (blessed($stmt) && $stmt->can('id')) {
                    push @ids, $stmt->id;
                }
            }
        }
        # If body is directly an IR node
        elsif (blessed($body_node) && $body_node->can('id')) {
            push @ids, $body_node->id;
        }

        return \@ids;
    }

    # Return the actual IR node objects from the body
    # Used by XS code generation to process function bodies
    method body_statements() {
        return [] unless defined $body_node;

        # Body is a hash with {type => 'block', statements => [...IR nodes...]}
        if (ref($body_node) eq 'HASH' && $body_node->{statements}) {
            return $body_node->{statements};
        }
        # If body is directly an IR node
        elsif (blessed($body_node) && $body_node->can('id')) {
            return [$body_node];
        }

        return [];
    }

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    # FunctionDef has no data inputs for graph validation purposes
    # Body statements are accessed via body_statements() for XS code generation
    # Note: We don't expose body through inputs() because body statements
    # aren't added to the main graph - they form a separate subgraph
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
