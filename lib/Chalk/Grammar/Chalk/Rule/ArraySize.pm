# ABOUTME: Semantic action for ArraySize rule in Chalk grammar
# ABOUTME: Passes through for ArraySize constructs
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ArraySize :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Pass through first child
        return $context->child(0);
    }
}

1;
