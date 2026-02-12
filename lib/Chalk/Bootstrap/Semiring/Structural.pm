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
        my $is_call  = $left->{is_call}  || $right->{is_call};
        my $is_list  = $left->{is_list}  || $right->{is_list};
        my $is_deref  = $left->{is_deref}  || $right->{is_deref};
        my $is_method = $left->{is_method} || $right->{is_method};
        my $is_binop   = $left->{is_binop}   || $right->{is_binop};
        my $is_vardecl = $left->{is_vardecl} || $right->{is_vardecl};

        return {
            valid => true,
            ($is_block   ? (is_block   => true) : ()),
            ($is_hash    ? (is_hash    => true) : ()),
            ($is_call    ? (is_call    => true) : ()),
            ($is_list    ? (is_list    => true) : ()),
            ($is_deref   ? (is_deref   => true) : ()),
            ($is_method  ? (is_method  => true) : ()),
            ($is_binop   ? (is_binop   => true) : ()),
            ($is_vardecl ? (is_vardecl => true) : ()),
        };
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if $self->is_zero($left);
        return $left  if $self->is_zero($right);

        # Both valid: prefer non-list over list (Expression vs ExpressionList)
        my $left_list  = $left->{is_list};
        my $right_list = $right->{is_list};
        if ($left_list && !$right_list) {
            return $right;
        }
        if ($right_list && !$left_list) {
            return $left;
        }

        # Both valid: prefer is_call over non-call
        # CallExpression consumes more input than bare QualifiedIdentifier.
        my $left_call  = $left->{is_call};
        my $right_call = $right->{is_call};
        if ($left_call && !$right_call) {
            return $left;
        }
        if ($right_call && !$left_call) {
            return $right;
        }

        # Both valid, both is_call: prefer non-deref over deref.
        # CallExpression (direct call consuming args) wins over
        # PostfixDeref-on-CallExpression (deref on shorter call).
        my $left_deref  = $left->{is_deref};
        my $right_deref = $right->{is_deref};
        if ($left_call && $right_call) {
            if ($right_deref && !$left_deref) {
                return $left;
            }
            if ($left_deref && !$right_deref) {
                return $right;
            }
        }

        # Both valid, both is_call: prefer non-method over method.
        # CallExpression (direct function call consuming full arg list) wins
        # over MethodCall (method on shorter expression result).
        my $left_method  = $left->{is_method};
        my $right_method = $right->{is_method};
        if ($left_call && $right_call) {
            if ($right_method && !$left_method) {
                return $left;
            }
            if ($left_method && !$right_method) {
                return $right;
            }
        }

        # Both valid, both is_call: prefer non-binop over binop.
        # CallExpression (consuming args) wins over BinaryExpression
        # that fragments the call: `push @a, $x . $y` as one call
        # is preferred over `(push @a) . $x . $y`.
        my $left_binop  = $left->{is_binop};
        my $right_binop = $right->{is_binop};
        if ($left_call && $right_call) {
            if ($right_binop && !$left_binop) {
                return $left;
            }
            if ($left_binop && !$right_binop) {
                return $right;
            }
        }

        # Both valid: prefer is_block over is_hash
        if ($left->{is_block} || $right->{is_block}) {
            return { valid => true, is_block => true };
        }

        # Both valid, neither is block: prefer is_hash if present
        if ($left->{is_hash} || $right->{is_hash}) {
            return { valid => true, is_hash => true };
        }

        # Both valid: prefer is_vardecl over non-is_vardecl.
        # VariableDeclaration (my/our/state/local as declarator keyword) is a
        # more specific parse than one where `my` is a bare QualifiedIdentifier.
        my $left_vardecl  = $left->{is_vardecl};
        my $right_vardecl = $right->{is_vardecl};
        if ($left_vardecl && !$right_vardecl) {
            return $left;
        }
        if ($right_vardecl && !$left_vardecl) {
            return $right;
        }

        # Both valid, untagged
        my $is_call    = $left_call    || $right_call;
        my $is_list    = $left_list    || $right_list;
        my $is_deref   = $left_deref   || $right_deref;
        my $is_method  = $left_method  || $right_method;
        my $is_binop   = $left_binop   || $right_binop;
        my $is_vardecl = $left_vardecl || $right_vardecl;
        return {
            valid => true,
            ($is_call    ? (is_call    => true) : ()),
            ($is_list    ? (is_list    => true) : ()),
            ($is_deref   ? (is_deref   => true) : ()),
            ($is_method  ? (is_method  => true) : ()),
            ($is_binop   ? (is_binop   => true) : ()),
            ($is_vardecl ? (is_vardecl => true) : ()),
        };
    }

    # Signal to Composite which alternative to select for ALL components.
    # Returns 'left', 'right', or undef (no preference).
    method selects_alternative($left, $right) {
        return undef if $self->is_zero($left);
        return undef if $self->is_zero($right);

        # Prefer non-list over list (Expression vs ExpressionList)
        if ($left->{is_list} && !$right->{is_list}) {
            return 'right';
        }
        if ($right->{is_list} && !$left->{is_list}) {
            return 'left';
        }
        # Both is_list: duplicate ExpressionList paths — pick left arbitrarily
        if ($left->{is_list} && $right->{is_list}) {
            return 'left';
        }

        # Prefer CallExpression over non-call
        if ($left->{is_call} && !$right->{is_call}) {
            return 'left';
        }
        if ($right->{is_call} && !$left->{is_call}) {
            return 'right';
        }

        # Both is_call: prefer non-deref over deref
        if ($left->{is_call} && $right->{is_call}) {
            if ($right->{is_deref} && !$left->{is_deref}) {
                return 'left';
            }
            if ($left->{is_deref} && !$right->{is_deref}) {
                return 'right';
            }
        }

        # Both is_call: prefer non-method over method
        if ($left->{is_call} && $right->{is_call}) {
            if ($right->{is_method} && !$left->{is_method}) {
                return 'left';
            }
            if ($left->{is_method} && !$right->{is_method}) {
                return 'right';
            }
        }

        # Both is_call: prefer non-binop over binop
        if ($left->{is_call} && $right->{is_call}) {
            if ($right->{is_binop} && !$left->{is_binop}) {
                return 'left';
            }
            if ($left->{is_binop} && !$right->{is_binop}) {
                return 'right';
            }
        }

        # Prefer block over hash
        if ($left->{is_block} && !$right->{is_block}) {
            return 'left';
        }
        if ($right->{is_block} && !$left->{is_block}) {
            return 'right';
        }

        # Prefer is_vardecl over non-is_vardecl
        if ($left->{is_vardecl} && !$right->{is_vardecl}) {
            return 'left';
        }
        if ($right->{is_vardecl} && !$left->{is_vardecl}) {
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

        # Tag VariableDeclaration completions — marks a `my`/`our`/`state`/`local`
        # declaration. This distinguishes correct parses (where `my` is a
        # declarator keyword) from bogus parses where `my` is treated as a
        # bare QualifiedIdentifier in a CallExpression.
        if ($rule_name eq 'VariableDeclaration') {
            return {
                valid => true,
                is_vardecl => true,
                ($value->{is_block} ? (is_block => true) : ()),
            };
        }

        # Tag PostfixDeref completions — marks a deref on an expression.
        # Do NOT propagate is_call from child: PostfixDeref is a dereference,
        # not a function call. This allows add() to prefer CallExpression
        # (is_call) over PostfixDeref-on-CallExpression (is_deref, no is_call)
        # via the existing "prefer is_call over non-call" rule.
        if ($rule_name eq 'PostfixDeref') {
            return {
                valid => true,
                is_deref => true,
                ($value->{is_block} ? (is_block => true) : ()),
            };
        }

        # Tag CallExpression completions — preferred over bare Identifier.
        # Preserve is_block/is_hash from inner nonterminals so add() can
        # prefer CallExpression-with-Block over CallExpression-with-Hash.
        # Clear is_deref/is_method: CallExpression is a direct function call,
        # deref/method tags from arguments should not leak outward.
        if ($rule_name eq 'CallExpression') {
            return {
                valid => true,
                is_call => true,
                ($value->{is_block} ? (is_block => true) : ()),
            };
        }

        # Tag MethodCall completions with parens (alts 0, 2) — preferred over
        # bare method access (alts 1, 3) so args aren't lost as separate stmts.
        # All MethodCall alts get is_method so add() prefers CallExpression
        # over MethodCall when both compete at the same PostfixExpression position.
        if ($rule_name eq 'MethodCall') {
            return {
                valid => true,
                is_method => true,
                (($alt_idx == 0 || $alt_idx == 2) ? (is_call => true) : ()),
                ($value->{is_call} ? (is_call => true) : ()),
            };
        }

        # Tag BinaryExpression with is_binop to distinguish from CallExpression.
        # When `push @a, $x . $y` produces two parses:
        #   1. CallExpression: push(@a, $x . $y) — is_call only
        #   2. BinaryExpression: (push @a) . $x . $y — is_call + is_binop
        # add() prefers the non-binop (CallExpression) path.
        if ($rule_name eq 'BinaryExpression') {
            return {
                valid => true,
                is_binop => true,
                ($value->{is_block}   ? (is_block   => true) : ()),
                ($value->{is_hash}    ? (is_hash    => true) : ()),
                ($value->{is_call}    ? (is_call    => true) : ()),
                ($value->{is_deref}   ? (is_deref   => true) : ()),
                ($value->{is_method}  ? (is_method  => true) : ()),
                ($value->{is_vardecl} ? (is_vardecl => true) : ()),
            };
        }

        # Tag ExpressionList alts 1-3 (comma/arrow/trailing-comma forms)
        # with is_list so add() can prefer the simpler single-Expression
        # alt 0 when both match. Without this, two ExpressionList alternatives
        # ending in PostfixDeref would have identical tags ({is_deref, valid}).
        if ($rule_name eq 'ExpressionList' && $alt_idx >= 1) {
            return {
                valid   => true,
                is_list => true,
                ($value->{is_block}   ? (is_block   => true) : ()),
                ($value->{is_hash}    ? (is_hash    => true) : ()),
                ($value->{is_call}    ? (is_call    => true) : ()),
                ($value->{is_deref}   ? (is_deref   => true) : ()),
                ($value->{is_method}  ? (is_method  => true) : ()),
                ($value->{is_vardecl} ? (is_vardecl => true) : ()),
            };
        }

        # Tag ExpressionStatement alt 1 (ExpressionList) — when a single
        # expression matches both Expression and ExpressionList, prefer
        # Expression (simpler parse). The list form is only correct when
        # there are actual commas or fat arrows.
        if ($rule_name eq 'ExpressionStatement' && $alt_idx == 1) {
            return {
                valid   => true,
                is_list => true,
                ($value->{is_block}   ? (is_block   => true) : ()),
                ($value->{is_hash}    ? (is_hash    => true) : ()),
                ($value->{is_call}    ? (is_call    => true) : ()),
                ($value->{is_vardecl} ? (is_vardecl => true) : ()),
            };
        }

        # Tag UseDeclaration with imports (alt 1) as is_call to prefer
        # it over the shorter alt 0 (without imports). This prevents
        # `use Foo 'bar'` from fragmenting into `use Foo` + `'bar'`.
        if ($rule_name eq 'UseDeclaration' && $alt_idx == 1) {
            return { valid => true, is_call => true };
        }


        # ParenExpr alt 1 (ExpressionList) — tag as list so add() prefers
        # the simpler Expression parse (alt 0) for single expressions.
        if ($rule_name eq 'ParenExpr' && $alt_idx == 1) {
            return { valid => true, is_list => true };
        }

        # Boundary rules: clear all structural tags
        if ($rule_name eq 'ParenExpr'
            || $rule_name eq 'ArrayConstructor') {
            return { valid => true };
        }

        # Statement boundaries: clear block/hash, preserve is_call, is_list
        if ($rule_name eq 'StatementList'
            || $rule_name eq 'Program') {
            return {
                valid => true,
                ($value->{is_call} ? (is_call => true) : ()),
                ($value->{is_list} ? (is_list => true) : ()),
            };
        }

        # Other rules: pass through tags from value
        my $is_block   = $value->{is_block};
        my $is_hash    = $value->{is_hash};
        my $is_call    = $value->{is_call};
        my $is_list    = $value->{is_list};
        my $is_deref   = $value->{is_deref};
        my $is_method  = $value->{is_method};
        my $is_binop   = $value->{is_binop};
        my $is_vardecl = $value->{is_vardecl};

        return {
            valid => true,
            ($is_block   ? (is_block   => true) : ()),
            ($is_hash    ? (is_hash    => true) : ()),
            ($is_call    ? (is_call    => true) : ()),
            ($is_list    ? (is_list    => true) : ()),
            ($is_deref   ? (is_deref   => true) : ()),
            ($is_method  ? (is_method  => true) : ()),
            ($is_binop   ? (is_binop   => true) : ()),
            ($is_vardecl ? (is_vardecl => true) : ()),
        };
    }
}
