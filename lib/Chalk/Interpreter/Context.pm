# ABOUTME: CEK interpreter functional context implementation
# ABOUTME: Provides immutable closure-based context management for interpreter
package Chalk::Interpreter::Context;
use 5.42.0;
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(extend_ctx $empty_ctx flatten_ctx rebuild_ctx);

# Empty context: returns undef for any key
our $empty_ctx = sub ($key) { return undef; };

# Extend context with a new binding
# Returns a new closure that captures the parent context
sub extend_ctx ($parent_ctx, $key, $value) {
    return sub ($lookup_key) {
        if ($lookup_key eq $key) {
            return $value;
        }
        return $parent_ctx->($lookup_key);
    };
}

# Flatten a context closure into a hash by extracting all bindings
# This enables snapshotting of execution state
# Note: Uses a heuristic approach - tries common keys and stores found values
sub flatten_ctx ($ctx, $known_keys) {
    my %bindings;

    # Extract all known keys from the context
    foreach my $key (@$known_keys) {
        my $value = $ctx->($key);
        $bindings{$key} = $value if defined $value;
    }

    return \%bindings;
}

# Rebuild a context closure from a flattened hash
# This enables restoring from snapshots
sub rebuild_ctx ($bindings_hash) {
    my $ctx = $empty_ctx;

    # Extend context with each binding
    foreach my $key (keys %$bindings_hash) {
        $ctx = extend_ctx($ctx, $key, $bindings_hash->{$key});
    }

    return $ctx;
}

1;

__END__

=head1 NAME

Chalk::Interpreter::Context - Functional context management for CEK interpreter

=head1 SYNOPSIS

    use Chalk::Interpreter::Context qw(extend_ctx $empty_ctx);

    # Start with empty context
    my $ctx = $empty_ctx;

    # Extend with bindings
    $ctx = extend_ctx($ctx, 'x', 42);
    $ctx = extend_ctx($ctx, 'y', 100);

    # Lookup values
    say $ctx->('x');  # 42
    say $ctx->('y');  # 100
    say $ctx->('z');  # undef

=head1 DESCRIPTION

This module provides immutable, closure-based context management for the CEK
(Control-Environment-Kontinuation) interpreter. Contexts are represented as
closures that capture their parent context, creating an immutable chain of
bindings.

=head1 EXPORTS

=head2 $empty_ctx

The base empty context that returns undef for any key.

=head2 extend_ctx($parent_ctx, $key, $value)

Creates a new context by extending the parent context with a new key-value
binding. Returns a closure that looks up the key first, then chains to the
parent for other keys.

=head1 DESIGN

This functional context design provides:

=over 4

=item * Immutability: Old contexts remain unchanged when new bindings are added

=item * Time-travel debugging: Previous contexts can be retained and inspected

=item * Self-hosting optimization: Constant label lookups can be inlined away

=item * Serializable execution: Contexts are data, not mutable state

=back

=cut
