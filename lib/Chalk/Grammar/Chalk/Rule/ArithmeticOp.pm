# ABOUTME: Semantic action for ArithmeticOp - flattened arithmetic operators
# ABOUTME: Handles +, -, *, / operators with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ArithmeticOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # For binary operation: check child(2) for the operator
        # Grammar is: ArithmeticOp -> Expression WS_OPT %ARITHMETIC_OP% WS_OPT Expression
        # So operator is at index 2
        my $operator = $context->child(2);
        return $context->child(0) unless defined $operator && !ref($operator);
        return $context->child(0) unless $operator =~ qr/^[+\-*\/]$/;

        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get left (child 0) and right (child 4)
        my $left  = $context->child(0);
        my $right = $context->child(4);

        # Validate that we got IR nodes
        return $left unless $left isa Chalk::IR::Node::Base;
        return $left unless $right isa Chalk::IR::Node::Base;

        # Build appropriate IR node based on operator
        if ( $operator eq '+' ) {
            return $builder->build_add_node( $left, $right );
        }
        elsif ( $operator eq '-' ) {
            return $builder->build_sub_node( $left, $right );
        }
        elsif ( $operator eq '*' ) {
            return $builder->build_multiply_node( $left, $right );
        }
        elsif ( $operator eq '/' ) {
            return $builder->build_divide_node( $left, $right );
        }

        return $context->child(0);
    }
}

1;
