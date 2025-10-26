# ABOUTME: Semantic action for Unary - pass through child value or build unary operation
# ABOUTME: Unary handles prefix operators like !, -, +, building appropriate IR nodes

use 5.42.0;
use experimental 'class';
use Scalar::Util 'blessed';

class Chalk::Grammar::Chalk::Rule::Unary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ExprUnary -> ExprPower (pass-through)
        # ExprUnary -> OpUnary WS_OPT ExprUnary (unary operation)
        #   Where OpUnary can be: !, -, +, ~, \

        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through ExprPower
            return $context->child(0);
        }

        # For unary operation: check child(0) for the operator
        my $op_child = $children[0]->extract;
        return $context->child(0) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;
        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get operand (child 2, after WS_OPT at child 1)
        my $operand = $context->child(2);

        # Validate that we got an IR node
        return $operand unless (blessed($operand) && $operand->can('id'));

        # Build appropriate unary node
        if ($operator eq '!') {
            return $builder->build_not_node($operand);
        } elsif ($operator eq '-') {
            return $builder->build_negate_node($operand);
        } elsif ($operator eq '+') {
            # Unary + is a no-op, just pass through
            return $operand;
        }
        # For other operators (~, \, ++, --), pass through for now
        # These will be implemented in future phases

        return $context->child(0);
    }
}

1;
