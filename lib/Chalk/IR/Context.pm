# ABOUTME: Context-as-closure abstraction for unified memory model
# ABOUTME: Implements functional closures for context extension and lookup operations

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

    # Creates a typed label for alias analysis (e.g., "lexical:Int:$x", "lexical:Str:$x")
    # Different types create different labels, preventing false aliasing
    sub make_typed_label($class, $namespace, $type, $name) {
        return "${namespace}:${type}:${name}";
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