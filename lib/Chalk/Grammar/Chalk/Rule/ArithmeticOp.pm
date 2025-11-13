# ABOUTME: Semantic action for ArithmeticOp - flattened arithmetic operators
# ABOUTME: Handles +, -, *, / operators with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ArithmeticOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # Grammar is: ArithmeticOp -> Expression WS_OPT %ARITHMETIC_OP% WS_OPT Expression
        # But WS_OPT may be filtered out, so we get either 3 or 5 children
        # Search for the operator dynamically instead of hardcoding indices

        my $builder = $context->env->{ir_builder};

        my $num_children = scalar(@{$context->children});
        my $operator_idx;
        my $operator;

        # Find the operator by searching through children
        for my $i (0 .. $num_children - 1) {
            my $child = $context->child($i);
            if (defined $child && !ref($child) && $child =~ qr/^[+\-*\/]$/) {
                $operator = $child;
                $operator_idx = $i;
                last;
            }
        }

        # If no operator found, return first child
        return $context->child(0) unless defined $operator;
        return $context->child(0) unless $builder;

        # Extract left operand (first IR node before operator)
        my $left;
        for my $i (0 .. $operator_idx - 1) {
            my $child = $context->child($i);
            if ($child && $child isa Chalk::IR::Node::Base) {
                $left = $child;
                last;
            }
        }

        # Extract right operand (first IR node after operator)
        my $right;
        for my $i ($operator_idx + 1 .. $num_children - 1) {
            my $child = $context->child($i);
            if ($child && $child isa Chalk::IR::Node::Base) {
                $right = $child;
                last;
            }
        }

        # Validate that we got both operands
        return $context->child(0) unless $left && $right;

        # Build appropriate IR node based on operator
        # Note: Precedence validation is handled by Precedence semiring during parsing
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
