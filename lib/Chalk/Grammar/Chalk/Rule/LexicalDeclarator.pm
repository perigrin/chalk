# ABOUTME: Semantic action for LexicalDeclarator - returns the declarator keyword
# ABOUTME: LexicalDeclarator handles 'my', 'state', 'field' keywords and passes through value

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::LexicalDeclarator :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # LexicalDeclarator -> 'my' | 'state' | 'field'
        # Just pass through the keyword string
        return $context->child(0);
    }
}

1;
