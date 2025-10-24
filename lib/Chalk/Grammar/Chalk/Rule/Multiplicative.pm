# ABOUTME: Semantic action for Multiplicative - pass through child value or build multiplication/division
# ABOUTME: Multiplicative handles * and / operators, building Multiply/Div IR nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Multiplicative :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Multiplicative -> Unary (pass-through)
        # Multiplicative -> Multiplicative WS_OPT '*' WS_OPT Unary
        # Multiplicative -> Multiplicative WS_OPT '/' WS_OPT Unary

        # Count children to determine which alternative matched
        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through Unary
            return $context->child(0);
        }

        # For binary operation: check child(2) for the operator
        # Grammar is: Multiplicative WS_OPT OP WS_OPT Unary
        # So operator is at index 2
        my $op_child = $children[2]->extract;
        return $context->child(0) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;
        return $context->child(0) unless ($operator eq '*' || $operator eq '/');

        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get left (child 0) and right (child 4)
        my $left = $context->child(0);
        my $right = $context->child(4);

        # Validate that we got IR nodes
        return $left unless (blessed($left) && $left->can('id'));
        return $left unless (blessed($right) && $right->can('id'));

        if ($operator eq '*') {
            return $builder->build_multiply_node($left, $right);
        } elsif ($operator eq '/') {
            return $builder->build_divide_node($left, $right);
        }

        return $context->child(0);
    }
}

1;
