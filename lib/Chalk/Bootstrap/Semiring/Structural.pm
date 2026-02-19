# ABOUTME: Structural semiring for disambiguation in Earley parsing.
# ABOUTME: Tags Block/Hash/bare-statement completions via integer bitfield, prefers separated expressions via add().
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::Structural {

    # Integer bitfield constants for structural tags.
    # Each bit position represents a distinct structural property of a parse item.
    # Bit 0: is_block    (1)   - item completed a Block rule
    # Bit 1: is_hash     (2)   - item completed a HashConstructor rule
    # Bit 2: is_call     (4)   - item completed a CallExpression rule
    # Bit 3: is_list     (8)   - item completed an ExpressionList or ExpressionStatement alt
    # Bit 4: is_deref    (16)  - item completed a PostfixDeref or Subscript rule
    # Bit 5: is_method   (32)  - item completed a MethodCall rule
    # Bit 6: is_binop    (64)  - item completed a BinaryExpression rule
    # Bit 7: is_vardecl  (128) - item completed a VariableDeclaration rule
    use constant {
        STRUCT_IS_BLOCK   => 1,
        STRUCT_IS_HASH    => 2,
        STRUCT_IS_CALL    => 4,
        STRUCT_IS_LIST    => 8,
        STRUCT_IS_DEREF   => 16,
        STRUCT_IS_METHOD  => 32,
        STRUCT_IS_BINOP   => 64,
        STRUCT_IS_VARDECL => 128,
    };

    use Exporter 'import';
    our @EXPORT_OK = qw(
        STRUCT_IS_BLOCK  STRUCT_IS_HASH    STRUCT_IS_CALL
        STRUCT_IS_LIST   STRUCT_IS_DEREF   STRUCT_IS_METHOD
        STRUCT_IS_BINOP  STRUCT_IS_VARDECL
    );

    # zero() returns -1: the sentinel value outside the 0-255 valid bitfield range.
    # This marks a dead parse path.
    method zero() {
        return -1;
    }

    # one() returns 0: the identity value with no bits set (valid, no structural tags).
    method one() {
        return 0;
    }

    # is_zero($value): true iff value is the sentinel -1.
    method is_zero($value) {
        return $value == -1;
    }

    method multiply($left, $right) {
        # Propagate zero
        return -1 if $left == -1;
        return -1 if $right == -1;

        # Combine tags from both sides using bitwise OR
        return $left | $right;
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if $left == -1;
        return $left  if $right == -1;

        # Both valid: prefer non-list over list (Expression vs ExpressionList)
        my $left_list  = $left  & STRUCT_IS_LIST;
        my $right_list = $right & STRUCT_IS_LIST;
        if ($left_list && !$right_list) {
            return $right;
        }
        if ($right_list && !$left_list) {
            return $left;
        }

        # Both valid: prefer is_call over non-call
        # CallExpression consumes more input than bare QualifiedIdentifier.
        my $left_call  = $left  & STRUCT_IS_CALL;
        my $right_call = $right & STRUCT_IS_CALL;
        if ($left_call && !$right_call) {
            return $left;
        }
        if ($right_call && !$left_call) {
            return $right;
        }

        # Both valid, both is_call: prefer non-deref over deref.
        # CallExpression (direct call consuming args) wins over
        # PostfixDeref-on-CallExpression (deref on shorter call).
        my $left_deref  = $left  & STRUCT_IS_DEREF;
        my $right_deref = $right & STRUCT_IS_DEREF;
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
        my $left_method  = $left  & STRUCT_IS_METHOD;
        my $right_method = $right & STRUCT_IS_METHOD;
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
        my $left_binop  = $left  & STRUCT_IS_BINOP;
        my $right_binop = $right & STRUCT_IS_BINOP;
        if ($left_call && $right_call) {
            if ($right_binop && !$left_binop) {
                return $left;
            }
            if ($left_binop && !$right_binop) {
                return $right;
            }
        }

        # Prefer non-binop over binop when is_call is absent.
        # Chained BinaryExpressions with hash subscripts on both sides
        # produce two Expression alternatives that differ only in grouping.
        # The non-binop alternative is the correct simpler parse.
        if (!$left_call && !$right_call) {
            if ($right_binop && !$left_binop) {
                return $left;
            }
            if ($left_binop && !$right_binop) {
                return $right;
            }
        }

        # Both valid: prefer non-deref over deref when is_call is absent.
        # PostfixDeref wrapping a larger expression (e.g.,
        # `(map {...} $x)->@*`) should lose to the simpler parse where
        # the deref is part of the inner expression (e.g., `map {...} $x->@*`).
        if (!$left_call && !$right_call) {
            if ($right_deref && !$left_deref) {
                return $left;
            }
            if ($left_deref && !$right_deref) {
                return $right;
            }
        }

        # Both valid: prefer is_block over is_hash.
        # Returns the actual winning object ($left or $right) so that Composite
        # can detect the preference via numeric identity comparison.
        my $left_block  = $left  & STRUCT_IS_BLOCK;
        my $right_block = $right & STRUCT_IS_BLOCK;
        my $left_hash   = $left  & STRUCT_IS_HASH;
        my $right_hash  = $right & STRUCT_IS_HASH;
        if ($left_block || $right_block) {
            # When both are is_block, prefer the one without is_hash.
            # This resolves `{ {} }` where one Block alt has inner Block
            # (pure is_block) and another has trailing HashConstructor
            # (is_block + is_hash).
            if ($left_block && $right_block) {
                if ($right_hash && !$left_hash) {
                    return $left;
                }
                if ($left_hash && !$right_hash) {
                    return $right;
                }
                # Both have is_block and same hash status — pick left
                return $left;
            }
            # One-sided: the block side wins
            return $left_block ? $left : $right;
        }

        # Both valid, neither is block: prefer is_hash if present.
        # Returns the actual winning object for Composite identity detection.
        if ($left_hash || $right_hash) {
            if ($left_hash && !$right_hash) {
                return $left;
            }
            if ($right_hash && !$left_hash) {
                return $right;
            }
            # Both have is_hash — pick left
            return $left;
        }

        # Both valid: prefer is_vardecl over non-is_vardecl.
        # VariableDeclaration (my/our/state/local as declarator keyword) is a
        # more specific parse than one where `my` is a bare QualifiedIdentifier.
        my $left_vardecl  = $left  & STRUCT_IS_VARDECL;
        my $right_vardecl = $right & STRUCT_IS_VARDECL;
        if ($left_vardecl && !$right_vardecl) {
            return $left;
        }
        if ($right_vardecl && !$left_vardecl) {
            return $right;
        }

        # Both valid, untagged: merge all bits
        return $left | $right;
    }

    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my $existing = $item->{value};

        # Propagate zero
        return -1 if $existing == -1;

        # Transparent pass-through
        return $existing;
    }

    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return -1 if $value == -1;

        my $rule_name = $item->{rule}->name();

        # Tag Block completions. Preserve is_hash from inner content so that
        # add() can prefer a pure-Block interpretation over one where a
        # HashConstructor acts as a trailing SimpleStatement. In `{ {} }`,
        # alt 0 (inner Block) has is_block only; alt 1 (trailing HashConstructor)
        # has is_block + is_hash. The preference for pure-Block resolves this.
        if ($rule_name eq 'Block') {
            return STRUCT_IS_BLOCK | ($value & STRUCT_IS_HASH);
        }

        # Tag HashConstructor completions
        if ($rule_name eq 'HashConstructor') {
            return STRUCT_IS_HASH;
        }

        # Tag VariableDeclaration completions — marks a `my`/`our`/`state`/`local`
        # declaration. This distinguishes correct parses (where `my` is a
        # declarator keyword) from bogus parses where `my` is treated as a
        # bare QualifiedIdentifier in a CallExpression.
        if ($rule_name eq 'VariableDeclaration') {
            return STRUCT_IS_VARDECL | ($value & STRUCT_IS_BLOCK);
        }

        # Tag PostfixDeref completions — marks a deref on an expression.
        # Do NOT propagate is_call from child: PostfixDeref is a dereference,
        # not a function call. This allows add() to prefer CallExpression
        # (is_call) over PostfixDeref-on-CallExpression (is_deref, no is_call)
        # via the existing "prefer is_call over non-call" rule.
        if ($rule_name eq 'PostfixDeref') {
            return STRUCT_IS_DEREF | ($value & STRUCT_IS_BLOCK);
        }

        # Tag ALL Subscript completions with is_deref.
        # Arrow variants (alts 0-2): $f->($x), $f->[$i], $f->{$k}
        # Non-arrow variants (alts 3-4): $h[$i], $h{$k}
        # Both are dereference operations. Tagging them allows add() to
        # prefer CallExpression (is_call, no is_deref) over
        # Subscript(CallExpression, ...) (is_call + is_deref).
        if ($rule_name eq 'Subscript') {
            return STRUCT_IS_DEREF
                | ($value & STRUCT_IS_CALL)
                | ($value & STRUCT_IS_BLOCK);
        }

        # Tag CallExpression completions — preferred over bare Identifier.
        # Preserve is_block/is_hash from inner nonterminals so add() can
        # prefer CallExpression-with-Block over CallExpression-with-Hash.
        # Clear is_deref/is_method: CallExpression is a direct function call,
        # deref/method tags from arguments should not leak outward.
        if ($rule_name eq 'CallExpression') {
            return STRUCT_IS_CALL | ($value & STRUCT_IS_BLOCK);
        }

        # Tag MethodCall completions with parens (alts 0, 2) — preferred over
        # bare method access (alts 1, 3) so args aren't lost as separate stmts.
        # All MethodCall alts get is_method so add() prefers CallExpression
        # over MethodCall when both compete at the same PostfixExpression position.
        if ($rule_name eq 'MethodCall') {
            my $call_from_alt   = ($alt_idx == 0 || $alt_idx == 2) ? STRUCT_IS_CALL : 0;
            my $call_from_child = $value & STRUCT_IS_CALL;
            return STRUCT_IS_METHOD | $call_from_alt | $call_from_child;
        }

        # Tag BinaryExpression with is_binop to distinguish from CallExpression.
        # When `push @a, $x . $y` produces two parses:
        #   1. CallExpression: push(@a, $x . $y) — is_call only
        #   2. BinaryExpression: (push @a) . $x . $y — is_call + is_binop
        # add() prefers the non-binop (CallExpression) path.
        if ($rule_name eq 'BinaryExpression') {
            return STRUCT_IS_BINOP
                | ($value & STRUCT_IS_BLOCK)
                | ($value & STRUCT_IS_HASH)
                | ($value & STRUCT_IS_CALL)
                | ($value & STRUCT_IS_DEREF)
                | ($value & STRUCT_IS_METHOD)
                | ($value & STRUCT_IS_VARDECL);
        }

        # Tag ExpressionList alts 1-3 (comma/arrow/trailing-comma forms)
        # with is_list so add() can prefer the simpler single-Expression
        # alt 0 when both match. Without this, two ExpressionList alternatives
        # ending in PostfixDeref would have identical tags.
        if ($rule_name eq 'ExpressionList' && $alt_idx >= 1) {
            return STRUCT_IS_LIST
                | ($value & STRUCT_IS_BLOCK)
                | ($value & STRUCT_IS_HASH)
                | ($value & STRUCT_IS_CALL)
                | ($value & STRUCT_IS_DEREF)
                | ($value & STRUCT_IS_METHOD)
                | ($value & STRUCT_IS_VARDECL);
        }

        # Tag ExpressionStatement alt 1 (ExpressionList) — when a single
        # expression matches both Expression and ExpressionList, prefer
        # Expression (simpler parse). The list form is only correct when
        # there are actual commas or fat arrows.
        if ($rule_name eq 'ExpressionStatement' && $alt_idx == 1) {
            return STRUCT_IS_LIST
                | ($value & STRUCT_IS_BLOCK)
                | ($value & STRUCT_IS_HASH)
                | ($value & STRUCT_IS_CALL)
                | ($value & STRUCT_IS_VARDECL);
        }

        # Tag UseDeclaration with imports (alt 1) as is_call to prefer
        # it over the shorter alt 0 (without imports). This prevents
        # `use Foo 'bar'` from fragmenting into `use Foo` + `'bar'`.
        if ($rule_name eq 'UseDeclaration' && $alt_idx == 1) {
            return STRUCT_IS_CALL;
        }

        # ParenExpr alt 1 (ExpressionList) — tag as list so add() prefers
        # the simpler Expression parse (alt 0) for single expressions.
        if ($rule_name eq 'ParenExpr' && $alt_idx == 1) {
            return STRUCT_IS_LIST;
        }

        # Boundary rules: clear all structural tags
        if ($rule_name eq 'ParenExpr'
            || $rule_name eq 'ArrayConstructor') {
            return 0;
        }

        # Statement boundaries: preserve is_block/is_hash for disambiguation
        # of nested empty {} (Block vs HashConstructor). Also preserve
        # is_call and is_list for their existing uses.
        if ($rule_name eq 'StatementList'
            || $rule_name eq 'Program') {
            return ($value & STRUCT_IS_BLOCK)
                 | ($value & STRUCT_IS_HASH)
                 | ($value & STRUCT_IS_CALL)
                 | ($value & STRUCT_IS_LIST);
        }

        # Other rules: pass through all tags from value
        return $value & (
            STRUCT_IS_BLOCK | STRUCT_IS_HASH | STRUCT_IS_CALL  | STRUCT_IS_LIST  |
            STRUCT_IS_DEREF | STRUCT_IS_METHOD | STRUCT_IS_BINOP | STRUCT_IS_VARDECL
        );
    }
}
