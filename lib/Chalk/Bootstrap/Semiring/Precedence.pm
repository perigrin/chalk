# ABOUTME: Precedence semiring for operator-level disambiguation in Earley parsing.
# ABOUTME: Rejects invalid operator nesting via is_zero, so bad parses die in the chart.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::PrecedenceTable;

class Chalk::Bootstrap::Semiring::Precedence {
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

        # If only one has operator info, carry it through
        if (!defined($left->{level})) {
            return { valid => true, op => $right->{op}, level => $right->{level}, assoc => $right->{assoc} };
        }
        if (!defined($right->{level})) {
            return { valid => true, op => $left->{op}, level => $left->{level}, assoc => $left->{assoc} };
        }

        # Both have operator info — validate precedence nesting
        # The left value is the "parent" context, right is the "child" being added
        my $parent_level = $left->{level};
        my $child_level = $right->{level};
        my $parent_assoc = $left->{assoc} // 'left';

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

        # left, right, chained: same level is allowed (direction checked structurally)
        return { valid => true, op => $left->{op}, level => $parent_level, assoc => $parent_assoc };
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if $self->is_zero($left);
        return $left if $self->is_zero($right);
        return $left;
    }

    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my $existing = $item->{value};

        # Propagate zero
        return $self->zero() if $self->is_zero($existing);

        my $rule_name = $item->{rule}->name();

        # In BinaryOp or AssignOp context, look up operator
        if ($rule_name eq 'BinaryOp' || $rule_name eq 'AssignOp') {
            my $op_info = Chalk::Bootstrap::PrecedenceTable::lookup($matched_text);
            if (defined $op_info) {
                return $self->multiply($existing, {
                    valid => true,
                    op    => $matched_text,
                    level => $op_info->{level},
                    assoc => $op_info->{assoc},
                });
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

        # Expression-type rules get their conceptual precedence level
        if (defined $EXPR_LEVELS->{$rule_name}) {
            return {
                valid => true,
                op    => undef,
                level => $EXPR_LEVELS->{$rule_name},
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

        # Other rules: pass through value, clear operator info
        return { valid => true };
    }

}
