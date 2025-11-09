# ABOUTME: Semantic action for WS_OPT - optional whitespace (ignored in IR generation)
# ABOUTME: Returns undef since whitespace doesn't produce IR nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::WS_OPT :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Whitespace is not significant for IR generation
        # Return undef to indicate no IR node produced
        return undef;
    }
}

1;
