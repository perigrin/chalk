# ABOUTME: Semantic action for VariableList rule in Chalk grammar
# ABOUTME: Passes through for VariableList constructs
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::VariableList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Pass through first child
        return $context->child(0);
    }
}

1;
