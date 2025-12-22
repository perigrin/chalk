# ABOUTME: Semantic action for ExpressionList - handles comma-separated expressions
# ABOUTME: Returns undef for empty list, passes through single expression, or List node for multiple

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;  # Provides Chalk::GrammarRule base class
use Chalk::IR::Node::List;
use Scalar::Util 'blessed';

class Chalk::Grammar::Chalk::Rule::ExpressionList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my @children = $context->children->@*;

        # ExpressionList ->  (empty)
        if (@children == 0) {
            return undef;
        }

        # Filter to only IR nodes (skip comma tokens and other non-IR children)
        my @ir_nodes;
        for my $child_ctx (@children) {
            my $focus = $child_ctx->focus;
            if (blessed($focus) && $focus->can('id')) {
                push @ir_nodes, $focus;
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
