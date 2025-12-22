# ABOUTME: Semantic action for ConcatenationOp - string concatenation operator
# ABOUTME: Handles '.' (concatenation) with precedence validated by Precedence semiring

use 5.42.0;
use utf8;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Rule::ConcatenationOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        use Chalk::IR::Node::StrConcat;

        # Grammar is: ConcatenationOp -> Expression WS_OPT '.' WS_OPT Expression
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

        my $num_children = scalar(@{$context->children});
        my $operator_idx;
        my $operator;

        # Find the operator by searching through children
        # Operators may be Token objects or plain strings, so stringify and check
        for my $i (0 .. $num_children - 1) {
            my $child = $context->child($i);
            if (defined $child) {
                my $str_val = "$child";  # Stringify (works for both Token objects and strings)
                if ($str_val eq '.') {
                    $operator = $str_val;
                    $operator_idx = $i;
                    last;
                }
            }
        }

        # If no operator found, return first child
        return $context->child(0) unless defined $operator;

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

        # Validate that we got both operands
        return $context->child(0) unless $left && $right;

        # Build string concatenation IR node
        # Note: Precedence validation is handled by Precedence semiring during parsing
        return Chalk::IR::Node::StrConcat->new( left => $left, right => $right );
    }

    # Type inference for TypeInference semiring
    # String concatenation coerces operands to strings
    # Sets string value context on operands
    method infer_type($semiring, $element) {
        use Chalk::Semiring::TypeInference;  # For TypeInferenceElement

        # Element tree structure mirrors parse tree
        my @children = $element->children->@*;

        # ConcatenationOp -> Expression (pass-through)
        # ConcatenationOp -> Expression WS_OPT '.' WS_OPT Expression
        # Need at least 3 children for binary operation
        return $element if scalar(@children) < 3;

        # Mark operand children with string value context
        # This propagates context information for downstream coercion
        my @updated_children;
        for my $child (@children) {
            if ($child->can('type_obj') && defined($child->type_obj)) {
                # Create new element with string context
                push @updated_children, Chalk::Semiring::TypeInferenceElement->new(
                    type_obj => $child->type_obj,
                    type_env => $child->type_env,
                    children => $child->children,
                    token => $child->token,
                    errors => $child->errors,
                    start_pos => $child->start_pos,
                    end_pos => $child->end_pos,
                    container_context => $child->container_context,
                    value_context => 'string'  # Set string context for concatenation
                );
            } else {
                push @updated_children, $child;
            }
        }
        @children = @updated_children;

        # Find the '.' operator token
        my $operator_idx;
        for my $i (0..$#children) {
            my $child = $children[$i];
            # Check if this child has a token that is '.'
            if (defined $child->token) {
                my $token_val = $child->token->value;
                if (defined($token_val) && $token_val eq '.') {
                    $operator_idx = $i;
                    last;
                }
            }
        }

        # Not a concatenation operation, pass through
        return $element unless defined($operator_idx);

        # Extract left operand type (first element before operator with type)
        my $left_type;
        for my $i (0 .. $operator_idx - 1) {
            my $elem = $children[$i];
            if (defined $elem->type_obj) {
                $left_type = $elem->type_obj;
                last;
            }
        }

        # Extract right operand type (first element after operator with type)
        my $right_type;
        for my $i ($operator_idx + 1 .. $#children) {
            my $elem = $children[$i];
            if (defined $elem->type_obj) {
                $right_type = $elem->type_obj;
                last;
            }
        }

        # If we can't find operand types, pass through element unchanged
        return $element unless (defined($left_type) && defined($right_type));

        # Get type lattice
        my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

        # String concatenation type rules:
        # Most types can stringify → Str
        # CodeRef, ArrayRef, HashRef typically can't be meaningfully concatenated → ⊥

        my $left_name = $left_type->name();
        my $right_name = $right_type->name();

        # Check for reference types that can't be meaningfully concatenated
        my $left_is_ref = any { $left_name eq $_ } qw(CodeRef ArrayRef HashRef);
        my $right_is_ref = any { $right_name eq $_ } qw(CodeRef ArrayRef HashRef);

        my $result_type;
        if ($left_is_ref || $right_is_ref) {
            # Reference types can't be meaningfully concatenated
            $result_type = $lattice->bottom_type();
        } else {
            # Most types can be coerced to strings
            $result_type = $lattice->type_from_name('Str');
        }

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $result_type,
            type_env => $element->type_env,
            children => \@children,  # Use updated children with string context
            token => $element->token,
            errors => $element->errors,
            start_pos => $element->start_pos,
            end_pos => $element->end_pos,
            container_context => $element->container_context,
            value_context => $element->value_context
        );
    }
}

1;
