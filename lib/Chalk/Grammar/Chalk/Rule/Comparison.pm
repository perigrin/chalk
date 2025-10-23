# ABOUTME: Semantic action for Comparison - pass through child value or build comparison operation
# ABOUTME: Comparison is a wrapper, return child when no comparison operator present

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Comparison :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Comparison -> RegexMatch (pass-through)
        # Comparison -> Comparison WS_OPT %NUM_COMPARE_OP% WS_OPT RegexMatch (TODO: implement)
        # Comparison -> Comparison WS_OPT %STRING_COMPARE_OP% WS_OPT RegexMatch (TODO: implement)
        # Comparison -> Comparison WS_OPT 'isa' WS_OPT QualifiedIdentifier (TODO: implement)

        # For now, just pass through the RegexMatch child
        return $context->child(0);
    }
}

1;
