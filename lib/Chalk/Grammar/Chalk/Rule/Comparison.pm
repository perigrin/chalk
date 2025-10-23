# ABOUTME: Semantic action for Comparison - pass through child value or build comparison operation
# ABOUTME: Comparison handles comparison operators, building Greater/Less/Equal IR nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Comparison :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Comparison -> RegexMatch (pass-through)
        # Comparison -> Comparison WS_OPT %NUM_COMPARE_OP% WS_OPT RegexMatch
        # Comparison -> Comparison WS_OPT %STRING_COMPARE_OP% WS_OPT RegexMatch
        # Comparison -> Comparison WS_OPT 'isa' WS_OPT QualifiedIdentifier

        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through RegexMatch
            return $context->child(0);
        }

        # For binary operation: check child(2) for the operator
        my $op_child = $children[2]->extract;
        return $context->child(0) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;
        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get left (child 0) and right (child 4)
        my $left = $context->child(0);
        my $right = $context->child(4);

        # Validate that we got IR nodes
        return $left unless (blessed($left) && $left->can('id'));
        return $left unless (blessed($right) && $right->can('id'));

        # Build appropriate comparison node
        if ($operator eq '>' || $operator eq 'gt') {
            return $builder->build_greater_node($left, $right);
        } elsif ($operator eq '<' || $operator eq 'lt') {
            return $builder->build_less_node($left, $right);
        } elsif ($operator eq '==' || $operator eq 'eq') {
            return $builder->build_equal_node($left, $right);
        } elsif ($operator eq '>=') {
            # >= is "not less than" but for simplicity, just use Greater for now
            # TODO: Implement GreaterOrEqual
            return $builder->build_greater_node($left, $right);
        } elsif ($operator eq '<=') {
            # <= is "not greater than"
            # TODO: Implement LessOrEqual
            return $builder->build_less_node($left, $right);
        } elsif ($operator eq '!=' || $operator eq 'ne') {
            # != is "not equal"
            # TODO: Implement NotEqual
            return $builder->build_equal_node($left, $right);
        }

        return $context->child(0);
    }
}

1;
