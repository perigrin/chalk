# ABOUTME: Comonad for threading context through parser and semantic actions.
# ABOUTME: Implements extract, extend, and duplicate operations for functional composition.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Context {
    field $focus       :param :reader;
    field $children    :param :reader = [];
    field $position    :param :reader = 0;
    field $rule        :param :reader = undef;
    field $annotations :param :reader = {};

    # Extract the current focus value from the context
    method extract() {
        return $focus;
    }

    # Apply a function to this context, creating a new context with the result as focus
    # This is the comonad 'extend' operation: (Context -> a) -> Context -> Context
    method extend($f) {
        my $new_focus = $f->($self);
        return Chalk::Bootstrap::Context->new(
            focus       => $new_focus,
            children    => $children,
            position    => $position,
            rule        => $rule,
            annotations => $annotations,
        );
    }

    # Create a context of contexts
    # duplicate() = extend(id) where id is the identity function
    method duplicate() {
        return $self->extend(sub ($ctx) { return $ctx });
    }

    # Collect leaf contexts with defined focuses from this Context tree.
    # A "leaf" is a context that has a defined focus (from on_complete).
    # Optional $node_class filters to only contexts whose focus isa $node_class.
    # Iterative (explicit stack) to avoid deep-recursion on tall parse trees.
    method leaves($node_class = undef) {
        my @results;
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f) {
                # This context has a focus — it's a "leaf" produced by on_complete
                if (!$node_class || $f isa $node_class) {
                    push @results, $node;
                }
                # Leaves don't recurse into their own children
                next;
            }

            # No focus — intermediate multiply() node. Push children in reverse
            # order so leftmost child is processed first (preserving original order).
            push @stack, reverse $node->children()->@*;
        }

        return @results;
    }

    # Extract concatenated scanned text from this Context tree.
    # Walks the tree and collects all string focuses (from on_scan),
    # concatenating them in order. Non-string (ref) focuses do not contribute
    # text, but their children are still walked (same as undef focus nodes).
    # Iterative (explicit stack) to avoid deep-recursion on tall parse trees.
    method scanned_text() {
        my $text = '';
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f && !ref($f)) {
                # String focus from on_scan — accumulate text, no child recursion
                $text .= $f;
                next;
            }

            # Undef focus (intermediate node) or ref focus (IR node from on_complete):
            # either way, recurse into children to collect scanned text.
            # Push children in reverse order so leftmost child is processed first.
            push @stack, reverse $node->children()->@*;
        }

        return $text;
    }
}
