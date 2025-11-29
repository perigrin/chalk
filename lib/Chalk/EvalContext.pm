# ABOUTME: Comonad implementation for semantic evaluation contexts
# ABOUTME: Provides extract, extend, duplicate operations for context-sensitive evaluation

use 5.42.0;
use experimental 'class';

class Chalk::EvalContext {
    use overload '""' => 'to_string';

    field $focus     :param :reader;      # Current semantic value
    field $children  :param :reader;      # Child contexts (array ref)
    field $start_pos :param :reader;      # Parse span start
    field $end_pos   :param :reader;      # Parse span end
    field $env       :param :reader;      # Environment (symbol table)
    field $grammar   :param :reader;      # Grammar reference
    field $rule      :param :reader;      # Rule being evaluated
    field $forest :param :reader = undef; # Optional shared parse forest
    field $type   :param :reader = undef; # Type of the expression (Chalk::Type)
    field $metadata_element :param :reader = undef; # Optional metadata from sibling semirings

    method to_string (@args) {
        my $rule_name = $rule ? $rule->lhs : 'none';
        my $type_name = $type ? ref($type) : 'none';
        return "EvalContext[rule=$rule_name, type=$type_name, pos=$start_pos..$end_pos]";
    }

    # Comonad operation: extract the focus value
    method extract() {
        return $focus;
    }

    # Functor operation: map a function over the focus
    method fmap($f) {
        return Chalk::EvalContext->new(
            focus     => $f->($focus),
            children  => $children,
            start_pos => $start_pos,
            end_pos   => $end_pos,
            env       => $env,
            grammar   => $grammar,
            rule      => $rule,
            forest    => $forest,
            type      => $type,
            metadata_element => $metadata_element
        );
    }

    # Comonad operation: extend with a function
    # The function receives a context and returns a new focus value
    method extend($f) {
        my $new_focus    = $f->($self);
        my @new_children = map { $_->extend($f) } $children->@*;

        return Chalk::EvalContext->new(
            focus     => $new_focus,
            children  => \@new_children,
            start_pos => $start_pos,
            end_pos   => $end_pos,
            env       => $env,
            grammar   => $grammar,
            rule      => $rule,
            forest    => $forest,
            type      => $type,
            metadata_element => $metadata_element
        );
    }

    # Comonad operation: duplicate context
    # Returns a context whose focus is the original context
    method duplicate() {
        my @dup_children = map { $_->duplicate } $children->@*;

        return Chalk::EvalContext->new(
            focus     => $self,
            children  => \@dup_children,
            start_pos => $start_pos,
            end_pos   => $end_pos,
            env       => $env,
            grammar   => $grammar,
            rule      => $rule,
            forest    => $forest,
            type      => $type,
            metadata_element => $metadata_element
        );
    }

    # Convenience method: get extracted value of child at index
    method child($index) {
        return unless $index < scalar( $children->@* );
        return $children->[$index]->extract;
    }

    # Convenience method: get child context at index
    method child_context($index) {
        return unless $index < scalar( $children->@* );
        return $children->[$index];
    }

    # Get SPPF alternatives for the current parse position
    # Returns array of packed nodes representing different parses
    method alternatives() {
        return () unless defined($forest);

        # Get the SPPF node corresponding to this context's parse span
        my $key = sprintf( "%s|%d|%d",
            $rule ? $rule->lhs : "UNKNOWN",
            $start_pos, $end_pos );

        my $nodes = $forest->nodes();
        my $node  = $nodes->{$key};
        return () unless $node;

        return $node->packed_nodes();
    }

    # Get alternatives for a specific child position
    # Useful for querying different parse alternatives of a child
    method child_alternatives($index) {
        return () unless $index < scalar( $children->@* );
        my $child = $children->[$index];
        return $child->alternatives() if $child->can('alternatives');
        return ();
    }
}
