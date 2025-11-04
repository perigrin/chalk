# ABOUTME: Semantic action for StringOp - flattened string operators
# ABOUTME: Handles '.' (concatenation) and '..' (range) with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

class Chalk::Grammar::Chalk::Rule::StringOp :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # StringOp -> ArithmeticOp (pass-through)
        # StringOp -> StringOp WS_OPT '.' WS_OPT ArithmeticOp
        # StringOp -> StringOp WS_OPT '..' WS_OPT ArithmeticOp

        # Count children to determine which alternative matched
        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through ArithmeticOp
            return $context->child(0);
        }

        # For binary operation: check child(2) for the operator
        # Grammar is: StringOp WS_OPT OP WS_OPT ArithmeticOp
        # So operator is at index 2
        my $op_child = $children[2]->extract;
        return $context->child(0) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;
        return $context->child(0) unless ($operator eq '.' || $operator eq '..');

        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get left (child 0) and right (child 4)
        my $left = $context->child(0);
        my $right = $context->child(4);

        # Validate that we got IR nodes
        return $left unless (blessed($left) && $left->can('id'));
        return $left unless (blessed($right) && $right->can('id'));

        # Build appropriate IR node based on operator
        if ($operator eq '.') {
            return $builder->build_str_concat_node($left, $right);
        } elsif ($operator eq '..') {
            return $builder->build_range_node($left, $right);
        }

        return $context->child(0);
    }
}

1;
