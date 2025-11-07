# ABOUTME: Context-as-closure abstraction for unified memory model
# ABOUTME: Implements functional closures for context extension and lookup operations

=head1 NAME

Chalk::IR::Context - Functional closure-based context implementation

=head1 SYNOPSIS

    use Chalk::IR::Context;

    # Create empty context
    my $ctx = Chalk::IR::Context->empty_context();

    # Extend context (functional style - returns new context)
    $ctx = Chalk::IR::Context->extend_context($ctx, "node:1", 42);

    # Lookup value
    my $value = $ctx->("node:1");  # Returns: 42

    # Flatten context for snapshotting
    my $bindings = Chalk::IR::Context->flatten_context($ctx, ["node:1", "node:2"]);

    # Rebuild context from bindings
    $ctx = Chalk::IR::Context->rebuild_context($bindings);

=head1 DESCRIPTION

Functional closure-based context implementation for Chalk interpreter.

Contexts are implemented as closures that capture parent contexts, creating
a chain for lookups. The Context abstraction itself is purely functional:
C<extend_context> returns a new context without modifying the parent.

B<Important Distinction>: While the Context abstraction is purely functional
(immutable closure chains), values stored IN contexts may come from mutable
environments. The Context provides the functional abstraction layer, but does
not enforce immutability on the values it stores.

B<Performance Consideration>: Closure chains have O(n) lookup time where n is
the depth of the chain (number of extensions). For large contexts (1000+ bindings),
consider the performance implications. The C<rebuild_context> method can optimize
deep chains by flattening and rebuilding.

=head1 METHODS

=over 4

=item empty_context()

Returns a base context closure that returns undef for any label.

=item extend_context($parent, $label, $value)

Creates a new context extending the parent with a label->value binding.
Returns a new closure without modifying the parent (functional style).

=item make_label($namespace, $name)

Creates a namespaced label to prevent collisions (e.g., "var:x", "temp:t1").

=item make_index_label($index)

Creates an index label for array elements (e.g., "index:0").

=item make_key_label($key)

Creates a key label for hash elements (e.g., "key:foo").

=item flatten_context($ctx, $known_keys)

Flattens a context closure into a hash by extracting all bindings.
Enables snapshotting of execution state.

=item rebuild_context($bindings_hash)

Rebuilds a context closure from a flattened hash.
Enables restoring from snapshots.

=back

=cut

use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Context {
    # Returns base closure that returns undef for any label
    sub empty_context($class) {
        return sub ($label) {
            return undef;
        };
    }

    # Creates new context extending parent with label->value binding
    sub extend_context($class, $parent, $label, $value) {
        return sub ($lookup_label) {
            return $value if $lookup_label eq $label;
            return $parent->($lookup_label);
        };
    }

    # Creates a namespaced label to prevent collisions (e.g., "var:x", "temp:t1")
    sub make_label($class, $namespace, $name) {
        return "${namespace}:${name}";
    }

    # Creates index label for array elements (e.g., "index:0", "index:1")
    sub make_index_label($class, $index) {
        return "index:${index}";
    }

    # Creates key label for hash elements (e.g., "key:foo", "key:bar")
    sub make_key_label($class, $key) {
        return "key:${key}";
    }

    # Flatten a context closure into a hash by extracting all bindings
    # This enables snapshotting of execution state
    sub flatten_context($class, $ctx, $known_keys) {
        my %bindings;

        # Extract all known keys from the context
        foreach my $key ($known_keys->@*) {
            my $value = $ctx->($key);
            $bindings{$key} = $value if defined $value;
        }

        return \%bindings;
    }

    # Rebuild a context closure from a flattened hash
    # This enables restoring from snapshots
    sub rebuild_context($class, $bindings_hash) {
        my $ctx = $class->empty_context();

        # Extend context with each binding (sorted for deterministic order)
        foreach my $key (sort keys $bindings_hash->%*) {
            $ctx = $class->extend_context($ctx, $key, $bindings_hash->{$key});
        }

        return $ctx;
    }
}