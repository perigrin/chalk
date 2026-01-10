# ABOUTME: Semantic action for ExpressionList - handles comma-separated expressions
# ABOUTME: Returns undef for empty list, passes through single expression, or List node for multiple

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;  # Provides Chalk::GrammarRule base class
use Chalk::IR::Node::List;
# Note: blessed is auto-imported by use 5.42.0

class Chalk::Grammar::Chalk::Rule::ExpressionList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my @children = $context->children->@*;

        # ExpressionList ->  (empty)
        if (@children == 0) {
            return undef;
        }

        # Filter to only IR nodes (skip comma tokens and other non-IR children)
        # IMPORTANT: Flatten nested List nodes created by right-recursive grammar rules
        # Grammar: ExpressionList -> Expression ',' ExpressionList (right-recursive)
        # This creates: [expr1, expr2, List[expr3, expr4, List[...]]]
        # We need: [expr1, expr2, expr3, expr4, ...]
        my @ir_nodes;
        for my $child_ctx (@children) {
            my $focus = $child_ctx->focus;
            if (blessed($focus) && $focus->can('id')) {
                # Recursively flatten nested List nodes
                if ($focus->can('op') && $focus->op eq 'List' && $focus->can('elements')) {
                    push @ir_nodes, $focus->elements->@*;
                } else {
                    push @ir_nodes, $focus;
                }
            }
        }

        # No IR nodes found
        if (@ir_nodes == 0) {
            return undef;
        }

        # Single expression - pass through directly
        if (@ir_nodes == 1) {
            return $ir_nodes[0];
        }

        # Multiple expressions - create List node
        return Chalk::IR::Node::List->new(
            inputs   => [],
            elements => \@ir_nodes,
        );
    }
}

1;
