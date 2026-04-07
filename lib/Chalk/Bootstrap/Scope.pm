# ABOUTME: Immutable lexical scope mapping variable names to IR node bindings
# ABOUTME: Provides lookup, define (copy-on-write), snapshot, diff, and lazy Phi sentinel operations
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util 'refaddr';
use Chalk::IR::Node::Phi;

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
    # Sentinels are blessed into Chalk::Bootstrap::Scope::Sentinel for
    # unambiguous type detection (plain hashrefs could be confused with IR nodes).
    method fork_for_loop($loop_node) {
        my %sentinel_bindings;
        for my $name (keys $bindings->%*) {
            $sentinel_bindings{$name} = bless {
                sentinel  => true,
                loop      => $loop_node,
                pre_value => $bindings->{$name},
            }, 'Chalk::Bootstrap::Scope::Sentinel';
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
        unless (ref $binding eq 'Chalk::Bootstrap::Scope::Sentinel') {
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

    # Remove a trivial Phi (all operands identical, ignoring self-references).
    # Returns the single common value if trivial, or the Phi if non-trivial.
    # A Phi is trivial when every operand (excluding backedge self-references)
    # is the same node. An undef operand counts as a distinct "no value" path
    # and makes the Phi non-trivial.
    sub _remove_trivial_phi($phi) {
        my $same;
        my $seen_same = false;
        for my $operand ($phi->inputs()->@*) {
            # Skip self-references (loop backedges)
            next if defined $operand
                && ref($operand)
                && refaddr($operand) == refaddr($phi);
            # undef means "value doesn't exist on this path" — that's non-trivial
            # unless we have already established $same as undef
            if (!defined $operand) {
                return $phi if $seen_same;
                next;
            }
            if (!$seen_same) {
                $same = $operand;
                $seen_same = true;
            } elsif (refaddr($same) != refaddr($operand)) {
                return $phi;  # non-trivial: two different values
            }
        }
        return $same // $phi;
    }

    # Merge pre-loop and body-final scopes at a Loop node, creating Phi nodes for
    # variables that differ between loop entry and body exit.
    # $body_scope is a hashref of { var_name => body_final_binding }.
    # $loop is the Loop CFG node.
    # $factory is the NodeFactory.
    # $iterator is the loop variable name (excluded from Phis, or undef if none).
    # Returns a new scope with Phi nodes for loop-carried variables.
    method merge_for_loop($body_scope, $loop, $factory, $iterator) {
        my %merged;

        for my $name ($self->variable_names()) {
            my $pre_val  = $bindings->{$name};
            my $body_val = $body_scope->{$name};

            # Iterator variable is defined by the loop itself — exclude from Phi creation
            if (defined $iterator && $name eq $iterator) {
                $merged{$name} = $pre_val;
                next;
            }

            # If body did not assign this variable, no Phi needed
            if (!defined $body_val
                    || (defined $pre_val && refaddr($pre_val) == refaddr($body_val))) {
                $merged{$name} = $pre_val;
                next;
            }

            # Values differ — create a Phi and wire the backedge immediately
            my $phi = $factory->make('Phi',
                region => $loop,
                values => [$pre_val, undef],
            );
            $phi->set_backedge($body_val);

            $merged{$name} = $phi;
        }

        return Chalk::Bootstrap::Scope->new(bindings => \%merged);
    }

    # Merge two branch scopes at a Region node, creating Phi nodes for variables
    # that have different values (by identity) across the two branches.
    # $then_scope: final scope after the then-branch
    # $else_scope: final scope after the else-branch
    # $region: the Region node representing the merge point
    # $factory: NodeFactory used to create Phi nodes
    # Returns a new Scope with Phi nodes where variables differ between branches.
    method merge_with_phis($then_scope, $else_scope, $region, $factory) {
        my %merged;

        # Collect all variable names from both branches
        my %all_names;
        $all_names{$_} = 1 for $then_scope->variable_names();
        $all_names{$_} = 1 for $else_scope->variable_names();

        for my $name (sort keys %all_names) {
            my $then_val = $then_scope->lookup($name);
            my $else_val = $else_scope->lookup($name);

            # Both undef — variable not bound in either branch, skip
            if (!defined $then_val && !defined $else_val) {
                next;
            }

            # Same node identity — no Phi needed
            if (defined $then_val && defined $else_val
                    && refaddr($then_val) == refaddr($else_val)) {
                $merged{$name} = $then_val;
                next;
            }

            # Values differ (or one branch is undef) — create a Phi node,
            # then simplify away trivial Phis (all operands the same value).
            my $phi = $factory->make('Phi',
                region => $region,
                values => [$then_val, $else_val],
            );
            $merged{$name} = _remove_trivial_phi($phi);
        }

        return Chalk::Bootstrap::Scope->new(bindings => \%merged);
    }
}

1;
