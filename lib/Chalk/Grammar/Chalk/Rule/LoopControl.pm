# ABOUTME: Semantic action for LoopControl rule in Chalk grammar
# ABOUTME: Passes through for LoopControl constructs
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::LoopControl :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Pass through first child
        return $context->child(0);
    }
}

1;
