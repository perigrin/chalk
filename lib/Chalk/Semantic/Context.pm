# ABOUTME: Semantic context for managing compilation state with scopes and source tracking
# ABOUTME: Provides explicit context handling for semantic actions with scope management
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Semantic::Scope;

class Chalk::Semantic::Context {
    field $current_scope  :reader;
    field $source_info    :param :reader = undef;
    field @scope_stack;
    field $_scope         :param = undef;  # Internal parameter for derive()
    field $_scope_stack   :param = undef;  # Internal parameter for derive()

    ADJUST {
        # If we're being derived, use the provided scope and stack
        if (defined $_scope && defined $_scope_stack) {
            $current_scope = $_scope;
            @scope_stack = @$_scope_stack;
        } else {
            # Initialize with a root scope
            $current_scope = Chalk::Semantic::Scope->new();
            @scope_stack = ($current_scope);
        }
    }

    # Bind a variable in the current scope
    method bind($name, $value) {
        $current_scope->bind($name, $value);
    }

    # Lookup a variable in the current scope (and parents)
    method lookup($name) {
        return $current_scope->lookup($name);
    }

    # Enter a new nested scope
    method enter_scope() {
        my $new_scope = Chalk::Semantic::Scope->new(parent => $current_scope);
        push @scope_stack, $new_scope;
        $current_scope = $new_scope;
        return $new_scope;
    }

    # Exit the current scope and return to parent
    method exit_scope() {
        die "Cannot exit root scope" if scalar(@scope_stack) <= 1;

        pop @scope_stack;
        $current_scope = $scope_stack[-1];
        return $current_scope;
    }

    # Get formatted source location string
    method source_location() {
        return $source_info ? $source_info->to_string() : undef;
    }

    # Derive a new context with updated source location
    method derive(%args) {
        my $new_source_info = $args{source_info} // $source_info;

        # Create new context that shares the current scope
        my $derived = Chalk::Semantic::Context->new(
            source_info  => $new_source_info,
            _scope       => $current_scope,
            _scope_stack => [@scope_stack],
        );

        return $derived;
    }
}

1;
