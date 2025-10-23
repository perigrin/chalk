# ABOUTME: Semantic action for RHS rules - collects RHS elements into array
# ABOUTME: Handles empty RHS, single element, and multiple elements

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::RHS :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my $children = $context->children();
        my @children = map { $_->extract() } $children->@*;

        # RHS -> []  (empty production)
        return [] if @children == 0;

        # RHS -> RHSElement  (single element)
        if (@children == 1) {
            my $elem = $children[0];
            return defined($elem) ? [$elem] : [];
        }

        # RHS -> RHSElement WS RHS  (multiple elements)
        if (@children == 3) {
            my ($elem, $ws, $rest) = @children;
            my @result = ();
            push(@result, $elem) if defined($elem);

            if (ref($rest) eq 'ARRAY') {
                push(@result, $rest->@*);
            }

            my $result_ref = [@result];
            return $result_ref;
        }

        return [];
    }
}

