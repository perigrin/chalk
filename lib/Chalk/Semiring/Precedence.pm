# ABOUTME: Precedence semiring for operator precedence validation during parsing
# ABOUTME: Validates operator precedence through semiring operations without SPPF dependency
#
# ACTIVE/PASSIVE MODEL:
# The semiring tracks whether each operator is "active" or "passive" to distinguish
# between operators from the current parse rule vs operators from completed sub-expressions.
#
# - ACTIVE operators: Created by on_scan() when scanning an operator token. These represent
#   the operator of the CURRENT rule being parsed (the "parent" in the parse tree).
#
# - PASSIVE operators: Created by on_complete() when a sub-expression finishes. These
#   represent operators from completed child expressions.
#
# PRECEDENCE VALIDATION:
# When combining operators via multiply(), the model enforces that a parent operator
# can only contain child operators of EQUAL OR HIGHER precedence. This prevents
# incorrect groupings like (1+2)*3 when * should bind tighter than +.
#
# Example for "1 + 2 * 3":
#   - Correct parse: 1 + (2*3) - The + is active (parent), * is passive (child from sub-expr)
#     Since + has lower precedence than *, this is VALID (lower-prec parent, higher-prec child)
#   - Wrong parse: (1+2) * 3 - The * is active (parent), + is passive (child from sub-expr)
#     Since * has higher precedence than +, this is INVALID (higher-prec parent can't contain
#     lower-prec child - the + should have been inside the * expression)
#
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::PrecedenceElement :isa(Chalk::Element) {
    field $valid :param :reader;  # Boolean: 1 = valid precedence, 0 = invalid
    field $operator :param :reader = undef;  # Operator symbol (if known)
    field $precedence_level :param :reader = undef;  # Index in precedence table
    field $associativity :param :reader = undef;  # Associativity type: left, right, nonassoc, chained, chain/na
    field $operator_index :param :reader = undef;  # Hash mapping operators to precedence info
    field $forest :param :reader = undef;  # Optional SPPF forest reference for disambiguation
    field $is_active :param :reader = 0;  # 1 if operator is from current rule (on_scan), 0 if from sub-expression (on_complete)

    # Lookup operator precedence and associativity from operator_index
    method lookup_operator($op) {
        return unless $operator_index;
        return $operator_index->{$op};
    }

    method add( $other, $swap = undef ) {
        # Choose between alternative parses based on precedence validation
        # Return the one with valid precedence, or add_id if neither is valid
        #
        # CONTRACT: This method returns $self or $other directly (not copies).
        # Composite::add() relies on reference equality to determine which
        # derivation won, ensuring all semirings use the same derivation.

        # Handle undef or wrong type for $other
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # If self is already invalid (add_id), return other
        return $other if !$valid;

        # If other is invalid, return self
        return $self if !$other->valid;

        # Both valid - prefer self (first alternative)
        return $self;
    }

    method multiply( $other, $swap = undef ) {
        # Handle undef or wrong type for $other
        return Chalk::Semiring::PrecedenceElement->new(valid => 0, operator_index => $operator_index) unless defined $other;
        return Chalk::Semiring::PrecedenceElement->new(valid => 0, operator_index => $operator_index) unless ref($other) && $other->can('valid');

        # Boolean AND for sequence: both must succeed
        # If either is invalid, result is invalid
        # IMPORTANT: Preserve operator info so invalid elements don't equal add_id
        # This prevents premature Composite short-circuit and allows add() to choose correctly
        if (!$valid || !$other->valid) {
            my $op = $operator // ($other->can('operator') ? $other->operator : undef);
            my $level = $precedence_level // ($other->can('precedence_level') ? $other->precedence_level : undef);
            my $assoc = $associativity // ($other->can('associativity') ? $other->associativity : undef);
            my $active = $is_active || ($other->can('is_active') ? $other->is_active : 0);

            return Chalk::Semiring::PrecedenceElement->new(
                valid => 0,
                operator => $op,
                precedence_level => $level,
                associativity => $assoc,
                operator_index => $operator_index,
                is_active => $active
            );
        }

        # Precedence validation: check if $other (right operand) has valid precedence
        # relative to $self (left context/current operator)

        my $self_op = $operator;
        my $self_level = $precedence_level;
        my $self_assoc = $associativity;

        my $other_op = $other->operator;
        my $other_level = $other->precedence_level;
        my $other_assoc = $other->associativity;

        # If either element has no operator info, preserve the one that does
        if (!defined($self_op) && !defined($other_op)) {
            # Neither has operator - return plain valid element, preserving any active status
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator_index => $operator_index,
                is_active => ($is_active || ($other->is_active // 0))
            );
        } elsif (!defined($self_op)) {
            # Other has operator, self doesn't - preserve other's operator and active status
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $other_op,
                precedence_level => $other_level,
                associativity => $other_assoc,
                operator_index => $operator_index,
                is_active => ($other->is_active // 0)
            );
        } elsif (!defined($other_op)) {
            # Self has operator, other doesn't - preserve self's operator and active status
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $self_op,
                precedence_level => $self_level,
                associativity => $self_assoc,
                operator_index => $operator_index,
                is_active => $is_active
            );
        }

        # Both have operators - validate based on precedence, associativity, and active/passive status
        # "Active" = operator from on_scan (current rule's operator)
        # "Passive" = operator from on_complete (sub-expression's operator)
        #
        # Key insight: The ACTIVE operator is the current rule's operator (parent).
        # The PASSIVE operator came from a completed sub-expression (child).
        # A parent can contain children of equal or higher precedence, but NOT lower precedence.

        my $self_active = $is_active;
        my $other_active = $other->is_active;

        # Determine which is the "current rule" (active) operator
        if ($self_active && !$other_active) {
            # self is the current rule's operator, other is from sub-expression
            # Valid if self (parent) has lower or equal precedence than other (child)
            # Invalid if self (parent) has higher precedence - the child should have bound first
            if ($self_level < $other_level) {
                # Parent has higher precedence than child - INVALID
                # Example: `*` trying to contain `+` result
                return Chalk::Semiring::PrecedenceElement->new(valid => 0, operator_index => $operator_index);
            }
            # Parent has lower or equal precedence - VALID
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $self_op,
                precedence_level => $self_level,
                associativity => $self_assoc,
                operator_index => $operator_index,
                is_active => 1
            );
        } elsif (!$self_active && $other_active) {
            # other is the current rule's operator, self is from sub-expression
            # Valid if other (parent) has lower or equal precedence than self (child)
            # Invalid if other (parent) has higher precedence - the child should have bound first
            if ($other_level < $self_level) {
                # Parent has higher precedence than child - INVALID
                # Example: `*` trying to contain `+` result
                return Chalk::Semiring::PrecedenceElement->new(valid => 0, operator_index => $operator_index);
            }
            # Parent has lower or equal precedence - VALID
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $other_op,
                precedence_level => $other_level,
                associativity => $other_assoc,
                operator_index => $operator_index,
                is_active => 1
            );
        }

        # Both active or both passive - use traditional precedence rules
        # Rule 1: Higher precedence (lower level) on LEFT with lower precedence (higher level) on RIGHT
        if ($self_level < $other_level) {
            # self has higher precedence (lower level), other has lower precedence (higher level)
            # Preserve the higher precedence operator
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $self_op,
                precedence_level => $self_level,
                associativity => $self_assoc,
                operator_index => $operator_index,
                is_active => $self_active || $other_active
            );
        }

        # Rule 2: Lower precedence (higher level) on LEFT with higher precedence (lower level) on RIGHT
        if ($self_level > $other_level) {
            # self has lower precedence (higher level), other has higher precedence (lower level)
            # Preserve the higher precedence operator
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $other_op,
                precedence_level => $other_level,
                associativity => $other_assoc,
                operator_index => $operator_index,
                is_active => $self_active || $other_active
            );
        }

        # Same precedence level - check associativity rules
        # Rule 3: nonassoc operators cannot chain with themselves
        if (defined($self_assoc) && $self_assoc eq 'nonassoc') {
            # nonassoc operators at same level cannot chain
            if ($self_op eq $other_op) {
                return Chalk::Semiring::PrecedenceElement->new(valid => 0, operator_index => $operator_index);
            }
        }

        # Rule 4: chained comparisons must maintain directional consistency
        if (defined($self_assoc) && $self_assoc eq 'chained') {
            # Determine direction of operators
            my $self_dir = _operator_direction($self_op);
            my $other_dir = _operator_direction($other_op);

            # If both have directions, they must match
            if (defined($self_dir) && defined($other_dir) && $self_dir ne $other_dir) {
                return Chalk::Semiring::PrecedenceElement->new(valid => 0, operator_index => $operator_index);
            }
        }

        # Rule 5: chain/na allows chaining (like chained but context-dependent)
        if (defined($self_assoc) && $self_assoc eq 'chain/na') {
            return Chalk::Semiring::PrecedenceElement->new(valid => 1, operator_index => $operator_index);
        }

        # Rule 6: left and right associativity
        # Default: valid
        return Chalk::Semiring::PrecedenceElement->new(valid => 1, operator_index => $operator_index);
    }

    method to_string(@args) {
        if ($operator) {
            my $active_marker = $is_active ? '*' : '';  # * marks active (scanned) operators
            return "Prec($operator$active_marker:$precedence_level)";
        } else {
            return $valid ? "valid" : "invalid";
        }
    }

    method score() {
        return $valid ? 1 : 0;
    }

    method equals($other, $swap = undef) {
        return 0 unless ref($other) eq ref($self);
        return 0 unless $valid == $other->valid;
        return 0 unless ($operator // '') eq ($other->operator // '');
        return 0 unless ($precedence_level // 0) == ($other->precedence_level // 0);
        return 0 unless ($associativity // '') eq ($other->associativity // '');
        return 0 unless ($is_active // 0) == ($other->is_active // 0);
        return 1;
    }
}

# Helper: Determine operator direction for chained comparison validation
sub _operator_direction($op) {
    return 'less' if $op =~ m/^(<|<=|lt|le)$/;
    return 'greater' if $op =~ m/^(>|>=|gt|ge)$/;
    return undef;
}

class Chalk::Semiring::Precedence :isa(Chalk::Semiring) {
    field $precedence_table :param :reader = [];  # Array of { assoc => ..., ops => [...] }
    field $shared_context :param :reader = undef;  # Optional context for SPPF forest sharing
    field $operator_index :reader;  # Hash mapping operator -> { level, assoc }
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        # Build operator index for fast lookup
        my %index;
        for my $i (0 .. $precedence_table->@* - 1) {
            my $entry = $precedence_table->[$i];
            for my $op ($entry->{ops}->@*) {
                $index{$op} = {
                    level => $i,
                    assoc => $entry->{assoc}
                };
            }
        }
        $operator_index = \%index;

        # Identity elements
        $add_id = Chalk::Semiring::PrecedenceElement->new(
            valid => 0,
            operator_index => $operator_index
        );

        $mul_id = Chalk::Semiring::PrecedenceElement->new(
            valid => 1,
            operator_index => $operator_index
        );
    }

    method zero() {
        return $add_id;
    }

    method one() {
        return $mul_id;
    }

    method lookup_operator($op) {
        return $operator_index->{$op};
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # Return a plain valid element
        return Chalk::Semiring::PrecedenceElement->new(
            valid => 1,
            operator_index => $operator_index
        );
    }

    method multiply($x, $y) {
        return $x->multiply($y);
    }

    method plus($x, $y) {
        return $x->add($y);
    }

    # Called when a token is scanned - mark operators and create precedence element
    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # Check if the token's value is an operator in our precedence table
        if (defined($matched_value)) {
            my $token_str = "$matched_value";

            # Don't treat identifiers or attribute tokens as operators
            my $is_identifier = defined($pattern_name) && $pattern_name eq 'IDENTIFIER';
            # Attributes are : followed by word chars (not ::)
            my $is_attribute = $token_str =~ m/^:\w/ && $token_str ne '::';

            if (!$is_identifier && !$is_attribute) {
                my $op_info = $self->lookup_operator($token_str);

                if ($op_info) {
                    # Check if the existing element has a passive operator from a sub-expression
                    # If so, validate that this active operator can legally contain it
                    my $existing_op = $element->operator;
                    my $existing_level = $element->precedence_level;

                    if (defined($existing_op) && !$element->is_active) {
                        # Existing element has a passive operator (from completed sub-expression)
                        # Active operator (new) is the current rule's operator (parent)
                        # Passive operator (existing) is from child expression
                        #
                        # Valid: parent has lower or equal precedence than child
                        # Invalid: parent has higher precedence than child (child should have bound first)
                        #
                        # Lower precedence = higher level number
                        # Higher precedence = lower level number
                        my $new_level = $op_info->{level};

                        if ($new_level > $existing_level) {
                            # New operator has lower precedence (higher level) than existing
                            # This is INVALID: e.g., + trying to contain * result
                            # The * should have been inside the + expression, not the other way around
                            # Mark as invalid but PRESERVE operator info for debugging
                            return Chalk::Semiring::PrecedenceElement->new(
                                valid => 0,
                                operator => $token_str,
                                precedence_level => $op_info->{level},
                                associativity => $op_info->{assoc},
                                operator_index => $operator_index,
                                is_active => 1
                            );
                        }
                    }

                    return Chalk::Semiring::PrecedenceElement->new(
                        valid => 1,
                        operator => $token_str,
                        precedence_level => $op_info->{level},
                        associativity => $op_info->{assoc},
                        operator_index => $operator_index,
                        is_active => 1  # Mark as active - this is the current rule's operator
                    );
                }
            }
        }

        # Otherwise return element unchanged
        return $element;
    }

    # Called when a rule completes
    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        # Get the rule name to check if we should clear operator context
        my $rule_name = $completed_item->rule->lhs // '';

        # CRITICAL: Preserve invalid state if the completed element was invalid
        # This prevents wiping out precedence validation results
        my $was_valid = $completed_element->can('valid') ? $completed_element->valid : 1;

        # PARENTHESIZED EXPRESSIONS: Clear operator info when completing a rule
        # that starts with '(' - parentheses "seal off" the inner precedence context.
        # This makes (1 + 2) behave as a primary value with no operator, so
        # (1 + 2) * 3 parses correctly (no precedence conflict between + and *).
        my $rhs = $completed_item->rule->rhs;
        if ($rhs && $rhs->@* > 0 && $rhs->[0] eq '(') {
            return Chalk::Semiring::PrecedenceElement->new(
                valid => $was_valid,
                operator_index => $operator_index
            );
        }

        # Preserve operator info for Expression and operator-producing rules
        # Clear it elsewhere to prevent comparing unrelated operators
        my @expression_rules = qw(
            Expression BinaryExpression ArithmeticExpression
            ComparisonExpression LogicalExpression
            ArithmeticOp ComparisonOp LogicalOp
            ConcatenationOp RangeOp
            Unary Postfix
        );

        my $is_expression = grep { $rule_name eq $_ } @expression_rules;

        # If not an expression rule, clear operator info (but preserve validity)
        if (!$is_expression) {
            return Chalk::Semiring::PrecedenceElement->new(
                valid => $was_valid,
                operator_index => $operator_index
            );
        }

        # Extract operator from completed element if present
        my $operator = undef;
        my $prec_level = undef;
        my $assoc = undef;

        if ($completed_element->can('operator') && defined($completed_element->operator)) {
            $operator = $completed_element->operator;
            $prec_level = $completed_element->precedence_level;
            $assoc = $completed_element->associativity;
        }

        # Create result element with operator information
        # IMPORTANT: Preserve validity state - don't always return valid => 1
        if (defined($operator)) {
            return Chalk::Semiring::PrecedenceElement->new(
                valid => $was_valid,
                operator => $operator,
                precedence_level => $prec_level,
                associativity => $assoc,
                operator_index => $operator_index
            );
        } else {
            return Chalk::Semiring::PrecedenceElement->new(
                valid => $was_valid,
                operator_index => $operator_index
            );
        }
    }
}

1;
