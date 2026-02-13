# ABOUTME: Precedence semiring for operator-level disambiguation in Earley parsing.
# ABOUTME: Rejects invalid operator nesting via is_zero, so bad parses die in the chart.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::Precedence {
    # Callback: op_string => { level => N, assoc => str } or undef
    field $lookup :param;

    # Expression-type precedence levels (relative to binary operators).
    # PostfixExpression is highest, AssignmentExpression is lowest.
    # These are conceptual levels above/below the binary operator table.
    my $EXPR_LEVELS = {
        PostfixExpression    => -2,  # higher than any binary op
        UnaryExpression      => -1,  # higher than any binary op
        # BinaryExpression uses the operator's level from PrecedenceTable
        TernaryExpression    => 100, # lower than any binary op
        AssignmentExpression => 101, # lowest
    };

    # Rules that reset precedence context (parenthesized expressions)
    my %RESETS = map { $_ => true } qw(ParenExpr ArrayConstructor HashConstructor);

    method zero() {
        return { valid => false };
    }

    method one() {
        return { valid => true };
    }

    method is_zero($value) {
        return !$value->{valid};
    }

    method multiply($left, $right) {
        # Propagate zero
        return $self->zero() if $self->is_zero($left);
        return $self->zero() if $self->is_zero($right);

        # If neither has operator info, no precedence constraint
        return { valid => true }
            if !defined($left->{level}) && !defined($right->{level});

        # Operator check: when a BinaryOp/AssignOp completion (is_operator)
        # multiplies into a BinaryExpression context carrying a left-operand
        # level, validate that the left operand's precedence is high enough
        # for this operator. E.g. ($a && $b) =~ /x/ is invalid because
        # && (level=10) has lower precedence than =~ (level=1).
        if ($right->{is_operator} && defined $left->{level}) {
            my $op_level = $right->{level};
            my $left_level = $left->{level};
            if ($left_level > $op_level) {
                if ($ENV{DEBUG_PRECEDENCE}) {
                    warn "  PREC_REJECT_MUL: left_level=$left_level > op_level=$op_level ($right->{op})\n";
                }
                return $self->zero();
            }
            # Same level: check associativity direction.
            # Right-associative operators reject same-level left operands:
            # `($a ** $b) ** $c` is invalid — must be `$a ** ($b ** $c)`.
            my $op_assoc = $right->{assoc} // 'left';
            if ($left_level == $op_level && $op_assoc eq 'right') {
                if ($ENV{DEBUG_PRECEDENCE}) {
                    warn "  PREC_REJECT_RASSOC: left_level=$left_level == op_level=$op_level ($right->{op})\n";
                }
                return $self->zero();
            }
            # Left operand is compatible. Adopt operator's level as context
            # for the right operand.
            return {
                valid => true,
                op    => $right->{op},
                level => $op_level,
                assoc => $right->{assoc},
            };
        }

        # If only one has operator info, carry it through
        # (strip is_operator to prevent leaking into BinaryExpression context)
        if (!defined($left->{level})) {
            return { valid => true, op => $right->{op}, level => $right->{level}, assoc => $right->{assoc} };
        }
        # Note: is_operator from $right is intentionally NOT propagated above
        if (!defined($right->{level})) {
            return { valid => true, op => $left->{op}, level => $left->{level}, assoc => $left->{assoc} };
        }

        # Both have operator info — validate precedence nesting
        # The left value is the "parent" context, right is the "child" being added
        my $parent_level = $left->{level};
        my $child_level = $right->{level};
        my $parent_assoc = $left->{assoc} // 'left';

        # Negative levels are conceptual expression-type levels
        # (PostfixExpression=-2, UnaryExpression=-1), not binary operator
        # levels. Skip precedence nesting checks for negative-level pairs —
        # they carry no operator semantics.
        if ($parent_level < 0 && $child_level < 0) {
            return { valid => true, op => $left->{op}, level => $parent_level, assoc => $parent_assoc };
        }

        # Child with higher precedence (lower level number) inside parent is always valid
        if ($child_level < $parent_level) {
            # Child binds tighter — valid. Carry parent's operator info.
            return { valid => true, op => $left->{op}, level => $parent_level, assoc => $parent_assoc };
        }

        # Child with lower precedence (higher level number) inside parent is invalid
        if ($child_level > $parent_level) {
            return $self->zero();
        }

        # Same level: depends on associativity
        if ($parent_assoc eq 'nonassoc') {
            # Non-associative: cannot nest at same level
            return $self->zero();
        }

        # Left-associative: the right operand cannot have the same level.
        # `$a // $b // $c` must group as `($a // $b) // $c` (left-assoc),
        # so `$b // $c` as a BinaryExpression (level=11) is invalid as the
        # right operand of the first `//` (also level=11).
        # The is_operator flag distinguishes an operator context (where $right
        # is a BinaryOp completion carrying is_operator) from a right-operand
        # context (where $right is an Expression completion without is_operator).
        if ($parent_assoc eq 'left' && !$right->{is_operator}) {
            return $self->zero();
        }

        # Right-associative: the left operand cannot have the same level.
        # `$a ** $b ** $c` must group as `$a ** ($b ** $c)` (right-assoc),
        # so `$a ** $b` as a BinaryExpression (level=0) is invalid as the
        # left operand of the second `**` (also level=0).
        # The is_operator flag on $right means we're in an operator context
        # (BinaryOp multiplying into accumulated left), where same-level
        # left operand should be rejected for right-associative operators.
        if ($parent_assoc eq 'right' && $right->{is_operator}) {
            return $self->zero();
        }

        # Chained/other: same level is allowed
        return { valid => true, op => $left->{op}, level => $parent_level, assoc => $parent_assoc };
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if $self->is_zero($left);
        return $left if $self->is_zero($right);

        # Both valid: prefer the value with level info (more constraining).
        # When both have levels, prefer the higher level number (lower
        # precedence = more constraining parent context). This ensures
        # the on_scan left-operand check has the tightest possible
        # constraint, preventing invalid parses like ($a && $b) =~ /x/.
        my $ll = $left->{level};
        my $rl = $right->{level};
        if ($ENV{DEBUG_PRECEDENCE}) {
            my $lls = $ll // 'undef';
            my $rls = $rl // 'undef';
            my $lo = $left->{op} // 'undef';
            my $ro = $right->{op} // 'undef';
            warn "  PREC_ADD: left(level=$lls,op=$lo) right(level=$rls,op=$ro)\n"
                if $lls ne 'undef' || $rls ne 'undef';
        }
        if (defined $ll && !defined $rl) {
            return $left;
        }
        if (defined $rl && !defined $ll) {
            return $right;
        }
        if (defined $ll && defined $rl) {
            # When a PostfixExpression (level<0) merges with an
            # AssignmentExpression (level>=100), prefer the PostfixExpression
            # level. The assignment level would otherwise kill valid
            # method-call/subscript parse paths downstream (PostfixExpression
            # on_complete rejects values with level>=0).
            if ($ll < 0 && $rl >= 100) {
                return $left;
            }
            if ($rl < 0 && $ll >= 100) {
                return $right;
            }
            if ($rl > $ll) {
                return $right;
            }
        }

        return $left;
    }

    # Signal to Composite which alternative to select for ALL components.
    # Returns 'left', 'right', or undef (no preference).
    # Mirrors add() logic: prefer the value with a defined level (more
    # constraining), and when both have levels, prefer the higher level
    # number (lower precedence = more constraining context).
    method selects_alternative($left, $right) {
        return undef if $self->is_zero($left);
        return undef if $self->is_zero($right);

        my $ll = $left->{level};
        my $rl = $right->{level};

        # One has level info, the other doesn't
        if (defined $ll && !defined $rl) {
            return 'left';
        }
        if (defined $rl && !defined $ll) {
            return 'right';
        }

        # Both have levels: prefer higher level number, except when
        # PostfixExpression (level<0) merges with AssignmentExpression
        # (level>=100) — prefer PostfixExpression to preserve method-call
        # parse paths.
        if (defined $ll && defined $rl) {
            if ($ll < 0 && $rl >= 100) {
                return 'left';
            }
            if ($rl < 0 && $ll >= 100) {
                return 'right';
            }
            if ($rl > $ll) {
                return 'right';
            }
            if ($ll > $rl) {
                return 'left';
            }
        }

        return undef;
    }

    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my $existing = $item->{value};

        # Propagate zero
        return $self->zero() if $self->is_zero($existing);

        my $rule_name = $item->{rule}->name();

        # In BinaryOp or AssignOp context, look up operator and validate
        # the LEFT operand's precedence (accumulated in $existing).
        if ($rule_name eq 'BinaryOp' || $rule_name eq 'AssignOp') {
            my $op_info = $lookup->($matched_text);
            if (defined $op_info) {
                my $op_level = $op_info->{level};

                # Validate: the left operand (in $existing) must have higher
                # or equal precedence (lower or equal level number) than the
                # operator. Otherwise, the left operand has lower precedence
                # and can't be a direct child of this operator.
                if (defined $existing->{level} && $existing->{level} > $op_level) {
                    if ($ENV{DEBUG_PRECEDENCE}) {
                        warn "  PREC_REJECT: left_level=$existing->{level} > op_level=$op_level ($matched_text)\n";
                    }
                    return $self->zero();
                }
                if ($ENV{DEBUG_PRECEDENCE}) {
                    my $el = $existing->{level} // 'undef';
                    warn "  PREC_SCAN: left_level=$el op=$matched_text op_level=$op_level\n";
                }

                # Replace accumulated level with operator's level.
                # Mark as is_operator so multiply can validate the left
                # operand's precedence when this BinaryOp completes back
                # into the parent BinaryExpression context.
                return {
                    valid       => true,
                    op          => $matched_text,
                    level       => $op_level,
                    assoc       => $op_info->{assoc},
                    is_operator => true,
                };
            }
            # Unknown operator in BinaryOp — treat as valid, no level info
            # (AssignOp operators are not in the binary precedence table)
        }

        # Non-operator scan: multiply with one (transparent)
        return $self->multiply($existing, $self->one());
    }

    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return $self->zero() if $self->is_zero($value);

        my $rule_name = $item->{rule}->name();

        # Parenthesized expressions reset precedence context
        if ($RESETS{$rule_name}) {
            return { valid => true };
        }

        # Expression-type rules get their conceptual precedence level.
        # PostfixExpression rejects targets that carry a BinaryExpression
        # level (level >= 0): an unparenthesized BinaryExpression cannot
        # be a postfix target. This kills `($a && $b)->foo()` where
        # `$a && $b` has level=10, while allowing `$x->foo()` (no level)
        # and `($a + $b)->foo()` via parenthesized ParenExpr (resets level).
        if (defined $EXPR_LEVELS->{$rule_name}) {
            my $expr_level = $EXPR_LEVELS->{$rule_name};
            if ($expr_level < 0 && defined $value->{level} && $value->{level} >= 0) {
                return $self->zero();
            }
            return {
                valid => true,
                op    => undef,
                level => $expr_level,
                assoc => undef,
            };
        }

        # BinaryOp completion: the value already carries operator info from on_scan.
        # Mark it so multiply can use it.
        if ($rule_name eq 'BinaryOp') {
            return $value;
        }

        # BinaryExpression completion: carries the operator's level
        if ($rule_name eq 'BinaryExpression') {
            return $value;
        }

        # AssignmentExpression: low precedence
        if ($rule_name eq 'AssignmentExpression') {
            return {
                valid => true,
                op    => $value->{op},
                level => $EXPR_LEVELS->{AssignmentExpression},
                assoc => 'right',
            };
        }

        # Expression: pass through precedence info from child so that
        # a BinaryExpression's operator level survives the Expression
        # wrapper and can be checked by an outer BinaryExpression.
        if ($rule_name eq 'Expression') {
            return $value;
        }

        # MethodCall/Subscript: pass through precedence info so
        # PostfixExpression's on_complete can reject invalid targets.
        if ($rule_name eq 'MethodCall'
            || $rule_name eq 'Subscript'
            || $rule_name eq 'CallExpression'
            || $rule_name eq 'PostfixDeref'
            || $rule_name eq 'PostfixIncDec') {
            return $value;
        }

        # Other rules: pass through value, clear operator info
        return { valid => true };
    }

}
