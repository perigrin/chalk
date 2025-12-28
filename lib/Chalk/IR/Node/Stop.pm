# ABOUTME: Stop node representing program termination point in the IR graph
# ABOUTME: Collects all Return nodes, FunctionDef nodes, and ClassDef nodes
# ABOUTME: Makes function bodies and class definitions available to XS generator
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Stop :isa(Chalk::IR::Node::Base) {
    # Object references to Return nodes (for graph traversal)
    field $returns :param :reader = [];
    # Object references to FunctionDef nodes (for XS code generation)
    field $functions :param :reader = [];
    # Object references to ClassDef nodes (for XS class generation)
    field $class_defs :param :reader = [];

    method op() { 'Stop' }

    # Add a Return node to this Stop (per Chapter 18: STOP.addDef(ret))
    # Called when building the graph to connect returns to Stop
    method add_return($return_node) {
        return unless defined $return_node;
        push $returns->@*, $return_node;
        push $self->inputs->@*, $return_node->id;
    }

    # Add a FunctionDef node to this Stop for XS code generation
    # Note: FunctionDefs are NOT added to inputs because they're stored in
    # FunctionRegistry, not the main graph. XS generator accesses them via
    # function_defs() method instead of graph traversal.
    method add_function($func_def) {
        return unless defined $func_def;
        push $functions->@*, $func_def;
    }

    # Add a ClassDef node to this Stop for XS class generation
    # ClassDefs define object structure and are emitted as separate XS modules
    method add_class($class_def) {
        return unless defined $class_def;
        push $class_defs->@*, $class_def;
    }

    # Provide accessor for Return node objects
    # Used by graph traversal to follow object references
    method return_nodes() {
        return $returns;
    }

    # Provide accessor for FunctionDef node objects
    # Used by XS code generation to emit separate XSUBs per function
    method function_defs() {
        return $functions;
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Stop',
            inputs => $self->inputs,
            attributes => {
                class_defs => [map { $_->id } $class_defs->@*],
            },
        };
    }

    # Clone with new inputs for GVN optimizer
    # Translates old input IDs to new node IDs using node_map
    method clone_with_inputs($new_inputs, $node_map, $new_attributes = {}) {
        # Translate old input IDs to new return nodes using node_map
        my @new_returns;
        my @translated_inputs;
        for my $input_id (@$new_inputs) {
            if (defined($input_id) && exists($node_map->{$input_id})) {
                my $new_node = $node_map->{$input_id};
                push @new_returns, $new_node;
                push @translated_inputs, $new_node->id;
            }
        }

        # Create new Stop with translated returns
        # Functions and class_defs are preserved as-is (they're in registry, not graph)
        return Chalk::IR::Node::Stop->new(
            inputs     => \@translated_inputs,
            returns    => \@new_returns,
            functions  => $functions,
            class_defs => $class_defs,
        );
    }

    method execute($context) {
        # Stop node collects all returns and executes the one from the active path
        # Returns are connected as inputs to Stop
        my @inputs = $self->inputs->@*;

        # Execute each Return input - the active one will return a value
        for my $input_id (@inputs) {
            my $return_result = $context->("node:$input_id");
            # If this Return executed (not undef), return its value
            return $return_result if defined($return_result);
        }

        # No active return found
        return undef;
    }
}

1;
