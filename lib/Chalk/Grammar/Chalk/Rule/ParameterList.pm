# ABOUTME: Semantic action for ParameterList rule in Chalk grammar
# ABOUTME: Passes through parameter list for method/function signatures
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ParameterList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ParameterList -> Variable
        # ParameterList -> Variable WS_OPT ',' WS_OPT ParameterList
        # ParameterList -> Assignment
        # ParameterList -> Assignment WS_OPT ',' WS_OPT ParameterList
        # ParameterList ->  (empty)
        # Pass through first child if present, or undef for empty
        return $context->child(0);
    }
}

1;
