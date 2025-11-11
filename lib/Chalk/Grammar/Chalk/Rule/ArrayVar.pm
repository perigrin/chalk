# ABOUTME: Semantic action for ArrayVar rule in Chalk grammar
# ABOUTME: Passes through array variable tokens (@var or @_)
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ArrayVar :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ArrayVar -> '@' Identifier
        # ArrayVar -> '@' %SPECIAL_IDENTIFIER%
        # Pass through first child (the @ sigil)
        return $context->child(0);
    }
}

1;
