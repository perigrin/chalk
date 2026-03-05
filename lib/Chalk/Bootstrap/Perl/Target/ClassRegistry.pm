# ABOUTME: Registry mapping class names to their parsed IR for multi-class XS compilation.
# ABOUTME: Tracks dependencies between classes and provides topological compilation order.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Perl::Target::ClassRegistry {
    field %_entries;  # class_name => { ir, sa, ctx, uses => [...] }

    # Register a class with its parsed data.
    # $data should be a hashref with keys: ir, sa, ctx, and optionally uses.
    method register($class_name, $data) {
        $_entries{$class_name} = $data;
    }

    # Resolve a class name to its registered data.
    # Returns the entry hashref or undef if not registered.
    method resolve($class_name) {
        return $_entries{$class_name};
    }

    # Return all registered class names.
    method all_classes() {
        return keys %_entries;
    }

    # Return class names in topological order (dependencies first).
    # Unknown dependencies (not in registry) are silently skipped.
    method compilation_order() {
        my %in_degree;
        my %deps;

        for my $name (keys %_entries) {
            $in_degree{$name} //= 0;
            my $uses = $_entries{$name}{uses} // [];
            my @known = grep { exists $_entries{$_} } $uses->@*;
            $deps{$name} = \@known;
            for my $dep (@known) {
                $in_degree{$dep} //= 0;
                $in_degree{$name}++;
            }
        }

        # Kahn's algorithm — deterministic via sorted queue
        my @queue = sort grep { $in_degree{$_} == 0 } keys %in_degree;
        my @order;

        while (@queue) {
            my $node = shift @queue;
            push @order, $node;

            # Find nodes that depend on $node and decrement
            for my $name (sort keys %deps) {
                if (grep { $_ eq $node } $deps{$name}->@*) {
                    $in_degree{$name}--;
                    if ($in_degree{$name} == 0) {
                        # Insert in sorted position to maintain determinism
                        push @queue, $name;
                        @queue = sort @queue;
                    }
                }
            }
        }

        return @order;
    }
}
