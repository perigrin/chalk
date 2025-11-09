# ABOUTME: Semantic action for Identifier - passes through terminal identifier value
# ABOUTME: Returns the raw identifier string for use in variable lookups and IR generation

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Identifier :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Identifier -> %IDENTIFIER%
        # Just pass through the terminal value (the identifier string)
        return $context->child(0);
    }
}

1;
