# ABOUTME: Semantic action for Nonterminal - extracts nonterminal name
# ABOUTME: Returns the nonterminal identifier as a string

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::Nonterminal :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Nonterminal -> /[A-Z][a-zA-Z0-9_]*/
        # Children: [0] = nonterminal name (string from regex match)

        my $children = $context->children();
        my @children = map { $_->extract() } $children->@*;

        # Return the nonterminal name
        return $children[0] if @children > 0;
        return '';
    }
}
