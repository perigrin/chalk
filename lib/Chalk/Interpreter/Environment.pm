# ABOUTME: CEK interpreter environment with discrete context architecture
# ABOUTME: Manages separate node, variable, and heap contexts for interpreter state
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::Interpreter::Context qw(extend_ctx $empty_ctx);

# Capture context helpers for use inside class
my $EMPTY_CTX = $empty_ctx;
my $EXTEND_CTX = \&extend_ctx;

class Chalk::Interpreter::Environment {
    field $node_ctx :param = undef;
    field $var_ctx :param = undef;
    # Future: heap contexts (arrays, hashes, objects)

    ADJUST {
        # Initialize with empty contexts if not provided
        $node_ctx //= $EMPTY_CTX;
        $var_ctx //= $EMPTY_CTX;
    }

    # Node context operations (for IR node computation results)
    method lookup_node($key) {
        return $node_ctx->($key);
    }

    method set_node($key, $value) {
        # Mutating operation - updates this environment's node context
        $node_ctx = $EXTEND_CTX->($node_ctx, $key, $value);
        return;
    }

    method extend_node($key, $value) {
        # Immutable operation - returns new environment
        my $new_node_ctx = $EXTEND_CTX->($node_ctx, $key, $value);
        return Chalk::Interpreter::Environment->new(
            node_ctx => $new_node_ctx,
            var_ctx => $var_ctx
        );
    }

    # Variable context operations (for lexical variable bindings)
    method lookup_variable($key) {
        return $var_ctx->($key);
    }

    method set_variable($key, $value) {
        # Mutating operation - updates this environment's variable context
        $var_ctx = $EXTEND_CTX->($var_ctx, $key, $value);
        return;
    }

    method extend_variable($key, $value) {
        # Immutable operation - returns new environment
        my $new_var_ctx = $EXTEND_CTX->($var_ctx, $key, $value);
        return Chalk::Interpreter::Environment->new(
            node_ctx => $node_ctx,
            var_ctx => $new_var_ctx
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

=item * Heap contexts: Arrays, hashes, objects (future)

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
