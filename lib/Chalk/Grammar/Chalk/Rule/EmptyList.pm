# ABOUTME: Semantic action for EmptyList rule in Chalk grammar
# ABOUTME: Passes through for EmptyList constructs
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::EmptyList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Pass through first child
        return $context->child(0);
    }
}

1;
