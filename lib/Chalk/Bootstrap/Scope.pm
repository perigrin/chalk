# ABOUTME: Immutable lexical scope mapping variable names to IR node bindings
# ABOUTME: Provides lookup, define (copy-on-write), snapshot, diff, and lazy Phi sentinel operations
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util 'refaddr';
use Chalk::Bootstrap::IR::Node::Phi;

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

    # Create a new Scope with all bindings replaced by sentinels.
    # Each sentinel records the Loop node and the pre-loop binding value.
    # Called at loop entry to enable lazy Phi creation.
    method fork_for_loop($loop_node) {
        my %sentinel_bindings;
        for my $name (keys $bindings->%*) {
            $sentinel_bindings{$name} = {
                sentinel  => true,
                loop      => $loop_node,
                pre_value => $bindings->{$name},
            };
        }
        return Chalk::Bootstrap::Scope->new(bindings => \%sentinel_bindings);
    }

    # Resolve a sentinel for a variable, creating a Phi on demand.
    # Returns ($value, $new_scope):
    #   - If sentinel: creates Phi, returns (Phi, new Scope with Phi replacing sentinel)
    #   - If non-sentinel binding: returns (binding, undef)
    #   - If unbound: returns (undef, undef)
    method resolve_sentinel($name, $factory) {
        my $binding = $bindings->{$name};
        return (undef, undef) unless defined $binding;

        # Non-sentinel: return the binding directly
        unless (ref $binding eq 'HASH' && $binding->{sentinel}) {
            return ($binding, undef);
        }

        # Sentinel: create a Phi node with backedge placeholder
        my $phi = $factory->make('Phi',
            region => $binding->{loop},
            values => [$binding->{pre_value}, undef],
        );

        # Replace sentinel with Phi in a new scope
        my $new_scope = $self->define($name, $phi);
        return ($phi, $new_scope);
    }

    # Return the raw binding without resolving sentinels.
    # Used during backedge wiring to distinguish sentinels from Phis.
    method raw_lookup($name) {
        return $bindings->{$name};
    }
}

1;
