# ABOUTME: Semantic action for RHSElement - extracts terminal, nonterminal, or pattern ref
# ABOUTME: Just passes through the child value

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::RHSElement :isa(Chalk::GrammarRule) {

    method evaluate($context) {

        # RHSElement -> Terminal | Nonterminal | PatternRef
        # Just return the child value
        my $children = $context->children();
        my @children = map { $_->extract() } $children->@*;
        return $children[0] if @children > 0;
        return;
    }
}

