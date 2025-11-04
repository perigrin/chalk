# ABOUTME: Semantic action for Unary - handles both prefix and postfix unary operators
# ABOUTME: Phase 4: Flattened from Unary + Postfix - handles prefix (!, -, +, \, ++, --) and postfix (++, --)

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

class Chalk::Grammar::Chalk::Rule::Unary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Unary -> Primary (pass-through)
        # Unary -> '!' WS_OPT Unary (prefix operators)
        # Unary -> Variable '++' (postfix increment)
        # Unary -> Variable '--' (postfix decrement)

        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through Primary
            return $context->child(0);
        }

        # Check if this is a postfix operator (Variable ++)
        # Postfix pattern: child(0) is Variable, child(1) is operator
        if (@children == 2) {
            my $last_child = $children[-1]->extract;
            if (defined($last_child) && !ref($last_child) && ($last_child eq '++' || $last_child eq '--')) {
                # This is postfix: Variable '++' or Variable '--'
                # TODO: Implement postfix increment/decrement when IR nodes available
                return $context->child(0);
            }
        }

        # Otherwise, this is a prefix operator: check child(0) for the operator
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
        } elsif ($operator eq '++' || $operator eq '--') {
            # Prefix ++/--
            # TODO: Implement prefix increment/decrement when IR nodes available
            return $operand;
        }

        return $context->child(0);
    }
}

1;
