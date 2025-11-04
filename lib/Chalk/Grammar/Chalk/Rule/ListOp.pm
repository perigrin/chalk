# ABOUTME: Semantic action for ListOp - list operations (map, grep, all, any)
# ABOUTME: Pass-through for now - full implementation when IR supports list op nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ListOp :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ListOp -> 'map' WS_OPT Block WS_OPT Expression
        # ListOp -> 'grep' WS_OPT Block WS_OPT Expression
        # ListOp -> 'all' WS_OPT Block WS_OPT Expression
        # ListOp -> 'any' WS_OPT Block WS_OPT Expression

        # TODO: Implement list operation IR nodes when available
        # For now, just pass through the operation keyword
        return $context->child(0);
    }
}

1;
