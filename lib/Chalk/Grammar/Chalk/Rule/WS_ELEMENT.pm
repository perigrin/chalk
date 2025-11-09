# ABOUTME: Semantic action for WS_ELEMENT - handles whitespace or comments
# ABOUTME: Returns undef since neither whitespace nor comments produce IR nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::WS_ELEMENT :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # WS_ELEMENT -> %WS% | %COMMENT%
        # Whitespace and comments are not significant for IR generation
        # Return undef to indicate no IR node produced
        return undef;
    }
}

1;
