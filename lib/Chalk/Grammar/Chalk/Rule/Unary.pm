# ABOUTME: Semantic action for Unary - pass through child value or build unary operation
# ABOUTME: Unary handles prefix operators like !, -, +, \, building appropriate IR nodes

use 5.42.0;
use experimental 'class';
use Scalar::Util 'blessed';

class Chalk::Grammar::Chalk::Rule::Unary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Unary -> Postfix (pass-through)
        # Unary -> '!' WS_OPT Unary (unary operation)
        #   Where OpUnary can be: !, -, +, ~, \
        # NOTE: WS_OPT is collapsed when empty, so child count varies

        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through Postfix
            return $context->child(0);
        }

        # For unary operation: check child(0) for the operator
        my $op_child = $children[0]->extract;
        return $context->child(0) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;
        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get operand at child 1 (WS_OPT is collapsed/absent when empty)
        my $operand = $context->child(1);

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
        } elsif ($operator eq '\\') {
            return $builder->build_reference_node($operand);
        }
        # For other operators (~), pass through for now
        # These will be implemented in future phases

        return $context->child(0);
    }
}

1;
