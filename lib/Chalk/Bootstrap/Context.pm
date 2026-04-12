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
    field $token       :param :reader = undef;
    field $is_zero     :param :reader = false;

    # Extract the current focus value from the context
    method extract() {
        return $focus;
    }

    # Apply a function to this context, creating a new context with the result as focus
    # This is the comonad 'extend' operation: (Context -> a) -> Context -> Context
    # Optional %opts may include rule => $name and annotations => $hashref overrides.
    method extend($f, %opts) {
        my $new_focus = $f->($self);
        return Chalk::Bootstrap::Context->new(
            focus       => $new_focus,
            children    => [$self],
            position    => $position,
            rule        => (exists $opts{rule} ? $opts{rule} : $rule),
            annotations => (exists $opts{annotations} ? $opts{annotations} : { $annotations->%* }),
            token       => (exists $opts{token} ? $opts{token} : $token),
            is_zero     => (exists $opts{is_zero} ? $opts{is_zero} : $is_zero),
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
    method leaves($node_class = undef) {
        return $self->walk_all(sub ($node) {
            my $f = $node->extract();
            if (!$node_class || $f isa $node_class) {
                return $node;
            }
            return undef;
        });
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

    # Walk the tree and return the first defined result from $callback.
    # Descends through unfocused multiply nodes, stops at focused leaves.
    # Optional reverse => true for right-to-left traversal.
    method walk($callback, %opts) {
        my $reverse = $opts{reverse};
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f) {
                my $result = $callback->($node);
                return $result if defined $result;
                next;
            }
            my @kids = $node->children()->@*;
            @kids = reverse @kids unless $reverse;
            push @stack, @kids;
        }

        return undef;
    }

    # Walk the tree and collect all defined results from $callback.
    # Descends through unfocused multiply nodes, stops at focused leaves.
    # Optional reverse => true for right-to-left traversal.
    method walk_all($callback, %opts) {
        my $reverse = $opts{reverse};
        my @results;
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f) {
                my $result = $callback->($node);
                push @results, $result if defined $result;
                next;
            }
            my @kids = $node->children()->@*;
            @kids = reverse @kids unless $reverse;
            push @stack, @kids;
        }

        return @results;
    }

    # Walk the tree threading an accumulator through focused leaves.
    # $callback->($acc, $node) returns the new accumulator value.
    # Optional reverse => true for right-to-left traversal.
    method walk_acc($init, $callback, %opts) {
        my $reverse = $opts{reverse};
        my $acc = $init;
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f) {
                $acc = $callback->($acc, $node);
                next;
            }
            my @kids = $node->children()->@*;
            @kids = reverse @kids unless $reverse;
            push @stack, @kids;
        }

        return $acc;
    }
}
