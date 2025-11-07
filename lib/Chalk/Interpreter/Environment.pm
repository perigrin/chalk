# ABOUTME: CEK interpreter environment with discrete context architecture
# ABOUTME: Manages separate node, variable, and heap contexts for interpreter state
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::IR::Context;

# Helper closures for context operations
my $EMPTY_CTX = sub { Chalk::IR::Context->empty_context() };
my $EXTEND_CTX = sub ($parent, $key, $value) {
    Chalk::IR::Context->extend_context($parent, $key, $value);
};
my $REBUILD_CTX = sub ($bindings) {
    Chalk::IR::Context->rebuild_context($bindings);
};

class Chalk::Interpreter::Environment {
    field $node_ctx :param = undef;
    field $var_ctx :param = undef;
    field $next_heap_id :param = 1;  # Counter for heap ID allocation
    field $heap_ctxs :param = undef; # Hash mapping heap_id => context

    # Tracking hashes for snapshotting (parallel to contexts)
    field $node_bindings :param = undef;
    field $var_bindings :param = undef;
    field $heap_bindings :param = undef;  # Hash mapping heap_id => bindings hash

    ADJUST {
        # Initialize with empty contexts if not provided
        $node_ctx //= $EMPTY_CTX->();
        $var_ctx //= $EMPTY_CTX->();
        $heap_ctxs //= {};  # Initialize heap contexts hash

        # Initialize tracking hashes
        $node_bindings //= {};
        $var_bindings //= {};
        $heap_bindings //= {};
    }

    # Node context operations (for IR node computation results)
    method lookup_node($key) {
        return $node_ctx->($key);
    }

    method set_node($key, $value) {
        # Mutating operation - updates this environment's node context
        $node_ctx = $EXTEND_CTX->($node_ctx, $key, $value);
        $node_bindings->{$key} = $value;  # Track for snapshotting
        return;
    }

    method extend_node($key, $value) {
        # Immutable operation - returns new environment
        my $new_node_ctx = $EXTEND_CTX->($node_ctx, $key, $value);
        my $new_node_bindings = { $node_bindings->%*, $key => $value };
        return Chalk::Interpreter::Environment->new(
            node_ctx => $new_node_ctx,
            var_ctx => $var_ctx,
            next_heap_id => $next_heap_id,
            heap_ctxs => $heap_ctxs,
            node_bindings => $new_node_bindings,
            var_bindings => $var_bindings,
            heap_bindings => $heap_bindings
        );
    }

    # Variable context operations (for lexical variable bindings)
    method lookup_variable($key) {
        return $var_ctx->($key);
    }

    method set_variable($key, $value) {
        # Mutating operation - updates this environment's variable context
        $var_ctx = $EXTEND_CTX->($var_ctx, $key, $value);
        $var_bindings->{$key} = $value;  # Track for snapshotting
        return;
    }

    method extend_variable($key, $value) {
        # Immutable operation - returns new environment
        my $new_var_ctx = $EXTEND_CTX->($var_ctx, $key, $value);
        my $new_var_bindings = { $var_bindings->%*, $key => $value };
        return Chalk::Interpreter::Environment->new(
            node_ctx => $node_ctx,
            var_ctx => $new_var_ctx,
            next_heap_id => $next_heap_id,
            heap_ctxs => $heap_ctxs,
            node_bindings => $node_bindings,
            var_bindings => $new_var_bindings,
            heap_bindings => $heap_bindings
        );
    }

    # Heap ID allocation
    method allocate_heap_id() {
        # Returns a new unique heap ID and increments counter
        my $id = $next_heap_id;
        $next_heap_id++;

        # Initialize empty context for this heap structure
        $heap_ctxs->{$id} = $EMPTY_CTX->();
        $heap_bindings->{$id} = {};  # Track for snapshotting

        return $id;
    }

    # Heap context operations (for arrays, hashes, objects)
    method lookup_heap($heap_id, $key) {
        my $ctx = $heap_ctxs->{$heap_id};
        die "lookup_heap: invalid heap_id '$heap_id' (not allocated)"
            unless defined $ctx;
        return $ctx->($key);
    }

    method set_heap($heap_id, $key, $value) {
        # Mutating operation - updates this heap's context
        die "set_heap: invalid heap_id '$heap_id' (not allocated)"
            unless exists $heap_ctxs->{$heap_id};
        my $old_ctx = $heap_ctxs->{$heap_id};
        $heap_ctxs->{$heap_id} = $EXTEND_CTX->($old_ctx, $key, $value);
        $heap_bindings->{$heap_id}{$key} = $value;  # Track for snapshotting
        return;
    }

    method extend_heap($heap_id, $key, $value) {
        # Immutable operation - returns new environment
        my $old_ctx = $heap_ctxs->{$heap_id} // $EMPTY_CTX->();
        my $new_ctx = $EXTEND_CTX->($old_ctx, $key, $value);

        my $new_heap_ctxs = { $heap_ctxs->%* };  # Shallow copy
        $new_heap_ctxs->{$heap_id} = $new_ctx;

        my $new_heap_bindings = { $heap_bindings->%* };
        my $old_bindings = $heap_bindings->{$heap_id} // {};
        $new_heap_bindings->{$heap_id} = { $old_bindings->%*, $key => $value };

        return Chalk::Interpreter::Environment->new(
            node_ctx => $node_ctx,
            var_ctx => $var_ctx,
            next_heap_id => $next_heap_id,
            heap_ctxs => $new_heap_ctxs,
            node_bindings => $node_bindings,
            var_bindings => $var_bindings,
            heap_bindings => $new_heap_bindings
        );
    }

    # Snapshot/restore functionality for Phase 4
    method snapshot() {
        # Create a complete snapshot of environment state
        # Returns a hash ref that can be used to restore this environment
        return {
            node_bindings => { $node_bindings->%* },
            var_bindings => { $var_bindings->%* },
            next_heap_id => $next_heap_id,
            heap_bindings => {
                map { $_ => { $heap_bindings->{$_}->%* } } keys $heap_bindings->%*
            },
        };
    }

    method restore_from_snapshot($snapshot) {
        # Restore environment from a snapshot
        # Rebuilds contexts from the tracked bindings
        # Performance Note: This performs a deep copy of all bindings, which
        # may be expensive for large execution states (O(n) where n = total bindings).
        my $new_node_ctx = $REBUILD_CTX->($snapshot->{node_bindings});
        my $new_var_ctx = $REBUILD_CTX->($snapshot->{var_bindings});

        my $new_heap_ctxs = {};
        foreach my $heap_id (keys $snapshot->{heap_bindings}->%*) {
            my $heap_binding = $snapshot->{heap_bindings}{$heap_id};
            $new_heap_ctxs->{$heap_id} = $REBUILD_CTX->($heap_binding);
        }

        return Chalk::Interpreter::Environment->new(
            node_ctx => $new_node_ctx,
            var_ctx => $new_var_ctx,
            next_heap_id => $snapshot->{next_heap_id},
            heap_ctxs => $new_heap_ctxs,
            node_bindings => { $snapshot->{node_bindings}->%* },
            var_bindings => { $snapshot->{var_bindings}->%* },
            heap_bindings => {
                map { $_ => { $snapshot->{heap_bindings}{$_}->%* } }
                keys $snapshot->{heap_bindings}->%*
            },
        );
    }
}

1;

__END__

=head1 NAME

Chalk::Interpreter::Environment - Discrete context architecture for CEK interpreter

=head1 SYNOPSIS

    use Chalk::Interpreter::Environment;

    # Create new environment
    my $env = Chalk::Interpreter::Environment->new();

    # Mutating operations
    $env->set_node('node_1', 42);
    $env->set_variable('x', 100);

    # Lookup operations
    my $node_val = $env->lookup_node('node_1');      # 42
    my $var_val  = $env->lookup_variable('x');       # 100

    # Immutable operations (return new environment)
    my $new_env = $env->extend_node('node_2', 99);
    # $env unchanged, $new_env has both bindings

=head1 DESCRIPTION

This class implements the discrete context architecture for the CEK interpreter.
Instead of a single monolithic context, the environment consists of separate,
independent contexts:

=over 4

=item * Node context: IR node computation results

=item * Variable context: Lexical variable bindings

=item * Heap contexts: Each array, hash, and object gets its own discrete context

=back

=head2 Design Benefits

=over 4

=item * Perfect isolation between different types of state

=item * Actor model readiness (each context can be an actor)

=item * Natural distribution capabilities

=item * Independent versioning per context type

=item * ECA (Event-Condition-Action) compatibility

=back

=head1 METHODS

=head2 Node Context Operations

=head3 lookup_node($key)

Lookup a value in the node context. Returns undef if not found.

=head3 set_node($key, $value)

Mutating operation. Updates the node context by extending it with a new binding.

=head3 extend_node($key, $value)

Immutable operation. Returns a new Environment with extended node context.
The original environment is unchanged.

=head2 Variable Context Operations

=head3 lookup_variable($key)

Lookup a value in the variable context. Returns undef if not found.

=head3 set_variable($key, $value)

Mutating operation. Updates the variable context by extending it with a new binding.

=head3 extend_variable($key, $value)

Immutable operation. Returns a new Environment with extended variable context.
The original environment is unchanged.

=head2 Heap Operations

=head3 allocate_heap_id()

Allocates and returns a unique heap ID for a new heap structure (array, hash, or object).
Automatically initializes an empty context for this heap ID.

=head3 lookup_heap($heap_id, $key)

Lookup a value in the specified heap structure's context. Returns undef if the
key is not found. Dies with an error message if the heap_id has not been allocated.

=head3 set_heap($heap_id, $key, $value)

Mutating operation. Updates the specified heap's context by extending it with a new binding.
Dies with an error message if the heap_id has not been allocated.

=head3 extend_heap($heap_id, $key, $value)

Immutable operation. Returns a new Environment with the specified heap's context extended.
The original environment is unchanged.

=head2 Snapshot and Restore Operations

=head3 snapshot()

Creates a complete snapshot of environment state. Returns a hash reference
containing all bindings from all contexts that can be used to restore this
environment later.

=head3 restore_from_snapshot($snapshot)

Restores environment from a snapshot created by C<snapshot()>. Rebuilds all
contexts from the tracked bindings.

B<Performance Note:> This performs a deep copy of all bindings, which may be
expensive for large execution states (O(n) where n = total bindings). For
production use with large programs, consider implementing a copy-on-write
optimization.

=head1 CONTEXT ARCHITECTURE

The environment uses functional closures (via Chalk::Interpreter::Context) to
implement immutable context chains. Each context is a closure that:

=over 4

=item * Looks up keys in its local bindings first

=item * Chains to parent context for unknown keys

=item * Maintains immutability through closure capture

=back

This enables time-travel debugging, serializable execution, and self-hosting
optimization where constant lookups can be inlined away.

=cut
