# ABOUTME: Semantic action for ReturnStatement - builds Return IR node
# ABOUTME: Transforms return statement parse tree into Sea of Nodes IR

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ReturnStatement :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        use Chalk::IR::Node::Return;
        use Chalk::IR::Node::Constant;

       # ReturnStatement can have multiple forms:
       # ReturnStatement -> 'return'
       # ReturnStatement -> 'return' WS_OPT Expression
       # ReturnStatement -> 'return' WS_OPT '(' WS_OPT ExpressionList WS_OPT ')'

        # For simple "return expr;" form, expression is at child 2
        # For bare "return;", there's no expression value
        my $expr_node = $context->child(2);

        # Default to undef constant if no expression
        $expr_node //= Chalk::IR::Node::Constant->new(
            type  => 'Undef',
            value => 'undef',
        );

        # Verify we have an IR node (check for id method, not Base inheritance)
        unless ( ref($expr_node) && $expr_node->can('id') ) {
            # Not an IR node - return undef for now
            return undef;
        }

        # Get scope for control flow
        my $scope = $context->env->{scope};
        my $current_control = $scope ? $scope->current_control : undef;

        # Create Return node directly (new architecture)
        my $return_node = Chalk::IR::Node::Return->new(
            control => $current_control,
            value   => $expr_node,
        );

        return $return_node;
    }
}

1;
