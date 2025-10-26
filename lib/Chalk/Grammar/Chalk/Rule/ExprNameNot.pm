# ABOUTME: Semantic action for ExprNameNot - handles 'not' keyword operator
# ABOUTME: ExprNameNot handles the 'not' keyword which is Perl's named logical negation

use 5.42.0;
use experimental 'class';
use Scalar::Util 'blessed';

class Chalk::Grammar::Chalk::Rule::ExprNameNot :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ExprNameNot -> ExprComma (pass-through)
        # ExprNameNot -> OpNameNot WS_OPT ExprNameNot
        #   Where OpNameNot is the keyword 'not'

        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through ExprComma
            return $context->child(0);
        }

        # For 'not' operation: check child(0) for the operator
        my $op_child = $children[0]->extract;
        return $context->child(0) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;
        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get operand (child 2, after WS_OPT at child 1)
        my $operand = $context->child(2);

        # Validate that we got an IR node
        return $operand unless (blessed($operand) && $operand->can('id'));

        # Build Not node for 'not' keyword (same as '!')
        if ($operator eq 'not') {
            return $builder->build_not_node($operand);
        }

        # Fallback - shouldn't reach here
        return $context->child(0);
    }
}

1;
