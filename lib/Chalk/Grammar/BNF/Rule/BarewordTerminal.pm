package Chalk::Grammar::BNF::Rule::BarewordTerminal;
# ABOUTME: Semantic action for BarewordTerminal - extracts bareword identifier as terminal string
# ABOUTME: Handles lowercase keywords like class, method, field that don't need quotes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::BarewordTerminal :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # BarewordTerminal -> /[a-z][a-z0-9_]*/
        # Children: [0] = bareword identifier (string from regex match)

        my @children = map { $_->extract } $context->children->@*;

        # Return the bareword as a terminal string
        return $children[0] if @children > 0;
        return '';
    }
}

1;
