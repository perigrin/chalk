# ABOUTME: Semantic action for ArithmeticOp - flattened arithmetic operators
# ABOUTME: Handles +, -, *, / operators with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';
use utf8;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::AddF;
use Chalk::IR::Node::SubF;
use Chalk::IR::Node::MulF;
use Chalk::IR::Node::DivF;
use Chalk::IR::Node::ToFloat;

class Chalk::Grammar::Chalk::Rule::ArithmeticOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {

# Grammar is: ArithmeticOp -> Expression WS_OPT %ARITHMETIC_OP% WS_OPT Expression
# But WS_OPT may be filtered out, so we get either 3 or 5 children
# Search for the operator dynamically instead of hardcoding indices

# PRECEDENCE CHECK: Check if this parse is valid according to precedence rules
# The Precedence semiring has validated this parse in multiply()/on_scan()
# If invalid, return undef - the add() coordination will filter out this derivation
        my $composite_elem = $context->metadata_element;
        if ( $composite_elem && $composite_elem->can('elements') ) {
            my @elements = $composite_elem->elements->@*;

            # Find the Precedence element (usually at index 0)
            for my $elem (@elements) {
                if ( $elem->can('valid') && !$elem->valid ) {

           # This parse violates precedence rules - return nothing
           # The coordinated add() in Composite will choose the valid derivation
                    return;
                }
            }
        }

        my $num_children = scalar( @{ $context->children } );
        my $operator_idx;
        my $operator;

       # Find the operator by scanning children - expression structure varies
       # because WS_OPT may or may not be present, so we can't use fixed indices
        for my $i ( 0 .. $num_children - 1 ) {
            my $child = $context->child($i);
            if ( $child isa Chalk::Grammar::Token::Operator ) {
                $operator     = "$child";    # Stringify to get operator value
                $operator_idx = $i;
                last;
            }
        }

 # If no operator found, this is a bug - we matched ArithmeticOp grammar rule
 # so there MUST be an operator. Dying here exposes bugs instead of hiding them.
        unless ( defined $operator ) {
            my @children_debug =
              map { defined $_ ? "$_" : '<undef>' } @{ $context->children };
            die
"ArithmeticOp matched but no operator found in children: [@children_debug]";
        }

        # Extract left operand (first IR node before operator)
        my $left;
        for my $i ( 0 .. $operator_idx - 1 ) {
            my $child = $context->child($i);
            if ( ref($child) && $child->can('id') ) {
                $left = $child;
                last;
            }
        }

        # Extract right operand (first IR node after operator)
        my $right;
        for my $i ( $operator_idx + 1 .. $num_children - 1 ) {
            my $child = $context->child($i);
            if ( ref($child) && $child->can('id') ) {
                $right = $child;
                last;
            }
        }

        # Validate that we got both operands - if missing, this is a bug
        unless ( $left && $right ) {
            my @children_debug =
              map { defined $_ ? "$_" : '<undef>' } @{ $context->children };
            die
"ArithmeticOp found operator '$operator' at index $operator_idx but missing operands: "
              . "left="
              . ( defined $left ? $left->id : '<undef>' ) . ", "
              . "right="
              . ( defined $right ? $right->id : '<undef>' ) . ", "
              . "children=[@children_debug]";
        }

     # Check operand types for type widening (int→float and bool→float coercion)
     # If either operand is a float, we need float arithmetic
        my $left_type  = $left->compute();
        my $right_type = $right->compute();

        my $has_float = ( $left_type->isa('Chalk::IR::Type::Float') )
          || ( $right_type->isa('Chalk::IR::Type::Float') );

        # Apply type widening if needed
        if ($has_float) {

            # Wrap integer and boolean operands in ToFloat for coercion
            # ToFloat converts: Int → Float, Bool → Float (true→1.0, false→0.0)
            if ( !$left_type->isa('Chalk::IR::Type::Float') ) {
                $left =
                  Chalk::IR::Node::ToFloat->new( operand => $left )->peephole();
            }
            if ( !$right_type->isa('Chalk::IR::Type::Float') ) {
                $right = Chalk::IR::Node::ToFloat->new( operand => $right )
                  ->peephole();
            }
        }

# Build appropriate IR node based on operator and types
# Note: Precedence validation is handled by Precedence semiring during parsing
# Each node is peepholed immediately for constant folding and algebraic simplification
        if ($has_float) {

            # Float arithmetic
            if ( $operator eq '+' ) {
                return Chalk::IR::Node::AddF->new(
                    left  => $left,
                    right => $right
                )->peephole();
            }
            elsif ( $operator eq '-' ) {
                return Chalk::IR::Node::SubF->new(
                    left  => $left,
                    right => $right
                )->peephole();
            }
            elsif ( $operator eq '*' ) {
                return Chalk::IR::Node::MulF->new(
                    left  => $left,
                    right => $right
                )->peephole();
            }
            elsif ( $operator eq '/' ) {
                return Chalk::IR::Node::DivF->new(
                    left  => $left,
                    right => $right
                )->peephole();
            }
        }
        else {
            # Integer arithmetic
            if ( $operator eq '+' ) {
                return Chalk::IR::Node::Add->new(
                    left  => $left,
                    right => $right
                )->peephole();
            }
            elsif ( $operator eq '-' ) {
                return Chalk::IR::Node::Subtract->new(
                    left  => $left,
                    right => $right
                )->peephole();
            }
            elsif ( $operator eq '*' ) {
                return Chalk::IR::Node::Multiply->new(
                    left  => $left,
                    right => $right
                )->peephole();
            }
            elsif ( $operator eq '/' ) {
                return Chalk::IR::Node::Divide->new(
                    left  => $left,
                    right => $right
                )->peephole();
            }
        }

    # If we get here, we found an operator that isn't +, -, *, / - this is a bug
        die
"ArithmeticOp found unrecognized operator '$operator' - expected one of +, -, *, /";
    }

    # Type inference for TypeInference semiring
    # Infers result type based on operator and operand types
    method infer_type( $semiring, $element ) {
        use Chalk::Semiring::TypeInference;    # For TypeInferenceElement

        # Element tree structure mirrors parse tree
        # ArithmeticOp has children built up through multiply() during parsing
        my @children = $element->children->@*;

        # ArithmeticOp -> Expression (pass-through)
        # ArithmeticOp -> Expression WS_OPT OPERATOR WS_OPT Expression
        # Need at least 3 children for binary operation
        return $element if scalar(@children) < 3;

        # Find the operator token
        my $operator;
        my $operator_idx;
        for my $i ( 0 .. $#children ) {
            my $child = $children[$i];

            # Check if this child has a token that is an arithmetic operator
            if ( defined $child->token ) {
                my $token_val = $child->token->value;
                if (
                    defined($token_val)
                    && (   $token_val eq '+'
                        || $token_val eq '-'
                        || $token_val eq '*'
                        || $token_val eq '/' )
                  )
                {
                    $operator     = $token_val;
                    $operator_idx = $i;
                    last;
                }
            }
        }

        # Not a binary operation, pass through
        return $element unless defined($operator);

        # Extract left operand type (first element before operator with type)
        my $left_type;
        for my $i ( 0 .. $operator_idx - 1 ) {
            my $elem = $children[$i];
            if ( defined $elem->type_obj ) {
                $left_type = $elem->type_obj;
                last;
            }
        }

        # Extract right operand type (first element after operator with type)
        my $right_type;
        for my $i ( $operator_idx + 1 .. $#children ) {
            my $elem = $children[$i];
            if ( defined $elem->type_obj ) {
                $right_type = $elem->type_obj;
                last;
            }
        }

        # If we can't find operand types, pass through element unchanged
        return $element unless ( defined($left_type) && defined($right_type) );

        # Apply operator-specific type inference rules
        my $result_type;

        # Get type lattice for bottom type
        my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

        # Arithmetic operations require numeric types
        # Int ⊗ Int → Int
        # Num ⊗ Num → Num
        # Str ⊗ Str → ⊥ (for *, -, /)
        # Incompatible types → ⊥

        my $left_name  = $left_type->name();
        my $right_name = $right_type->name();

        # Check for numeric types (Int, Num)
        my $left_is_numeric  = ( $left_name eq 'Int'  || $left_name eq 'Num' );
        my $right_is_numeric = ( $right_name eq 'Int' || $right_name eq 'Num' );

        if ( $left_is_numeric && $right_is_numeric ) {

            # Both numeric - result is the meet (more specific type)
            $result_type = $left_type->meet($right_type);
        }
        elsif ( $operator eq '+' ) {

            # Special case: string concatenation via + (some languages)
            # For now, treat non-numeric + as type error
            $result_type = $lattice->bottom_type();
        }
        else {
            # Non-numeric operands with -, *, / → bottom (type error)
            $result_type = $lattice->bottom_type();
        }

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $result_type,
            type_env => $element->type_env,
            children => $element->children,
            token    => $element->token
        );
    }
}

1;
