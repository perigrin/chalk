# ABOUTME: Semantic action for Range - pass through child value or build range operation
# ABOUTME: Range handles '..' operator, building Range IR nodes

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

class Chalk::Grammar::Chalk::Rule::Range :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Range -> Concatenation (pass-through)
        # Range -> Range WS_OPT '..' WS_OPT Concatenation

        # Count children to determine which alternative matched
        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through Concatenation
            return $context->child(0);
        }

        # For binary operation: check child(2) for the operator
        # Grammar is: Range WS_OPT '..' WS_OPT Concatenation
        # So operator is at index 2
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

        return $builder->build_range_node($left, $right);
    }
}

1;
