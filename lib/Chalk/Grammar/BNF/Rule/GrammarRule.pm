package Chalk::Grammar::BNF::Rule::GrammarRule;
# ABOUTME: Semantic action for GrammarRule - builds [LHS, RHS] array for Grammar
# ABOUTME: Extracts nonterminal name and RHS elements

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::GrammarRule :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # GrammarRule -> Nonterminal WS '->' WS RHS
        # Children: [0] = LHS nonterminal name (string)
        #           [1] = whitespace (ignore)
        #           [2] = '->' (ignore)
        #           [3] = whitespace (ignore)
        #           [4] = RHS (array of symbols)

        my @children = map { $_->extract } $context->children->@*;

        # Extract LHS (nonterminal name)
        my $lhs = $children[0];

        # Extract RHS (array of symbols)
        my $rhs = $children[4] // [];
        $rhs = [] unless ref($rhs) eq 'ARRAY';

        # Return rule in format expected by build_grammar: [LHS, RHS]
        return [$lhs, $rhs];
    }
}

1;
