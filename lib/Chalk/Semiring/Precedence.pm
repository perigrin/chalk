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
    field $valid :param :reader = 0;  # Boolean: 1 = valid precedence, 0 = invalid (default to add_id)
    field $operator :param :reader = undef;  # Operator symbol (if known)
    field $precedence_level :param :reader = undef;  # Index in precedence table
    field $associativity :param :reader = undef;  # Associativity type: left, right, nonassoc, chained, chain/na
    field $operator_index :param :reader = undef;  # Hash mapping operators to precedence info
    field $forest :param :reader = undef;  # Optional SPPF forest reference for disambiguation
    field $is_active :param :reader = 0;  # 1 if operator is from current rule (on_scan), 0 if from sub-expression (on_complete)
    field $errors :param :reader = [];  # Accumulated error messages (arrayref)
    field $start_pos :param :reader = 0;  # Start position for error reporting
    field $end_pos :param :reader = 0;  # End position for error reporting
    field $semiring_add_id :param :reader = undef;  # Cached add_id from parent semiring
    field $semiring_mul_id :param :reader = undef;  # Cached mul_id from parent semiring

    ADJUST {
        # Identity elements are self-referential - all others get explicit refs from parent
        $semiring_add_id //= $self;
        $semiring_mul_id //= $self;
    }

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

        # DEBUG: Log add() calls when valid/invalid differs
        if ($ENV{DEBUG_PRECEDENCE_VERBOSE} && $valid != $other->valid) {
            my $sop = $operator // 'undef';
            my $oop = $other->operator // 'undef';
            warn "PREC add: self($sop,v$valid) + other($oop,v" . $other->valid . ") => " .
                 ($valid ? "self" : "other") . " wins\n";
        }

        # If self is already invalid (add_id), return other
        return $other if !$valid;

        # If other is invalid, return self
        return $self if !$other->valid;

        # Both valid - prefer self (first alternative)
        return $self;
    }

    method multiply( $other, $swap = undef ) {
        # Handle undef or wrong type for $other - return cached add_id
        return $semiring_add_id unless defined $other;
        return $semiring_add_id unless ref($other) && $other->can('valid');

        # Helper closure to create new elements with identity references
        my $new_element = sub (%params) {
            return Chalk::Semiring::PrecedenceElement->new(
                %params,
                operator_index => $operator_index,
                semiring_add_id => $semiring_add_id,
                semiring_mul_id => $semiring_mul_id
            );
        };

        # Boolean AND for sequence: both must succeed
        # If either is invalid, return cached add_id (semiring zero) to reject this parse
        # This allows Composite to short-circuit and reject the entire derivation
        if (!$valid || !$other->valid) {
            return $semiring_add_id;
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
            return $new_element->(
                valid => 1,
                operator_index => $operator_index,
                is_active => ($is_active || ($other->is_active // 0))
            );
        } elsif (!defined($self_op)) {
            # Other has operator, self doesn't - preserve other's operator and active status
            return $new_element->(
                valid => 1,
                operator => $other_op,
                precedence_level => $other_level,
                associativity => $other_assoc,
                operator_index => $operator_index,
                is_active => ($other->is_active // 0)
            );
        } elsif (!defined($other_op)) {
            # Self has operator, other doesn't - preserve self's operator and active status
            return $new_element->(
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

        # DEBUG: Log operator combinations when DEBUG_PRECEDENCE is set
        if ($ENV{DEBUG_PRECEDENCE} && (defined($self_op) || defined($other_op))) {
            my $sa = $self_active ? '*' : '';
            my $oa = $other_active ? '*' : '';
            my $sop = $self_op // 'undef';
            my $oop = $other_op // 'undef';
            my $slv = $self_level // '?';
            my $olv = $other_level // '?';
            warn "PREC multiply: $sop$sa(L$slv) x $oop$oa(L$olv)\n";
        }

        # Determine which is the "current rule" (active) operator
        if ($self_active && !$other_active) {
            # self is the current rule's operator, other is from sub-expression
            # Valid if self (parent) has lower or equal precedence than other (child)
            # Invalid if self (parent) has higher precedence - the child should have bound first
            #
            # EXCEPTION: When =~ or !~ is the active operator and / is passive,
            # this is likely a regex match like `$x =~ m/pattern/`. The / is a regex
            # delimiter, not division, so don't enforce precedence checks.
            my $is_regex_match_context = ($self_op eq '=~' || $self_op eq '!~') && $other_op eq '/';

            if ($self_level < $other_level && !$is_regex_match_context) {
                # Parent has higher precedence than child - INVALID
                # Return cached add_id to reject this parse entirely
                if ($ENV{DEBUG_PRECEDENCE}) {
                    warn "PREC REJECT: $self_op*(L$self_level) cannot contain $other_op(L$other_level) - parent has higher precedence\n";
                }
                return $semiring_add_id;
            }
            # Parent has lower or equal precedence - VALID
            return $new_element->(
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
                # Return cached add_id to reject this parse entirely
                if ($ENV{DEBUG_PRECEDENCE}) {
                    warn "PREC REJECT: $other_op*(L$other_level) cannot contain $self_op(L$self_level) - parent has higher precedence\n";
                }
                return $semiring_add_id;
            }
            # Parent has lower or equal precedence - VALID
            return $new_element->(
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
            return $new_element->(
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
            return $new_element->(
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
            # Return cached add_id to reject this parse entirely
            if ($self_op eq $other_op) {
                if ($ENV{DEBUG_PRECEDENCE}) {
                    warn "PREC REJECT: nonassoc $self_op cannot chain with $other_op\n";
                }
                return $semiring_add_id;
            }
        }

        # Rule 4: chained comparisons must maintain directional consistency
        if (defined($self_assoc) && $self_assoc eq 'chained') {
            # Determine direction of operators
            my $self_dir = _operator_direction($self_op);
            my $other_dir = _operator_direction($other_op);

            # If both have directions, they must match
            # Return cached add_id to reject this parse entirely
            if (defined($self_dir) && defined($other_dir) && $self_dir ne $other_dir) {
                return $semiring_add_id;
            }
        }

        # Rule 5: chain/na allows chaining (like chained but context-dependent)
        if (defined($self_assoc) && $self_assoc eq 'chain/na') {
            return $new_element->(valid => 1, );
        }

        # Rule 6: left and right associativity
        # Default: valid
        return $new_element->(valid => 1, );
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

    # Helper: Determine operator direction for chained comparison validation
    sub _operator_direction($op) {
        return 'less' if $op =~ m/^(<|<=|lt|le)$/;
        return 'greater' if $op =~ m/^(>|>=|gt|ge)$/;
        return undef;
    }
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

        # Identity elements - don't pass semiring_add_id/mul_id
        # ADJUST block will make them self-referential (circular refs acceptable for 2 singletons)
        $add_id = Chalk::Semiring::PrecedenceElement->new();
        $mul_id = Chalk::Semiring::PrecedenceElement->new(valid => 1);
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
        # Return a plain valid element with identity references
        return Chalk::Semiring::PrecedenceElement->new(
            valid => 1,
            operator_index => $operator_index,
            semiring_add_id => $add_id,
            semiring_mul_id => $mul_id
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

            # DEBUG: Log scanned tokens when DEBUG_PRECEDENCE is set
            if ($ENV{DEBUG_PRECEDENCE} && $self->lookup_operator($token_str)) {
                warn "SCAN: token='$token_str' pattern='$pattern_name' found operator\n";
            }

            # Don't treat identifiers or attribute tokens as operators
            # BAREWORD, BAREWORD_ANY, and IDENTIFIER patterns are all identifier-like tokens
            # that should never be treated as operators even if they match an operator string
            # (e.g., the 'x' in variable $x should not be treated as string repetition operator)
            my $is_identifier = defined($pattern_name) &&
                ($pattern_name eq 'IDENTIFIER' || $pattern_name eq 'BAREWORD' || $pattern_name eq 'BAREWORD_ANY');
            # Attributes are : followed by word chars (not ::)
            my $is_attribute = $token_str =~ m/^:\w/ && $token_str ne '::';

            # Don't treat certain tokens as operators when matched as literal terminals
            # pattern_name tells us HOW the token was matched:
            # - 'ARITHMETIC_OP' means it matched via the operator pattern (it's truly an operator)
            # - empty/undef means it matched a literal terminal (context-dependent)
            # Filter cases:
            # - '/' as literal: regex delimiter, not division
            # - '.' as literal: part of '..', method call separator, or qw delimiter - not concat
            my $is_empty_pattern = !defined($pattern_name) || $pattern_name eq '';
            my $is_literal_terminal = $is_empty_pattern && ($token_str eq '/' || $token_str eq '.');

            if (!$is_identifier && !$is_attribute && !$is_literal_terminal) {
                my $op_info = $self->lookup_operator($token_str);

                if ($op_info) {
                    # Create element for the scanned operator (active)
                    my $new_op_element = Chalk::Semiring::PrecedenceElement->new(
                semiring_add_id => $add_id,
                semiring_mul_id => $mul_id,
                
                        valid => 1,
                        operator => $token_str,
                        precedence_level => $op_info->{level},
                        associativity => $op_info->{assoc},
                        operator_index => $operator_index,
                        is_active => 1  # Mark as active - this is the current rule's operator
                    );

                    # CRITICAL: Use multiply() to combine with existing element
                    # This ensures precedence validation happens when active operator
                    # (new) tries to combine with passive operator (existing from sub-expr)
                    # multiply() at lines 149-185 will reject invalid precedence like
                    # * (active, level 5) trying to contain + (passive, level 6)
                    return $element->multiply($new_op_element);
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

        # DEBUG: Log on_complete
        if ($ENV{DEBUG_PRECEDENCE} && $rule_name =~ /Expression|Statement|Program/) {
            my $v = $completed_element->can('valid') ? $completed_element->valid : '?';
            my $op = $completed_element->can('operator') ? ($completed_element->operator // 'undef') : '?';
            my $rhs_str = join(' ', $completed_item->rule->rhs->@*);
            my $start = $completed_item->start_pos;
            my $end = $completed_item->end_pos // '?';
            warn "PREC on_complete: $rule_name($start-$end) valid=$v op=$op rule=$rhs_str\n";
        }

        # CRITICAL: Preserve invalid state if the completed element was invalid
        # This prevents wiping out precedence validation results
        my $was_valid = $completed_element->can('valid') ? $completed_element->valid : 1;

        # BRACKETED EXPRESSIONS: Clear operator info when completing a rule
        # that starts with '(' or '[' - these "seal off" the inner precedence context.
        # This makes (1 + 2) behave as a primary value with no operator, so
        # (1 + 2) * 3 parses correctly (no precedence conflict between + and *).
        my $rhs = $completed_item->rule->rhs;
        if ($rhs && $rhs->@* > 0 && ($rhs->[0] eq '(' || $rhs->[0] eq '[')) {
            return Chalk::Semiring::PrecedenceElement->new(
                semiring_add_id => $add_id,
                semiring_mul_id => $mul_id,
                
                valid => $was_valid,
                operator_index => $operator_index
            );
        }

        # UNARY EXPRESSIONS: Also clear operator info for Unary rules.
        # Unary operators like -1 should not conflict with surrounding binary
        # operators. The '-' in '-1' is unary (high precedence) not binary.
        if ($rule_name eq 'Unary') {
            return Chalk::Semiring::PrecedenceElement->new(
                semiring_add_id => $add_id,
                semiring_mul_id => $mul_id,
                
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
                semiring_add_id => $add_id,
                semiring_mul_id => $mul_id,
                
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
                semiring_add_id => $add_id,
                semiring_mul_id => $mul_id,
                
                valid => $was_valid,
                operator => $operator,
                precedence_level => $prec_level,
                associativity => $assoc,
                operator_index => $operator_index
            );
        } else {
            return Chalk::Semiring::PrecedenceElement->new(
                semiring_add_id => $add_id,
                semiring_mul_id => $mul_id,
                
                valid => $was_valid,
                operator_index => $operator_index
            );
        }
    }
}

1;
