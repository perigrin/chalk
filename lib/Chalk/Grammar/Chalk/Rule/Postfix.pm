# ABOUTME: Semantic action for Postfix - pass through child value or build postfix operation
# ABOUTME: Postfix is a wrapper, return child when no postfix operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Postfix :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Postfix -> Primary (pass-through)
        # Postfix -> Variable '++' (TODO: implement post-increment)
        # Postfix -> Variable '--' (TODO: implement post-decrement)

        # For now, just pass through the Primary child
        return $context->child(0);
    }
}

1;
