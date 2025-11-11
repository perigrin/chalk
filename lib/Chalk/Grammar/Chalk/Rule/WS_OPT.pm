# ABOUTME: Semantic action for WS_OPT (optional whitespace) - pass-through rule
# ABOUTME: Returns first child or undef if no children (epsilon production)

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::WS_OPT :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # WS_OPT -> WS_ELEMENT WS_OPT (recursive)
        # WS_OPT ->  (epsilon - empty)
        # Pass through first child if present, or return undef for epsilon
        return $context->child(0);
    }
}

1;
