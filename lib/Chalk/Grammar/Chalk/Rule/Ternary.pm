# ABOUTME: Semantic action for Ternary - generates If/Region/Phi for conditional expressions
# ABOUTME: Handles $cond ? $true_expr : $false_expr control flow

use 5.42.0;
use experimental 'class';
# Note: blessed is auto-imported by use 5.42.0

class Chalk::Grammar::Chalk::Rule::Ternary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::If;
        use Chalk::IR::Node::Proj;
        use Chalk::IR::Node::Region;
        use Chalk::IR::Node::Phi;

        # Ternary -> LogicalOr (pass-through)
        # Ternary -> LogicalOr WS_OPT '?' WS_OPT Expression WS_OPT ':' WS_OPT Ternary

        my @children = $context->children->@*;

        # Pass-through case: single child (just LogicalOr, no ? :)
        if (@children == 1) {
            return $context->child(0);
        }

        # Full ternary: find condition, true_expr, false_expr
        my $condition = $context->child(0);  # First child is LogicalOr (condition)

        # Scan children for '?' and ':' to find expressions
        my ($true_expr, $false_expr);
        my $found_question = 0;
        my $found_colon = 0;

        for my $i (0 .. $#children) {
            my $child_ctx = $children[$i];
            my $child_val = $child_ctx->extract;
            my $str = defined($child_val) ? "$child_val" : '';

            if ($str eq '?') {
                $found_question = 1;
                next;
            }
            if ($str eq ':') {
                $found_colon = 1;
                next;
            }

            # After '?', first IR node is true_expr
            if ($found_question && !$found_colon && !$true_expr) {
                my $val = $context->child($i);
                if (blessed($val) && $val->can('id')) {
                    $true_expr = $val;
                }
            }

            # After ':', first IR node is false_expr
            if ($found_colon && !$false_expr) {
                my $val = $context->child($i);
                if (blessed($val) && $val->can('id')) {
                    $false_expr = $val;
                }
            }
        }

        # Validate we found both expressions
        unless ($true_expr) {
            die "Ternary: missing true expression after '?'";
        }
        unless ($false_expr) {
            die "Ternary: missing false expression after ':'";
        }

        # Create If node with condition
        # inputs: [condition_id] (no control input for expression-level ternary)
        my $if_node = Chalk::IR::Node::If->new(
            inputs       => [$condition->id],
            condition_id => $condition->id,
            condition    => $condition,
        );

        # Create Proj nodes for branches
        my $if_true = Chalk::IR::Node::Proj->new(
            inputs => [$if_node->id],
            index  => 0,
            label  => 'IfTrue',
            source => $if_node,
        );
        my $if_false = Chalk::IR::Node::Proj->new(
            inputs => [$if_node->id],
            index  => 1,
            label  => 'IfFalse',
            source => $if_node,
        );

        # Create Region merging both branches
        my $region = Chalk::IR::Node::Region->new(
            inputs => [$if_true->id, $if_false->id],
        );

        # Create Phi to select result value
        # Phi inputs: [region_id, true_value_id, false_value_id]
        my $phi = Chalk::IR::Node::Phi->new(
            region_id => $region->id,
            inputs    => [$region->id, $true_expr->id, $false_expr->id],
        );

        return $phi;
    }
}

1;
