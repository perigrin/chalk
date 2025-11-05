# ABOUTME: Lexical scope for variable bindings with parent chain support
# ABOUTME: Enables nested scopes with shadowing and lexical lookup through parent scopes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::Semantic::Scope {
    field $parent :param :reader = undef;
    field %bindings;

    # Bind a variable to a value in this scope
    method bind($name, $value) {
        $bindings{$name} = $value;
    }

    # Lookup a variable, checking parent scopes if not found locally
    method lookup($name) {
        # Check local scope first
        return $bindings{$name} if exists $bindings{$name};

        # Check parent scope if available
        return $parent ? $parent->lookup($name) : undef;
    }

    # Check if variable is bound in this scope or parent scopes
    method has_binding($name) {
        return 1 if exists $bindings{$name};
        return $parent ? $parent->has_binding($name) : 0;
    }

    # Check if variable is bound locally (doesn't check parent)
    method has_local_binding($name) {
        return exists $bindings{$name};
    }

    # Get all local bindings (doesn't include parent bindings)
    method get_bindings() {
        return {%bindings};
    }
}

1;
