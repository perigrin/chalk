# ABOUTME: Semantic action for PostfixDeref - postfix dereferencing operators
# ABOUTME: Handles ->@* (array deref) and ->%* (hash deref) on any expression returning a reference

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

class Chalk::Grammar::Chalk::Rule::PostfixDeref :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # PostfixDeref -> Expression '->' '@' '*'  # Postfix array deref
        # PostfixDeref -> Expression '->' '%' '*'  # Postfix hash deref

        # For now, pass through the expression
        # Future: Generate IR nodes for postfix dereferencing
        my $expr = $context->child(0);

        # If we have an IR builder and the expression is an IR node,
        # we could build a deref node here
        my $builder = $context->env->{ir_builder};
        if ($builder && blessed($expr) && $expr->can('id')) {
            # Get the deref type from child(2): '@' or '%'
            my $deref_type = $context->child(2);
            # TODO: Build IR node for postfix deref operation
            # For now, pass through
        }

        return $expr;
    }
}

1;
