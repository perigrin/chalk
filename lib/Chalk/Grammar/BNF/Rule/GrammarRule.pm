package Chalk::Grammar::BNF::Rule::GrammarRule;
# ABOUTME: Semantic action for GrammarRule - builds [LHS, RHS] array for Grammar
# ABOUTME: Extracts nonterminal name and RHS elements

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

        my @children = map { $_->extract } $context->children->@*;

        # Extract LHS (nonterminal name)
        my $lhs = $children[0];

        # Extract RHS (array of symbols)
        # Inline comment at [5] is automatically ignored (only present in 6-child case)
        my $rhs = $children[4] // [];
        $rhs = [] unless ref($rhs) eq 'ARRAY';

        # Return rule in format expected by build_grammar: [LHS, RHS]
        return [$lhs, $rhs];
    }
}

1;
