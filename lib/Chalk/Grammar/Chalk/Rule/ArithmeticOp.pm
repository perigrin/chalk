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
    # Infers result type based on operand types
    # Uses simplified approach: first and last typed children are operands
    method infer_type( $semiring, $element ) {
        use Chalk::Semiring::TypeInference;    # For TypeInferenceElement
        use Chalk::Grammar::Chalk::TypeLattice;

        # Element tree structure mirrors parse tree
        # ArithmeticOp has children built up through multiply() during parsing
        my @children = $element->children->@*;

        # ArithmeticOp -> Expression (pass-through with 1 child)
        # ArithmeticOp -> Expression WS_OPT OPERATOR WS_OPT Expression (binary)
        # Need at least 2 typed children for binary operation
        return $element if scalar(@children) < 2;

        # Simplified approach: find first and last children with non-top types
        # These correspond to left and right operands in binary expression
        my ($left_type, $right_type);
        my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
        my $top_name = $lattice->top_type()->name();

        # Find first non-top typed child (left operand)
        for my $child (@children) {
            next unless $child->can('type_obj') && defined($child->type_obj);
            my $type = $child->type_obj;
            next if $type->name() eq $top_name;
            $left_type = $type;
            last;
        }

        # Find last non-top typed child (right operand)
        for my $child (reverse @children) {
            next unless $child->can('type_obj') && defined($child->type_obj);
            my $type = $child->type_obj;
            next if $type->name() eq $top_name;
            $right_type = $type;
            last;
        }

        # If both left and right are the same (single operand), pass through
        # This happens in pass-through cases where there's only one typed child
        if (defined($left_type) && defined($right_type) &&
            $left_type == $right_type) {
            return $element;
        }

        # If we can't find both operand types, pass through element unchanged
        return $element unless defined($left_type) && defined($right_type);

        my $left_name = $left_type->name();
        my $right_name = $right_type->name();

        # Check for numeric types (Int, Num)
        my $left_is_numeric  = ($left_name eq 'Int' || $left_name eq 'Num');
        my $right_is_numeric = ($right_name eq 'Int' || $right_name eq 'Num');

        my @new_errors = $element->errors->@*;
        my $result_type;

        if ($left_is_numeric && $right_is_numeric) {
            # Both numeric - result is the join (widened type)
            # Int + Int -> Int, Int + Num -> Num, Num + Num -> Num
            $result_type = $left_type->join($right_type);
        } else {
            # Type error: non-numeric operands for arithmetic
            push @new_errors, {
                type => 'type_error',
                message => "Type error: Cannot apply arithmetic operator to " .
                           $left_name . " and " . $right_name .
                           " (expected numeric types)",
                start_pos => $element->start_pos,
                end_pos => $element->end_pos,
                left_type => $left_name,
                right_type => $right_name,
            };
            # Result type is bottom (type error)
            $result_type = $lattice->bottom_type();
        }

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $result_type,
            type_env => $element->type_env,
            children => $element->children,
            token    => $element->token,
            errors   => \@new_errors,
            start_pos => $element->start_pos,
            end_pos => $element->end_pos,
        );
    }
}

1;
