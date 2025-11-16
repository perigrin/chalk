# ABOUTME: Semantic action for LogicalOp - flattened logical operators
# ABOUTME: Handles logical OR (||, or, //) and AND (&&, and) operators with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::LogicalOp :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # LogicalOp -> ComparisonOp (pass-through)
        # LogicalOp -> LogicalOp WS_OPT '||' WS_OPT ComparisonOp
        # LogicalOp -> LogicalOp WS_OPT 'or' WS_OPT ComparisonOp
        # LogicalOp -> LogicalOp WS_OPT '//' WS_OPT ComparisonOp
        # LogicalOp -> LogicalOp WS_OPT '&&' WS_OPT ComparisonOp
        # LogicalOp -> LogicalOp WS_OPT 'and' WS_OPT ComparisonOp

        # Count children to determine which alternative matched
        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through ComparisonOp
            return $context->child(0);
        }

        # For binary operation: check child(2) for the operator
        # Grammar is: LogicalOp WS_OPT OP WS_OPT ComparisonOp
        # So operator is at index 2
        return $context->child(0) unless defined $children[2];
        my $op_child = $children[2]->extract;
        return $context->child(0) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;

        # TODO: Implement IR nodes for logical operators when available
        # For now, just pass through left side
        # Valid operators: ||, or, //, &&, and
        return $context->child(0) unless ($operator eq '||' || $operator eq 'or' || $operator eq '//' ||
                                          $operator eq '&&' || $operator eq 'and');

        # When IR builder methods are available, implement like this:
        # my $builder = $context->env->{ir_builder};
        # return $context->child(0) unless $builder;
        #
        # my $left = $context->child(0);
        # my $right = $context->child(4);
        #
        # return $left unless (blessed($left) && $left->can('id'));
        # return $left unless (blessed($right) && $right->can('id'));
        #
        # if ($operator eq '||' || $operator eq 'or') {
        #     return $builder->build_logical_or_node($left, $right);
        # } elsif ($operator eq '//') {
        #     return $builder->build_defined_or_node($left, $right);
        # } elsif ($operator eq '&&' || $operator eq 'and') {
        #     return $builder->build_logical_and_node($left, $right);
        # }

        return $context->child(0);
    }
}

1;
