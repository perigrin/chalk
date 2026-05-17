# ABOUTME: Precedence semiring for operator-level disambiguation in Earley parsing.
# ABOUTME: Rejects invalid operator nesting via is_zero, so bad parses die in the chart.
use 5.42.0;
use utf8;
use experimental 'class';
use Chalk::Grammar::Perl::PrecedenceTable ();

class Chalk::Bootstrap::Semiring::Precedence {
    # Callback: op_string => { level => N, assoc => str } or undef
    field $lookup :param;

    # Hash-cons cache: canonical objects keyed by (valid, level, assoc, is_operator).
    # The `op` field is excluded from the key: it carries debug text only and does
    # not affect the identity of a Precedence value for disambiguation purposes.
    my %_cache;

    # Wrapper for the $lookup coderef. Calling $lookup->($text) directly
    # in XS drops arguments (field coderef call bug). This method calls
    # the package sub directly, which the XS codegen compiles as call_pv.
    method _do_lookup($text) {
        return Chalk::Grammar::Perl::PrecedenceTable::lookup($text);
    }

    # Return (or create and cache) the canonical object for the given 4-tuple.
    # The key scheme is:
    #   "0"          for valid=false (zero)
    #   "1:::"       for valid=true, no level/assoc/is_operator (one)
    #   "1:N:A:1"    for valid=true, level=N, assoc=A, is_operator=true
    #   "1:N:A:"     for valid=true, level=N, assoc=A, is_operator=false
    sub _intern($valid, $level, $assoc, $is_operator, $op = undef) {
        my $key;
        if (!$valid) {
            $key = '0';
        } else {
            my $l  = $level       // '';
            my $a  = $assoc       // '';
            my $io = $is_operator ? '1' : '';
            $key = "1:$l:$a:$io";
        }
        unless (exists $_cache{$key}) {
            $_cache{$key} = {
                valid       => $valid  ? true : false,
                level       => $level,
                assoc       => $assoc,
                is_operator => $is_operator ? true : false,
                op          => $op,
            };
        }
        return $_cache{$key};
    }

    # Clear hash-cons cache between parses to prevent unbounded growth.
    method reset_cache() {
        %_cache = ();
    }

    # Expression-type precedence levels and associativity (relative to binary operators).
    # PostfixExpression is highest, AssignmentExpression is lowest.
    # These are conceptual levels above/below the binary operator table.
    # Format: rule_name => [level, assoc]
    # Negative levels never hit the same-level reject path; assoc=undef is fine for them.
    my $EXPR_LEVELS = {
        PostfixExpression    => [-2,  undef  ],  # higher than any binary op
        UnaryExpression      => [-1,  undef  ],  # higher than any binary op
        # BinaryExpression uses the operator's level from PrecedenceTable
        TernaryExpression    => [100, 'right'],   # lower than any binary op; ?: is right-assoc
        AssignmentExpression => [101, 'right'],   # lowest; = and compound ops are right-assoc
    };

    # Rules that reset precedence context (parenthesized expressions)
    my $RESETS = {ParenExpr => true, ArrayConstructor => true, HashConstructor => true};

    method zero() {
        return _intern(false, undef, undef, false);
    }

    method one() {
        return _intern(true, undef, undef, false);
    }

    method is_zero($value) {
        my $valid = $value->{valid};
        return !$valid;
    }

    # _slot_val: extract the precedence hashref from an argument.
    # Accepts either a raw precedence hashref or a full Context object.
    # Falls back to one() when no precedence annotation is present.
    method _slot_val($val) {
        return $self->one() unless defined $val;
        # Context object: read from annotations->{precedence}
        if (blessed($val) && $val->can('annotations')) {
            return $val->annotations()->{precedence} // $self->one();
        }
        return $val;
    }

    method multiply($left, $right) {
        # Extract slot values from full Context objects if needed
        my $l_prec = $self->_slot_val($left);
        my $r_prec = $self->_slot_val($right);

        # Propagate zero
        return $self->zero() if $self->is_zero($l_prec);

        # Scan event: right Context has annotations->{scan} = true.
        # Apply operator-validation logic inline.
        if (blessed($right) && $right->can('annotations')
                && $right->annotations()->{scan}) {
            my $existing  = $l_prec;
            my $rule_name = $right->annotations()->{rule_name} // '';
            my $matched_text = $right->focus() // '';
            my $predicted = $right->annotations()->{predicted};
            return $self->_scan_multiply($existing, $rule_name, $matched_text, $predicted);
        }

        # Complete event: right Context has annotations->{complete} = true.
        # Apply precedence rule-completion logic.
        if (blessed($right) && $right->can('annotations')
                && $right->annotations()->{complete}) {
            my $rule_name = $right->annotations()->{rule_name};
            my $alt_idx   = $right->annotations()->{alt_idx};
            return $self->_complete_prec($l_prec, $rule_name, $alt_idx);
        }

        return $self->zero() if $self->is_zero($r_prec);

        # Delegate to the regular multiply logic with extracted slot values
        return $self->_prec_multiply($l_prec, $r_prec);
    }

    # _scan_multiply: operator-validation logic for scan events.
    # Called from multiply when the right argument is a scan-annotated Context.
    method _scan_multiply($existing, $rule_name, $matched_text, $predicted = undef) {
        # Propagate zero
        return $self->zero() if $self->is_zero($existing);

        # Named-unary detection: QualifiedIdentifier scanning a named-unary
        # token while CallExpression is predicted marks it with L10 precedence
        # (level=4.5, nonassoc, is_operator=true). The Subscript bracket-boundary
        # check below uses this to reject named-unary CallExpressions as
        # Subscript targets; PostfixExpression completion exempts level=4.5 so
        # the named-unary call itself can be a valid PostfixExpression.
        if ($rule_name eq 'QualifiedIdentifier'
                && Chalk::Grammar::Perl::PrecedenceTable::is_named_unary($matched_text)) {
            my $in_call = ref($predicted) eq 'HASH'
                ? exists $predicted->{CallExpression}
                : (defined $predicted ? $predicted->('CallExpression') : 0);
            if ($in_call) {
                my $nu_level = Chalk::Grammar::Perl::PrecedenceTable::named_unary_level();
                my $nu_assoc = Chalk::Grammar::Perl::PrecedenceTable::named_unary_assoc();
                if ($ENV{DEBUG_PRECEDENCE}) {
                    warn "  PREC_NAMED_UNARY: $matched_text level=$nu_level assoc=$nu_assoc\n";
                }
                return _intern(true, $nu_level, $nu_assoc, true, $matched_text);
            }
        }

        # `not` detection: UnaryExpression scanning /not\b/ gets L23 precedence
        # (level=12.5, right-associative, is_operator). This places `not` between
        # `..` (level 12) and `and` (level 13), matching perlop L23. Without this,
        # `not` inherits UnaryExpression's default level=-1 (tighter than all binary
        # ops), causing `not $a == $b` to misparse as `(not $a) == $b` rather than
        # `not ($a == $b)`.
        if ($rule_name eq 'UnaryExpression' && $matched_text =~ /^not\b/) {
            my $not_level = Chalk::Grammar::Perl::PrecedenceTable::not_level();
            if ($ENV{DEBUG_PRECEDENCE}) {
                warn "  PREC_NOT: matched=$matched_text level=$not_level\n";
            }
            return _intern(true, $not_level, 'right', true, $matched_text);
        }

        # TernaryExpression scanning '?' validates that the condition expression
        # (accumulated in $existing) has tighter binding than ?:, then resets
        # the accumulated level for the then/else branches.
        #
        # This enforces two related rules:
        #
        # 1. Right-associativity (perlop L19): reject a TernaryExpression (level=100)
        #    as the direct condition.  `$a ? $b : $c ? $d : $e` must parse as
        #    TernaryExpr($a,$b, TernaryExpr($c,$d,$e)), not the left-assoc form.
        #    Killing level=100 in the condition slot forces the right-assoc reading
        #    (the nested ternary goes on the else-branch instead).
        #
        # 2. ?: tighter than = (L19 < L20): reject an AssignmentExpression (level=101)
        #    as the condition.  `$a = $b ? $c : $d` must parse as
        #    Assign($a, TernaryExpr($b,$c,$d)), not TernaryExpr(Assign($a,$b),$c,$d).
        #
        # After validation, return one() to reset the accumulated level.  The
        # condition's level (e.g., $a==1 at level 7) must not constrain what
        # can appear in the then/else branches — those branches accept any
        # expression, including nested TernaryExpressions.  Without the reset,
        # the else-branch `$a==2 ? "two" : "other"` fails because
        # TernaryExpression (level=100) > condition-level (7).
        if ($rule_name eq 'TernaryExpression' && $matched_text eq '?') {
            if (defined($existing->{level}) && $existing->{level} >= 100) {
                if ($ENV{DEBUG_PRECEDENCE}) {
                    warn "  PREC_REJECT_TERNARY_COND: cond_level=$existing->{level} >= 100 at '?'\n";
                }
                return $self->zero();
            }
            if ($ENV{DEBUG_PRECEDENCE}) {
                my $el = $existing->{level} // 'undef';
                warn "  PREC_TERNARY_RESET: cond_level=$el at '?' -> reset to one()\n";
            }
            return $self->one();
        }

        # In BinaryOp or AssignOp context, look up operator and validate
        # the LEFT operand's precedence (accumulated in $existing).
        if ($rule_name eq 'BinaryOp' || $rule_name eq 'AssignOp') {
            my $op_info = $self->_do_lookup($matched_text);
            if (defined $op_info) {
                my $op_level = $op_info->{level};

                # Validate: the left operand (in $existing) must have higher
                # or equal precedence (lower or equal level number) than the
                # operator. Otherwise, the left operand has lower precedence
                # and can't be a direct child of this operator.
                if (defined($existing->{level}) && $existing->{level} > $op_level) {
                    if ($ENV{DEBUG_PRECEDENCE}) {
                        warn "  PREC_REJECT: left_level=$existing->{level} > op_level=$op_level ($matched_text)\n";
                    }
                    return $self->zero();
                }
                # Non-associative: reject same-level left operand.
                # `$a isa Foo isa Bar` and `1 .. 10 .. 100` are syntax errors
                # in Perl — the left operand of a nonassoc operator cannot
                # itself be an expression at the same precedence level.
                if (defined($existing->{level}) && $existing->{level} == $op_level
                        && $op_info->{assoc} eq 'nonassoc') {
                    if ($ENV{DEBUG_PRECEDENCE}) {
                        warn "  PREC_REJECT_NONASSOC: left_level=$existing->{level} == op_level=$op_level ($matched_text)\n";
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
                return _intern(true, $op_level, $op_info->{assoc}, true, $matched_text);
            }
            # AssignOp operators are not in the binary precedence table.
            # Give them level 101 (assignment precedence) with right-associativity
            # and is_operator, so multiply can reject left-grouping of chained
            # assignments: `(my $x = $y) //= 1` is invalid because the left
            # operand is an AssignmentExpression (level 101, right-assoc).
            if ($rule_name eq 'AssignOp') {
                my $assign_level = 101;  # $EXPR_LEVELS->{AssignmentExpression}

                # Validate left operand: reject if its level exceeds assignment
                # precedence. Also reject same-level left operands (right-assoc):
                # `(my $x = $y) //= 1` has left level=101 == op level=101.
                if (defined($existing->{level})) {
                    if ($existing->{level} > $assign_level) {
                        if ($ENV{DEBUG_PRECEDENCE}) {
                            warn "  PREC_REJECT: left_level=$existing->{level} > op_level=$assign_level ($matched_text)\n";
                        }
                        return $self->zero();
                    }
                    if ($existing->{level} == $assign_level) {
                        if ($ENV{DEBUG_PRECEDENCE}) {
                            warn "  PREC_REJECT_RASSOC: left_level=$existing->{level} == op_level=$assign_level ($matched_text)\n";
                        }
                        return $self->zero();
                    }
                }

                return _intern(true, $assign_level, 'right', true, $matched_text);
            }
        }

        # Named-unary CallExpression cannot be a Subscript target.
        # `defined $h{key}` must parse as defined($h{key}) (the call wraps the
        # subscript), not (defined $h){key} (subscript on the call). This
        # rejection at Subscript scan of [ or { blocks the wrong derivation.
        # Level 4.5 is uniquely assigned by the named-unary detection in this
        # method; no other code path produces level=4.5. is_operator gets
        # stripped by _prec_multiply when non-operator tokens multiply in, so
        # we check only the level, not is_operator.
        if ($rule_name eq 'Subscript' && $matched_text =~ /^[\[\{]$/
                && defined($existing->{level})
                && $existing->{level} == Chalk::Grammar::Perl::PrecedenceTable::named_unary_level()) {
            if ($ENV{DEBUG_PRECEDENCE}) {
                warn "  PREC_REJECT_NAMED_UNARY_TARGET: matched=$matched_text level=$existing->{level}\n";
            }
            return $self->zero();
        }

        # UnaryExpression cannot be a Subscript target.
        # `!$h{key}` must parse as !($h{key}) = Not(Subscript($h, key)), not
        # (!$h){key} = Subscript(Not($h), key). Per perlop, postfix subscript
        # (L2) binds tighter than unary ! / - / ~ (L5). UnaryExpression carries
        # level=-1 in $EXPR_LEVELS (tighter than all binary ops but looser than
        # PostfixExpression at level=-2). The level >= 0 check below does not
        # catch level=-1, so we add an explicit rejection here.
        # PostfixExpression (level=-2) IS a valid subscript target and must not
        # be rejected by this clause.
        if (($rule_name eq 'Subscript' || $rule_name eq 'PostfixDeref')
                && $matched_text =~ /^[\[\{]$/
                && defined($existing->{level})
                && $existing->{level} == -1) {
            if ($ENV{DEBUG_PRECEDENCE}) {
                warn "  PREC_REJECT_UNARY_TARGET: $rule_name matched=$matched_text level=$existing->{level}\n";
            }
            return $self->zero();
        }

        # Subscript bracket boundary: reject if the target is a bare
        # BinaryExpression. When `[` or `{` scans inside a Subscript rule,
        # the accumulated level comes from the target Expression. A level
        # in 0..99 means the target is a BinaryExpression (e.g., `$a // $b`),
        # which cannot be a subscript target without parentheses. This kills
        # the wrong parse of `$a->[$i] // $a->[-1]` as `($a->[$i] // $a)->[-1]`.
        if ($rule_name eq 'Subscript' && $matched_text =~ /^[\[\{]$/
                && defined($existing->{level}) && $existing->{level} >= 0) {
            return $self->zero();
        }

        # PostfixDeref bracket boundary: same logic as Subscript above, but
        # for the ->@[range] slice alternative. When `[` scans inside the
        # slice form of PostfixDeref, the accumulated level is from the target
        # Expression. A level in 0..99 means the target is a BinaryExpression
        # that cannot be a deref target without parentheses.
        if ($rule_name eq 'PostfixDeref' && $matched_text eq '['
                && defined($existing->{level}) && $existing->{level} >= 0) {
            return $self->zero();
        }

        # Non-operator scan: multiply with one (transparent)
        return $self->_prec_multiply($existing, $self->one());
    }

    # _prec_multiply: the core multiply logic on raw precedence hashrefs.
    # Called from multiply() after slot extraction and scan-event dispatch.
    method _prec_multiply($left, $right) {
        # Propagate zero
        return $self->zero() if $self->is_zero($left);
        return $self->zero() if $self->is_zero($right);

        # If neither has operator info, no precedence constraint
        return $self->one()
            if !defined($left->{level}) && !defined($right->{level});

        # Operator check: when a BinaryOp/AssignOp completion (is_operator)
        # multiplies into a BinaryExpression context carrying a left-operand
        # level, validate that the left operand's precedence is high enough
        # for this operator. E.g. ($a && $b) =~ /x/ is invalid because
        # && (level=10) has lower precedence than =~ (level=1).
        if ($right->{is_operator} && defined($left->{level})) {
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
            # Non-associative operators also reject same-level left operands:
            # `$a isa Foo isa Bar` and `1 .. 10 .. 100` are syntax errors in Perl.
            my $op_assoc = $right->{assoc} // 'left';
            if ($left_level == $op_level
                    && ($op_assoc eq 'right' || $op_assoc eq 'nonassoc')) {
                if ($ENV{DEBUG_PRECEDENCE}) {
                    warn "  PREC_REJECT_RASSOC: left_level=$left_level == op_level=$op_level ($right->{op})\n";
                }
                return $self->zero();
            }
            # Left operand is compatible. Adopt operator's level as context
            # for the right operand.
            return _intern(true, $op_level, $right->{assoc}, false, $right->{op});
        }

        # If only one has operator info, carry it through
        # (strip is_operator to prevent leaking into BinaryExpression context)
        if (!defined($left->{level})) {
            return _intern(true, $right->{level}, $right->{assoc}, false, $right->{op});
        }
        # Note: is_operator from $right is intentionally NOT propagated above
        if (!defined($right->{level})) {
            return _intern(true, $left->{level}, $left->{assoc}, false, $left->{op});
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
            return _intern(true, $parent_level, $parent_assoc, false, $left->{op});
        }

        # Child with higher precedence (lower level number) inside parent is always valid
        if ($child_level < $parent_level) {
            # Child binds tighter — valid. Carry parent's operator info.
            return _intern(true, $parent_level, $parent_assoc, false, $left->{op});
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
        my $right_is_op = $right->{is_operator};
        if ($parent_assoc eq 'left' && !$right_is_op) {
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
        return _intern(true, $parent_level, $parent_assoc, false, $left->{op});
    }

    method add($left, $right) {
        # Return first non-zero alternative, wrapped in a single-element arrayref.
        # This enables FilterComposite's identity-detection protocol: when the result
        # is the same object as one of the inputs, FilterComposite knows which side won.
        return [$right] if $self->is_zero($left);
        return [$left]  if $self->is_zero($right);

        # Identical inputs: return [$left] as a deterministic tie-break.
        # refaddr comparison works because all values are hash-consed.
        if (refaddr($left) == refaddr($right)) {
            return [$left];
        }

        # Both valid: prefer the value with level info (more constraining).
        # When both have levels, prefer the higher level number (lower
        # precedence = more constraining parent context). This ensures
        # the scan-time left-operand check has the tightest possible
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
            return [$left];
        }
        if (defined $rl && !defined $ll) {
            # Negative levels (-1 = UnaryExpression, -2 = PostfixExpression) are
            # marker levels that prevent certain completions — not real precedence
            # values for disambiguation. When only the right side carries a marker
            # level and left has no level, prefer left (no change in constraint).
            # Real positive levels on the right are genuinely more constraining.
            return $rl < 0 ? [$left] : [$right];
        }
        if (defined $ll && defined $rl) {
            # When a PostfixExpression (level<0) merges with an
            # AssignmentExpression (level>=100), prefer the PostfixExpression
            # level. The assignment level would otherwise kill valid
            # method-call/subscript parse paths downstream (PostfixExpression
            # completion rejects values with level>=0).
            if ($ll < 0 && $rl >= 100) {
                return [$left];
            }
            if ($rl < 0 && $ll >= 100) {
                return [$right];
            }
            if ($rl > $ll) {
                return [$right];
            }
        }

        return [$left];
    }

    # _complete_prec: apply precedence reification for a completed rule.
    # Receives the accumulated left-side precedence hashref and rule metadata.
    method _complete_prec($value, $rule_name, $alt_idx) {
        return $self->zero() if $self->is_zero($value);

        # Parenthesized expressions reset precedence context
        if ($RESETS->{$rule_name}) {
            return $self->one();
        }

        # Expression-type rules get their conceptual precedence level and associativity.
        # PostfixExpression rejects targets that carry a BinaryExpression
        # level (level >= 0): an unparenthesized BinaryExpression cannot
        # be a postfix target. This kills `($a && $b)->foo()` where
        # `$a && $b` has level=10, while allowing `$x->foo()` (no level)
        # and `($a + $b)->foo()` via parenthesized ParenExpr (resets level).
        # AssignmentExpression and TernaryExpression carry assoc='right' so
        # the same-level reject in _prec_multiply does not misfire when two
        # such completions meet in a chart-complete multiply.
        if (my $info = $EXPR_LEVELS->{$rule_name}) {
            my ($expr_level, $expr_assoc) = $info->@*;
            if ($expr_level < 0 && defined($value->{level}) && $value->{level} >= 0) {
                my $nu_level = Chalk::Grammar::Perl::PrecedenceTable::named_unary_level();
                # Exempt named-unary level: a named-unary CallExpression IS a
                # legitimate PostfixExpression. Preserve level=4.5 so that the
                # Subscript bracket-boundary scan in _scan_multiply can detect
                # a named-unary PostfixExpression being used as a Subscript
                # target and reject it. Note: is_operator gets stripped by
                # _prec_multiply, so only the level (4.5) is checked below.
                if ($value->{level} == $nu_level) {
                    return _intern(true, $nu_level, $value->{assoc}, false);
                }
                # Exempt `not` level: a `not` UnaryExpression carries level=12.5
                # (L23) so that outer binary operators can correctly reject it as
                # a left operand (e.g., `==` at level 7 rejects not-expression at
                # 12.5 as its left child, forcing `not ($a == $b)` grouping).
                my $not_level = Chalk::Grammar::Perl::PrecedenceTable::not_level();
                if ($value->{level} == $not_level) {
                    return _intern(true, $not_level, 'right', false);
                }
                return $self->zero();
            }
            return _intern(true, $expr_level, $expr_assoc, false);
        }

        # BinaryOp/AssignOp completion: the value already carries operator info
        # from scan. Pass it through so multiply can use is_operator.
        if ($rule_name eq 'BinaryOp' || $rule_name eq 'AssignOp') {
            return $value;
        }

        # BinaryExpression completion: carries the operator's level
        if ($rule_name eq 'BinaryExpression') {
            return $value;
        }

        # Expression: pass through precedence info from child so that
        # a BinaryExpression's operator level survives the Expression
        # wrapper and can be checked by an outer BinaryExpression.
        if ($rule_name eq 'Expression') {
            return $value;
        }

        # Subscript brackets [...] and {...} are delimiter boundaries.
        # Inner binary expressions (e.g., `$i + 1` in `$x->[$i + 1]`)
        # must not leak their operator level through the Subscript into
        # PostfixExpression. However, if the left operand of the Subscript
        # is an AssignmentExpression or TernaryExpression (level >= 100),
        # that level must survive so PostfixExpression can reject it:
        # `($x = $h){$k}` is invalid without parens.
        if ($rule_name eq 'Subscript') {
            if (defined($value->{level}) && $value->{level} >= 100) {
                return _intern(true, $value->{level}, $value->{assoc}, false);
            }
            return $self->one();
        }

        # MethodCall/PostfixIncDec: pass through precedence info so
        # PostfixExpression's completion can reject invalid targets.
        if ($rule_name eq 'MethodCall' || $rule_name eq 'PostfixIncDec') {
            return $value;
        }

        # CallExpression: pass through precedence info, but reset the
        # named-unary level (4.5) for the parenthesized alternative (alt 0:
        # QualifiedIdentifier _ \( ExpressionList? \)). When named-unary
        # operators use explicit parens, e.g. scalar(@arr), the parens bound
        # the argument and the result behaves as a regular term. Alts 1-3
        # (space-delimited) are named-unary calls without explicit delimiter;
        # these preserve level=4.5 so the Subscript boundary check can fire.
        if ($rule_name eq 'CallExpression') {
            my $nu_level = Chalk::Grammar::Perl::PrecedenceTable::named_unary_level();
            if (defined($alt_idx) && $alt_idx == 0
                    && defined($value->{level})
                    && $value->{level} == $nu_level) {
                return $self->one();
            }
            return $value;
        }

        # PostfixDeref: bracket form (alt_idx == 4, the ->@[range] alternative)
        # resets precedence context like Subscript — inner binary expressions
        # (e.g., `$i + 1` in `$x->@[$i + 1]`) must not leak their operator
        # level into the PostfixExpression wrapper. Non-bracket forms (alts 0-3:
        # ->@*, ->%*, ->$*, ->$#*) pass through unchanged.
        if ($rule_name eq 'PostfixDeref') {
            if (defined($alt_idx) && $alt_idx == 4) {
                if (defined($value->{level}) && $value->{level} >= 100) {
                    return _intern(true, $value->{level}, $value->{assoc}, false);
                }
                return $self->one();
            }
            return $value;
        }

        # Atom and QualifiedIdentifier preserve a named-unary marker so the
        # level=4.5 from _scan_multiply survives through to the CallExpression
        # wrapping it. Without this, the catch-all below clears the marker.
        if (($rule_name eq 'Atom' || $rule_name eq 'QualifiedIdentifier')
                && $value->{is_operator}
                && defined($value->{level})
                && $value->{level} == Chalk::Grammar::Perl::PrecedenceTable::named_unary_level()) {
            return $value;
        }

        # Other rules: pass through value, clear operator info
        return $self->one();
    }

    # slot_name: Precedence reads/writes the 'precedence' annotation slot.
    method slot_name() {
        return 'precedence';
    }

}
