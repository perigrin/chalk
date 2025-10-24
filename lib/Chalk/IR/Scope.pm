# ABOUTME: Scope management for Sea of Nodes IR variable tracking
# ABOUTME: Maintains stack of symbol tables mapping variable names to IR nodes for SSA form
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Scope {
    use Chalk::IR::Node;

    # Stack of scopes, each scope is a hashref mapping variable names to node IDs
    field $scope_stack :reader;

    ADJUST {
        $scope_stack = [];
        # Always start with a global scope
        $self->push_scope();
    }

    method push_scope() {
        # Create new scope level
        push $scope_stack->@*, {};
        return;
    }

    method pop_scope() {
        # Exit current scope
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
}

1;
