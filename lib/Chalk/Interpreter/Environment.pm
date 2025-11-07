# ABOUTME: CEK interpreter environment with discrete context architecture
# ABOUTME: Manages separate node, variable, and heap contexts for interpreter state

=head1 NAME

Chalk::Interpreter::Environment - CEK interpreter execution state management

=head1 SYNOPSIS

    use Chalk::Interpreter::Environment;

    my $env = Chalk::Interpreter::Environment->new();

    # Node context operations
    $env->set_node($node_id, $value);
    my $value = $env->lookup_node($node_id);

    # Variable context operations
    $env->set_variable($var_name, $value);
    my $value = $env->lookup_variable($var_name);

    # Heap context operations
    my $heap_id = $env->allocate_heap_id();
    $env->set_heap($heap_id, $key, $value);
    my $value = $env->lookup_heap($heap_id, $key);

    # Snapshot/restore for debugging
    my $snapshot = $env->snapshot();
    my $restored_env = $env->restore_from_snapshot($snapshot);

=head1 DESCRIPTION

Chalk::Interpreter::Environment provides execution state management for the
CEK dataflow interpreter with support for time-travel debugging through snapshots.

B<Note on Immutability>: This module offers two patterns:

=over 4

=item * B<Mutating operations> (C<set_node>, C<set_variable>, C<set_heap>)

These modify the environment in place for efficient execution. This is the
primary execution mode used by the CEK interpreter.

=item * B<Extending operations> (C<extend_node>, C<extend_variable>, C<extend_heap>)

These create new environment instances without modifying the original, providing
a functional style when needed for special cases.

=item * B<Snapshot/restore>

Captures and restores complete execution state for time-travel debugging,
enabling checkpoint-based debugging without replay.

=back

This is B<snapshot-based immutability>, not pure functional immutability. The
environment itself is mutable, but snapshots provide immutable checkpoints.
This design provides the performance benefits of mutation with the debugging
benefits of immutability where it matters.

=head1 METHODS

See code below for method documentation.

=cut

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
        $heap_bindings->{$heap_id}->{$key} = $value;  # Track for snapshotting
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
            my $heap_binding = $snapshot->{heap_bindings}->{$heap_id};
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
                map { $_ => { $snapshot->{heap_bindings}->{$_}->%* } }
                keys $snapshot->{heap_bindings}->%*
            },
        );
    }
}

1;
