# ABOUTME: Semantic action for FunctionCall - function and method calls
# ABOUTME: Pass-through for now - full implementation when IR supports call nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::FunctionCall :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # FunctionCall -> Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # FunctionCall -> Identifier '(' WS_OPT ')'
        # FunctionCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # FunctionCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ')'

        # TODO: Implement function call IR nodes when available
        # For now, just pass through the function name
        return $context->child(0);
    }
}

1;
