# ABOUTME: Semantic action for Ternary - pass through child value or build conditional operation
# ABOUTME: Ternary is a wrapper, return child when no ? : operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Ternary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Ternary -> LogicalOr (pass-through)
        # Ternary -> LogicalOr WS_OPT '?' WS_OPT Expression WS_OPT ':' WS_OPT Ternary (TODO: implement If/Phi)

        # For now, just pass through the LogicalOr child
        # TODO: Implement ternary conditional when we have control flow (Chapter 5)
        return $context->child(0);
    }
}

1;
