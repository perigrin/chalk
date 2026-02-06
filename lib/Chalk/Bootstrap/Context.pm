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
}
