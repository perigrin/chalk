# ABOUTME: Immutable lexical scope mapping variable names to IR node bindings
# ABOUTME: Provides lookup, define (copy-on-write), snapshot, and diff operations for scope threading
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util 'refaddr';

class Chalk::Bootstrap::Scope {
    # Hash mapping variable names (strings like '$x', '@arr', '%hash') to IR nodes
    field $bindings :param = undef;

    # Initialize bindings to empty hash if not provided
    ADJUST {
        $bindings //= {};
    }

    # Look up a variable by name
    # Returns the IR node if bound, undef otherwise
    method lookup($name) {
        return $bindings->{$name};
    }

    # Define a new binding (or overwrite existing)
    # Returns a NEW Scope with the binding added (immutable operation)
    method define($name, $node) {
        # Create a new bindings hash with the added/updated binding
        my %new_bindings = $bindings->%*;
        $new_bindings{$name} = $node;

        # Return new Scope with updated bindings
        return Chalk::Bootstrap::Scope->new(bindings => \%new_bindings);
    }

    # Return a plain hashref copy of current bindings
    # Used for later diffing via diff()
    method snapshot() {
        return { $bindings->%* };
    }

    # Compare current bindings against a previous snapshot
    # Returns hash of name => current_node for variables that changed or were added
    # Uses refaddr for identity comparison (not string comparison)
    method diff($snapshot) {
        my %changes;

        # Check all current bindings
        for my $name (keys $bindings->%*) {
            my $current = $bindings->{$name};
            my $previous = $snapshot->{$name};

            # Variable is new or changed if:
            # 1. Not in snapshot (new variable)
            # 2. Different node reference (modified)
            if (!defined $previous || refaddr($current) != refaddr($previous)) {
                $changes{$name} = $current;
            }
        }

        return \%changes;
    }

    # Return count of bound variable names
    method size() {
        return scalar keys $bindings->%*;
    }

    # Merge another scope's bindings into this one, returning a new Scope.
    # The other scope's bindings take precedence for duplicate names.
    method merge($other) {
        my %new_bindings = $bindings->%*;
        for my $name ($other->variable_names()) {
            $new_bindings{$name} = $other->lookup($name);
        }
        return Chalk::Bootstrap::Scope->new(bindings => \%new_bindings);
    }

    # Return list of all bound variable names
    method variable_names() {
        return keys $bindings->%*;
    }
}

1;
