package Chalk::EvalContext;
# ABOUTME: Comonad implementation for semantic evaluation contexts
# ABOUTME: Provides extract, extend, duplicate operations for context-sensitive evaluation

use 5.42.0;
use experimental 'class';

class Chalk::EvalContext {
    field $focus :param :reader;        # Current semantic value
    field $children :param :reader;     # Child contexts (array ref)
    field $start_pos :param :reader;    # Parse span start
    field $end_pos :param :reader;      # Parse span end
    field $env :param :reader;          # Environment (symbol table)
    field $grammar :param :reader;      # Grammar reference
    field $rule :param :reader;         # Rule being evaluated

    # Comonad operation: extract the focus value
    method extract() {
        return $focus;
    }

    # Functor operation: map a function over the focus
    method fmap($f) {
        return Chalk::EvalContext->new(
            focus => $f->($focus),
            children => $children,
            start_pos => $start_pos,
            end_pos => $end_pos,
            env => $env,
            grammar => $grammar,
            rule => $rule
        );
    }

    # Comonad operation: extend with a function
    # The function receives a context and returns a new focus value
    method extend($f) {
        my $new_focus = $f->($self);
        my @new_children = map { $_->extend($f) } @$children;

        return Chalk::EvalContext->new(
            focus => $new_focus,
            children => \@new_children,
            start_pos => $start_pos,
            end_pos => $end_pos,
            env => $env,
            grammar => $grammar,
            rule => $rule
        );
    }

    # Comonad operation: duplicate context
    # Returns a context whose focus is the original context
    method duplicate() {
        my @dup_children = map { $_->duplicate } @$children;

        return Chalk::EvalContext->new(
            focus => $self,
            children => \@dup_children,
            start_pos => $start_pos,
            end_pos => $end_pos,
            env => $env,
            grammar => $grammar,
            rule => $rule
        );
    }

    # Convenience method: get extracted value of child at index
    method child($index) {
        return undef unless $index < scalar(@$children);
        return $children->[$index]->extract;
    }

    # Convenience method: get child context at index
    method child_context($index) {
        return undef unless $index < scalar(@$children);
        return $children->[$index];
    }
}

1;
