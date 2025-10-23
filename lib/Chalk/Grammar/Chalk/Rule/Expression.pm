# ABOUTME: Semantic action for Expression - pass through child value
# ABOUTME: Expression is just a wrapper, so return the child IR node directly

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Expression :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Expression -> Assignment (and other alternatives)
        # Just pass through the child value
        return $context->child(0);
    }
}

1;
