# ABOUTME: Semantic action for Unary - pass through child value or build unary operation
# ABOUTME: Unary is a wrapper, return child when no prefix operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Unary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Unary -> Postfix (pass-through)
        # Unary -> '!' WS_OPT Unary (TODO: implement Not node)
        # Unary -> 'not' WS_OPT Unary (TODO: implement Not node)
        # Unary -> '-' WS_OPT Unary (TODO: implement Negate node)
        # Unary -> '+' WS_OPT Unary (no-op, just pass through)
        # Unary -> '++' WS_OPT Unary (TODO: implement pre-increment)
        # Unary -> '--' WS_OPT Unary (TODO: implement pre-decrement)
        # Unary -> '\\' WS_OPT Unary (TODO: implement reference operator)

        # For now, just pass through the Postfix child
        return $context->child(0);
    }
}

1;
