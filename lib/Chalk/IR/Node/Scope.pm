# ABOUTME: ScopeNode for Sea of Nodes IR - maintains symbol tables for lexical scoping
# ABOUTME: Utility node (not Data/Control) that keeps variable bindings alive through inputs
use 5.42.0;
use experimental qw(class builtin);
use utf8;
use Scalar::Util 'refaddr';

class Chalk::IR::Node::Scope {
    # Scope is a special utility node that doesn't inherit from Base
    # It implements the same interface but isn't added to the graph

    field $id :reader;
    field $inputs :reader;
    field $scope_stack :reader;

    ADJUST {
        # Generate ID using object address (Scope nodes aren't in graph registry)
        $id = 'scope_' . refaddr($self);
        $inputs = [];

        # Initialize scope stack
        $scope_stack = [];
        # Always start with a global scope
        $self->push_scope();
    }

    method op() { 'Scope' }

    method push_scope() {
        # Create new lexical scope level
        push $scope_stack->@*, {};
        return;
    }

    method pop_scope() {
        # Exit current scope (but keep global scope)
        my $depth = scalar($scope_stack->@*);
        if ($depth > 1) {
            pop $scope_stack->@*;
        }
        return;
    }

    method define($name, $node_id) {
        # Define a variable in the current (innermost) scope
        my $current_scope = $scope_stack->[-1];
        $current_scope->{$name} = $node_id;

        # Add the node as an input to keep it alive (per Chapter 3)
        # "nodes referenced by names become inputs to the ScopeNode"
        push $inputs->@*, $node_id;

        return;
    }

    method lookup($name) {
        # Look up a variable, searching from innermost to outermost scope
        for my $i (0 .. $#$scope_stack) {
            my $scope = $scope_stack->[$#$scope_stack - $i];
            if (exists($scope->{$name})) {
                return $scope->{$name};
            }
        }
        # Variable not found
        return undef;
    }

    method depth() {
        # Return current scope nesting depth
        return scalar($scope_stack->@*);
    }

    method current_bindings() {
        # Return all bindings in the current scope
        return $scope_stack->[-1];
    }

    method all_bindings() {
        # Return all bindings from all scopes (for debugging)
        my %all = ();
        for my $scope ($scope_stack->@*) {
            %all = (%all, $scope->%*);
        }
        return \%all;
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Scope',
            inputs => $self->inputs,
            attributes => {
                depth => $self->depth(),
                bindings => $self->all_bindings(),
            },
        };
    }

    method execute() {
        # Scope nodes don't execute in the interpreter
        # They're parse-time utilities for tracking variable bindings
        return $self;
    }
}

1;
