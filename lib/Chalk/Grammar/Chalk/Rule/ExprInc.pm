# ABOUTME: Semantic action for ExprInc - handles increment/decrement operators (++/--)
# ABOUTME: ExprInc handles both pre-increment (++$x) and post-increment ($x++) operators

use 5.42.0;
use experimental 'class';
use Scalar::Util 'blessed';

class Chalk::Grammar::Chalk::Rule::ExprInc :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ExprInc -> ExprArrow (pass-through)
        # ExprInc -> OpInc WS_OPT ExprArrow (pre-increment/decrement)
        # ExprInc -> ExprArrow WS_OPT OpInc (post-increment/decrement)
        #   Where OpInc can be: ++, --

        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through ExprArrow
            return $context->child(0);
        }

        # Check if child(0) is an operator (pre-inc/dec) or operand (post-inc/dec)
        my $first_child = $children[0]->extract;
        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Determine if this is pre- or post-increment/decrement
        if (defined $first_child && !ref($first_child) && ($first_child eq '++' || $first_child eq '--')) {
            # Pre-increment/decrement: operator at child(0), operand at child(2)
            my $operator = $first_child;
            my $operand = $context->child(2);

            # Validate that we got an IR node
            return $operand unless (blessed($operand) && $operand->can('id'));

            if ($operator eq '++') {
                return $builder->build_pre_increment_node($operand);
            } elsif ($operator eq '--') {
                return $builder->build_pre_decrement_node($operand);
            }
        } else {
            # Post-increment/decrement: operand at child(0), operator at child(2)
            my $operand = $context->child(0);
            my $op_child = $children[2]->extract;

            return $operand unless (defined $op_child && !ref($op_child) && ($op_child eq '++' || $op_child eq '--'));
            return $operand unless (blessed($operand) && $operand->can('id'));

            my $operator = $op_child;

            if ($operator eq '++') {
                return $builder->build_post_increment_node($operand);
            } elsif ($operator eq '--') {
                return $builder->build_post_decrement_node($operand);
            }
        }

        # Fallback - shouldn't reach here
        return $context->child(0);
    }
}

1;
