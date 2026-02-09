# ABOUTME: Structural semiring for disambiguation in Earley parsing.
# ABOUTME: Tags Block/Hash/bare-statement completions, prefers separated expressions via add().
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::Structural {

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

        # Propagate tags from either child
        my $is_block = $left->{is_block} || $right->{is_block};
        my $is_hash  = $left->{is_hash}  || $right->{is_hash};
        my $is_bare  = $left->{is_bare_statement} || $right->{is_bare_statement};
        my $is_call  = $left->{is_call}  || $right->{is_call};

        return {
            valid => true,
            ($is_block ? (is_block          => true) : ()),
            ($is_hash  ? (is_hash           => true) : ()),
            ($is_bare  ? (is_bare_statement => true) : ()),
            ($is_call  ? (is_call           => true) : ()),
        };
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if $self->is_zero($left);
        return $left  if $self->is_zero($right);

        # Both valid: prefer non-bare over bare (expression separator disambiguation)
        my $left_bare  = $left->{is_bare_statement};
        my $right_bare = $right->{is_bare_statement};
        if ($left_bare && !$right_bare) {
            return $right;
        }
        if ($right_bare && !$left_bare) {
            return $left;
        }

        # Both valid: prefer is_call over non-call
        # CallExpression consumes more input than bare Identifier.
        my $left_call  = $left->{is_call};
        my $right_call = $right->{is_call};
        if ($left_call && !$right_call) {
            return $left;
        }
        if ($right_call && !$left_call) {
            return $right;
        }

        # Both valid: prefer is_block over is_hash
        if ($left->{is_block} || $right->{is_block}) {
            return { valid => true, is_block => true };
        }

        # Both valid, neither is block: prefer is_hash if present
        if ($left->{is_hash} || $right->{is_hash}) {
            return { valid => true, is_hash => true };
        }

        # Both valid, untagged (or both bare)
        my $is_bare = $left_bare || $right_bare;
        my $is_call = $left_call || $right_call;
        return {
            valid => true,
            ($is_bare ? (is_bare_statement => true) : ()),
            ($is_call ? (is_call           => true) : ()),
        };
    }

    # Signal to Composite which alternative to select for ALL components.
    # Returns 'left', 'right', or undef (no preference).
    method selects_alternative($left, $right) {
        return undef if $self->is_zero($left);
        return undef if $self->is_zero($right);

        # Prefer non-bare over bare
        my $left_bare  = $left->{is_bare_statement};
        my $right_bare = $right->{is_bare_statement};
        if ($left_bare && !$right_bare) {
            return 'right';
        }
        if ($right_bare && !$left_bare) {
            return 'left';
        }

        # Prefer CallExpression over non-call
        if ($left->{is_call} && !$right->{is_call}) {
            return 'left';
        }
        if ($right->{is_call} && !$left->{is_call}) {
            return 'right';
        }

        # Prefer block over hash
        if ($left->{is_block} && !$right->{is_block}) {
            return 'left';
        }
        if ($right->{is_block} && !$left->{is_block}) {
            return 'right';
        }

        return undef;
    }

    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my $existing = $item->{value};

        # Propagate zero
        return $self->zero() if $self->is_zero($existing);

        # Transparent: just multiply with one()
        return $self->multiply($existing, $self->one());
    }

    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return $self->zero() if $self->is_zero($value);

        my $rule_name = $item->{rule}->name();

        # Tag Block completions
        if ($rule_name eq 'Block') {
            return { valid => true, is_block => true };
        }

        # Tag HashConstructor completions
        if ($rule_name eq 'HashConstructor') {
            return { valid => true, is_hash => true };
        }

        # Tag CallExpression completions — preferred over bare Identifier
        if ($rule_name eq 'CallExpression') {
            return { valid => true, is_call => true };
        }

        # Tag MethodCall completions with parens (alts 0, 2) — preferred over
        # bare method access (alts 1, 3) so args aren't lost as separate stmts.
        if ($rule_name eq 'MethodCall' && ($alt_idx == 0 || $alt_idx == 2)) {
            return { valid => true, is_call => true };
        }

        # Tag bare StatementItem (alt 1 = SimpleStatement without semicolon)
        if ($rule_name eq 'StatementItem' && $alt_idx == 1) {
            return {
                valid => true,
                is_bare_statement => true,
                ($value->{is_block} ? (is_block => true) : ()),
                ($value->{is_hash}  ? (is_hash  => true) : ()),
                ($value->{is_call}  ? (is_call  => true) : ()),
            };
        }

        # Boundary rules: clear all structural tags
        if ($rule_name eq 'ParenExpr'
            || $rule_name eq 'ArrayConstructor') {
            return { valid => true };
        }

        # Statement boundaries: clear block/hash, preserve is_bare_statement and is_call
        if ($rule_name eq 'StatementList'
            || $rule_name eq 'Program') {
            return {
                valid => true,
                ($value->{is_bare_statement} ? (is_bare_statement => true) : ()),
                ($value->{is_call}           ? (is_call           => true) : ()),
            };
        }

        # Other rules: pass through tags from value
        my $is_block = $value->{is_block};
        my $is_hash  = $value->{is_hash};
        my $is_bare  = $value->{is_bare_statement};
        my $is_call  = $value->{is_call};

        return {
            valid => true,
            ($is_block ? (is_block          => true) : ()),
            ($is_hash  ? (is_hash           => true) : ()),
            ($is_bare  ? (is_bare_statement => true) : ()),
            ($is_call  ? (is_call           => true) : ()),
        };
    }
}
