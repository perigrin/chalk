# ABOUTME: Semantic action for ReferenceConstructor - array and hash constructors
# ABOUTME: Pass-through for now - full implementation when IR supports reference construction nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ReferenceConstructor :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ReferenceConstructor -> '[' WS_OPT ExpressionList WS_OPT ']'  # Array constructor
        # ReferenceConstructor -> '[' WS_OPT ']'  # Empty array
        # ReferenceConstructor -> '{' WS_OPT ExpressionList WS_OPT '}'  # Hash constructor
        # ReferenceConstructor -> '{' WS_OPT '}'  # Empty hash

        # TODO: Implement reference constructor IR nodes when available
        # For now, just pass through the opening bracket/brace
        return $context->child(0);
    }
}

1;
