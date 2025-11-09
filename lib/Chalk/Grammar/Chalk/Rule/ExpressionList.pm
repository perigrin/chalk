# ABOUTME: Semantic action for ExpressionList - handles comma-separated expressions
# ABOUTME: Returns undef for empty list, passes through single expression, or builds list structure

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ExpressionList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my @children = $context->children->@*;

        # ExpressionList ->  (empty)
        if (@children == 0) {
            return undef;
        }

        # ExpressionList -> Expression  (single expression)
        if (@children == 1) {
            return $context->child(0);
        }

        # For multiple expressions or fat-comma pairs, we'd need to build
        # an array/list IR structure. For now, just pass through the first.
        # TODO: Implement proper list/array IR nodes
        return $context->child(0);
    }
}

1;
