# ABOUTME: Comonad for threading context through parser and semantic actions.
# ABOUTME: Implements extract, extend, and duplicate operations for functional composition.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::Context {
    field $focus    :param :reader;
    field $children :param :reader = [];
    field $position :param :reader = 0;
    field $rule     :param :reader = undef;

    # Extract the current focus value from the context
    method extract() {
        return $focus;
    }

    # Apply a function to this context, creating a new context with the result as focus
    # This is the comonad 'extend' operation: (Context -> a) -> Context -> Context
    method extend($f) {
        my $new_focus = $f->($self);
        return Chalk::Bootstrap::Context->new(
            focus    => $new_focus,
            children => $children,
            position => $position,
            rule     => $rule,
        );
    }

    # Create a context of contexts
    # duplicate() = extend(id) where id is the identity function
    method duplicate() {
        return $self->extend(sub ($ctx) { return $ctx });
    }

    # Collect leaf contexts with defined focuses from this Context tree.
    # A "leaf" is a context that has a defined focus (from complete_value).
    # Optional $node_class filters to only contexts whose focus isa $node_class.
    method leaves($node_class = undef) {
        my @results;

        my $focus = $self->extract();
        if (defined $focus) {
            # This context has a focus — it's a "leaf" produced by complete_value
            if (!$node_class || $focus isa $node_class) {
                push @results, $self;
            }
            return @results;
        }

        # No focus — this is an intermediate multiply() node. Recurse into children.
        for my $child ($children->@*) {
            push @results, $child->leaves($node_class);
        }

        return @results;
    }

    # Extract concatenated scanned text from this Context tree.
    # Walks the tree and collects all string focuses (from scan_value),
    # concatenating them in order. Skips non-string focuses (IR nodes from complete_value).
    method scanned_text() {
        my $focus = $self->extract();
        if (defined $focus && !ref($focus)) {
            # String focus from scan_value
            return $focus;
        }

        # Recurse into children and concatenate
        my $text = '';
        for my $child ($children->@*) {
            $text .= $child->scanned_text();
        }
        return $text;
    }
}
