# ABOUTME: Semantic action for GrammarRule - creates Chalk::GrammarRule objects
# ABOUTME: Extracts nonterminal name and RHS elements and wraps in GrammarRule object

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::GrammarRule :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Two alternatives:
        # 1. GrammarRule -> Nonterminal WS '->' WS RHS Comment (6 children)
        # 2. GrammarRule -> Nonterminal WS '->' WS RHS (5 children)
        # Children: [0] = LHS nonterminal name (string)
        #           [1] = whitespace (ignore)
        #           [2] = '->' (ignore)
        #           [3] = whitespace (ignore)
        #           [4] = RHS (array of symbols)
        #           [5] = optional inline comment (ignore if present)

        my $children = $context->children();
        my @children = map { $_->extract() } $children->@*;

        # Extract LHS (nonterminal name)
        my $lhs = $children[0];

        # Extract RHS (array of symbols)
        # Inline comment at [5] is automatically ignored (only present in 6-child case)
        my $rhs = $children[4] // [];
        $rhs = [] unless ref($rhs) eq 'ARRAY';

        # Return a Chalk::GrammarRule object directly
        return Chalk::GrammarRule->new(
            lhs         => $lhs,
            rhs         => $rhs,
            probability => 1.0
        );
    }
}

