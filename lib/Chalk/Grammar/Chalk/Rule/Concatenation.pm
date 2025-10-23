# ABOUTME: Semantic action for Concatenation - pass through child value or build concatenation operation
# ABOUTME: Concatenation is a wrapper, return child when no . operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Concatenation :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Concatenation -> Additive (pass-through)
        # Concatenation -> Concatenation WS_OPT '.' WS_OPT Additive (TODO: implement)

        # For now, just pass through the Additive child
        return $context->child(0);
    }
}

1;
