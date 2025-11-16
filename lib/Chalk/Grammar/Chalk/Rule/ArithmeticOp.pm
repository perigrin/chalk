# ABOUTME: Semantic action for ArithmeticOp - flattened arithmetic operators
# ABOUTME: Handles +, -, *, / operators with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ArithmeticOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # Grammar is: ArithmeticOp -> Expression WS_OPT %ARITHMETIC_OP% WS_OPT Expression
        # But WS_OPT may be filtered out, so we get either 3 or 5 children
        # Search for the operator dynamically instead of hardcoding indices

        # PRECEDENCE CHECK: Only build IR for valid precedence parses
        # The Precedence semiring has already validated this parse in multiply()
        # Check metadata_element for precedence validity before building IR
        my $composite_elem = $context->metadata_element;
        if ($composite_elem && $composite_elem->can('elements')) {
            my @elements = $composite_elem->elements->@*;
            # Find the Precedence element (usually at index 1 after SPPF)
            for my $elem (@elements) {
                if ($elem->can('valid') && !$elem->valid) {
                    # This parse violates precedence rules - don't build IR
                    return $context->child(0);
                }
            }
        }

        my $builder = $context->env->{ir_builder};

        my $num_children = scalar(@{$context->children});
        my $operator_idx;
        my $operator;

        # Find the operator by searching through children
        # Operators may be Token objects or plain strings, so stringify and check
        for my $i (0 .. $num_children - 1) {
            my $child = $context->child($i);
            if (defined $child) {
                my $str_val = "$child";  # Stringify (works for both Token objects and strings)
                if ($str_val =~ qr/^[+\-*\/]$/) {
                    $operator = $str_val;
                    $operator_idx = $i;
                    last;
                }
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
