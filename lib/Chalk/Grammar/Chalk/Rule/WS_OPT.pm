# ABOUTME: Semantic action for WS_OPT - optional whitespace (ignored in IR generation)
# ABOUTME: Passes through child value when present, returns undef when empty (epsilon)

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;

class Chalk::Grammar::Chalk::Rule::WS_OPT :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # WS_OPT has two alternatives:
        # 1. WS_OPT -> (epsilon/empty)
        # 2. WS_OPT -> WS_ELEMENT WS_OPT
        #
        # For empty case: return undef (no semantic value)
        # For non-empty case: pass through child(0) which is WS_ELEMENT
        my @children = $context->children->@*;
        return undef unless @children;

        # Pass through child(0) - this allows WS_OPT to work in semantic contexts
        return $context->child(0);
    }
}

1;
