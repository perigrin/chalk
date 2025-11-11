# ABOUTME: Semantic action for ForStatement rule in Chalk grammar
# ABOUTME: Passes through for ForStatement constructs
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ForStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Pass through first child
        return $context->child(0);
    }
}

1;
