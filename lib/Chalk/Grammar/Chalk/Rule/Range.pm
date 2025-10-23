# ABOUTME: Semantic action for Range - pass through child value or build range operation
# ABOUTME: Range is a wrapper, return child when no .. operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Range :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Range -> Concatenation (pass-through)
        # Range -> Range WS_OPT '..' WS_OPT Concatenation (TODO: implement)

        # For now, just pass through the Concatenation child
        return $context->child(0);
    }
}

1;
