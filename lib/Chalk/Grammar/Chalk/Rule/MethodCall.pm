# ABOUTME: Semantic action for MethodCall - instance and class method invocations
# ABOUTME: Handles $obj->method() and Class->method() - these are invocations (rvalues), not lvalues

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::MethodCall :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # MethodCall -> Variable '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # MethodCall -> Variable '->' Identifier  # Without parens
        # MethodCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # MethodCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ')'

        # For now, just pass through - method calls are invocations that return values
        # Future: Generate IR nodes for method dispatch
        return $context->child(0);
    }
}

1;
