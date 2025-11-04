# ABOUTME: Semantic action for RangeOp - range and flip-flop operator
# ABOUTME: Handles '..' (range in list context, flip-flop in scalar context) with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

class Chalk::Grammar::Chalk::Rule::RangeOp :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # RangeOp -> Expression WS_OPT '..' WS_OPT Expression

        # For binary operation: check child(2) for the operator
        # Grammar is: Expression WS_OPT '..' WS_OPT Expression
        # So operator is at index 2
        my @children = $context->children->@*;
        my $op_child = $children[2]->extract;
        return $context->child(0) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;
        return $context->child(0) unless $operator eq '..';

        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get left (child 0) and right (child 4)
        my $left = $context->child(0);
        my $right = $context->child(4);

        # Validate that we got IR nodes
        return $left unless (blessed($left) && $left->can('id'));
        return $left unless (blessed($right) && $right->can('id'));

        # Build range IR node
        # Note: In Perl, .. is a range operator in list context and
        # a flip-flop operator in scalar/boolean context
        return $builder->build_range_node($left, $right);
    }
}

1;
