# ABOUTME: Semantic action for HashVar rule in Chalk grammar
# ABOUTME: Passes through for HashVar constructs
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::HashVar :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Pass through first child
        return $context->child(0);
    }
}

1;
