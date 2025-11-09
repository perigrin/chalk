# ABOUTME: Semantic action for ReturnStatement - builds Return IR node
# ABOUTME: Transforms return statement parse tree into Sea of Nodes IR

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ReturnStatement :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        warn "Return Statement: " . $context->rule;

       # ReturnStatement can have multiple forms:
       # ReturnStatement -> 'return'
       # ReturnStatement -> 'return' WS_OPT Expression
       # ReturnStatement -> 'return' WS_OPT '(' WS_OPT ExpressionList WS_OPT ')'

        my $builder = $context->env->{ir_builder};
        return unless $builder;

        # For simple "return expr;" form, expression is at child 2
        # For bare "return;", there's no expression value
        my $expr_node = $context->child(2);
        return unless $expr_node;

        # Build Return IR node WITHOUT control assignment
        # The control input will be '__CONTROL_PLACEHOLDER__'
        # Parent rule (Block, ConditionalStatement, etc) must wire up control
        unless ( $expr_node isa Chalk::IR::Node::Base ) {
            use DDP;
            use Carp qw(confess);
            p $expr_node;
            confess "unknown expression for return: $expr_node";
        }

        return $builder->build_return_node( $expr_node,
            '__CONTROL_PLACEHOLDER__' );
    }
}

1;
