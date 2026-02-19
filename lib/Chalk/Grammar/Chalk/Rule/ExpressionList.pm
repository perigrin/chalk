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
        # Helper to recursively flatten List nodes
        my $flatten_list;
        $flatten_list = sub {
            my ($node) = @_;
            my @results;

            if ($node->can('op') && $node->op eq 'List' && $node->can('elements')) {
                # This is a List node - flatten its elements recursively
                say STDERR "DEBUG ExpressionList: Flattening nested List with " . scalar($node->elements->@*) . " elements";
                for my $elem ($node->elements->@*) {
                    push @results, $flatten_list->($elem);
                }
            } else {
                # Not a List - return as-is
                say STDERR "DEBUG ExpressionList: Adding node with op=" . ($node->can('op') ? $node->op : 'NO_OP');
                push @results, $node;
            }

            return @results;
        };

        my @ir_nodes;
        for my $child_ctx (@children) {
            my $focus = $child_ctx->focus;
            if (blessed($focus) && $focus->can('id')) {
                push @ir_nodes, $flatten_list->($focus);
            }
        }
        say STDERR "DEBUG ExpressionList: Total ir_nodes collected: " . scalar(@ir_nodes);

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
