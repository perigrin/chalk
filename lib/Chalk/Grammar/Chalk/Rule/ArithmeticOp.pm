# ABOUTME: Semantic action for ArithmeticOp - flattened arithmetic operators
# ABOUTME: Handles +, -, *, / operators with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ArithmeticOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        use Chalk::IR::Node::Add;
        use Chalk::IR::Node::Subtract;
        use Chalk::IR::Node::Multiply;
        use Chalk::IR::Node::Divide;

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
                    # This parse violates precedence rules - this is a bug
                    die "ArithmeticOp received invalid precedence parse - precedence semiring should have filtered this";
                }
            }
        }

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

        # If no operator found, this is a bug - we matched ArithmeticOp grammar rule
        # so there MUST be an operator. Dying here exposes bugs instead of hiding them.
        unless (defined $operator) {
            my @children_debug = map { defined $_ ? "$_" : '<undef>' } @{$context->children};
            die "ArithmeticOp matched but no operator found in children: [@children_debug]";
        }

        # Extract left operand (first IR node before operator)
        my $left;
        for my $i (0 .. $operator_idx - 1) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                $left = $child;
                last;
            }
        }

        # Extract right operand (first IR node after operator)
        my $right;
        for my $i ($operator_idx + 1 .. $num_children - 1) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                $right = $child;
                last;
            }
        }

        # Validate that we got both operands - if missing, this is a bug
        unless ($left && $right) {
            my @children_debug = map { defined $_ ? "$_" : '<undef>' } @{$context->children};
            die "ArithmeticOp found operator '$operator' at index $operator_idx but missing operands: "
              . "left=" . (defined $left ? $left->id : '<undef>') . ", "
              . "right=" . (defined $right ? $right->id : '<undef>') . ", "
              . "children=[@children_debug]";
        }

        # Build appropriate IR node based on operator
        # Note: Precedence validation is handled by Precedence semiring during parsing
        if ( $operator eq '+' ) {
            return Chalk::IR::Node::Add->new( left => $left, right => $right );
        }
        elsif ( $operator eq '-' ) {
            return Chalk::IR::Node::Subtract->new( left => $left, right => $right );
        }
        elsif ( $operator eq '*' ) {
            return Chalk::IR::Node::Multiply->new( left => $left, right => $right );
        }
        elsif ( $operator eq '/' ) {
            return Chalk::IR::Node::Divide->new( left => $left, right => $right );
        }

        # If we get here, we found an operator that isn't +, -, *, / - this is a bug
        die "ArithmeticOp found unrecognized operator '$operator' - expected one of +, -, *, /";
    }
}

1;
