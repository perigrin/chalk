# ABOUTME: Semantic action for ReturnStatement - builds Return IR node
# ABOUTME: Transforms return statement parse tree into Sea of Nodes IR

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ReturnStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ReturnStatement can have multiple forms:
        # ReturnStatement -> 'return'
        # ReturnStatement -> 'return' WS_OPT Expression
        # ReturnStatement -> 'return' WS_OPT '(' WS_OPT ExpressionList WS_OPT ')'

        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        # For simple "return expr;" form, expression is at child 2
        # For bare "return;", there's no expression value
        my $expr_node = $context->child(2);

        # Build Return IR node
        # If no expression, we might need to return undef/void
        # For now, require an expression
        return undef unless $expr_node;

        return $builder->build_return_node($expr_node);
    }
}

1;
