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
        STRUCT_IS_BLOCK    => 1,
        STRUCT_IS_HASH     => 2,
        STRUCT_IS_CALL     => 4,
        STRUCT_IS_LIST     => 8,
        STRUCT_IS_DEREF    => 16,
        STRUCT_IS_METHOD   => 32,
        STRUCT_IS_BINOP    => 64,
        STRUCT_IS_VARDECL  => 128,
        STRUCT_IS_BARECALL => 256,
    };

    # Constants are accessed via fully-qualified names
    # (e.g. Chalk::Bootstrap::Semiring::Structural::STRUCT_IS_CALL)
    # to avoid depending on Exporter, which Chalk cannot compile.

    # Sentinel value outside the 0-255 valid bitfield range, marking dead parse paths.
    my $ZERO = -1;

    # zero() returns -1: the sentinel value outside the 0-255 valid bitfield range.
    # This marks a dead parse path.
    method zero() {
        return $ZERO;
    }

    # one() returns 0: the identity value with no bits set (valid, no structural tags).
    method one() {
        return 0;
    }

    # is_zero($value): true iff value is the sentinel -1.
    method is_zero($value) {
        return $value == $ZERO;
    }

    # _slot_val: extract the structural integer from an argument.
    # Accepts either a raw integer (direct semiring value) or a full Context
    # (when called from FilterComposite with the shared parse Context).
    # Falls back to one() (0) when no structural annotation is present.
    my sub _slot_val($val, $fallback) {
        return $fallback unless defined $val;
        # Context object: read from annotations->{structural}
        if (blessed($val) && $val->can('annotations')) {
            return $val->annotations()->{structural} // $fallback;
        }
        return $val;
    }

    method multiply($left, $right) {
        my $l = _slot_val($left,  $self->one());
        my $r = _slot_val($right, $self->one());

        # Scan event: right Context has annotations->{scan} = true.
        # Structural is transparent at scan time — pass through unchanged.
        if (blessed($right) && $right->can('annotations')
                && $right->annotations()->{scan}) {
            return $ZERO if $l == $ZERO;
            return $l;
        }

        # Complete event: right Context has annotations->{complete} = true.
        # Apply structural tagging based on the completed rule name.
        if (blessed($right) && $right->can('annotations')
                && $right->annotations()->{complete}) {
            return $ZERO if $l == $ZERO;
            my $rule_name = $right->annotations()->{rule_name};
            my $alt_idx   = $right->annotations()->{alt_idx};
            return $self->_complete_structural($l, $rule_name, $alt_idx);
        }

        # Propagate zero
        return $ZERO if $l == $ZERO;
        return $ZERO if $r == $ZERO;

        # Combine tags from both sides using bitwise OR
        return $l | $r;
    }

    # _complete_structural: apply structural bit-tagging for a completed rule.
    # Receives the accumulated left-side integer value and the rule metadata.
    # Receives the accumulated left-side integer value and the rule metadata.
    method _complete_structural($value, $rule_name, $alt_idx) {
        return $ZERO if $value == $ZERO;

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
        #
        # Reject postfix on bare-form CallExpression: per perlop, `foo @args->@*`
        # cannot deref the call's result without explicit parens around the call.
        # The bare-form CallExpression has no injected `()` boundary, so the
        # postfix has nothing to attach to.
        if ($rule_name eq 'PostfixDeref') {
            return $ZERO if $value & STRUCT_IS_BARECALL;
            return STRUCT_IS_DEREF | ($value & STRUCT_IS_BLOCK);
        }

        # Tag ALL Subscript completions with is_deref.
        # Arrow variants (alts 0-2): $f->($x), $f->[$i], $f->{$k}
        # Non-arrow variants (alts 3-4): $h[$i], $h{$k}
        # Both are dereference operations. Tagging them allows add() to
        # prefer CallExpression (is_call, no is_deref) over
        # Subscript(CallExpression, ...) (is_call + is_deref).
        # IS_BARECALL rejection same as PostfixDeref above.
        if ($rule_name eq 'Subscript') {
            return $ZERO if $value & STRUCT_IS_BARECALL;
            return STRUCT_IS_DEREF
                | ($value & STRUCT_IS_CALL)
                | ($value & STRUCT_IS_BLOCK);
        }

        # Tag CallExpression completions — preferred over bare Identifier.
        # Preserve is_block/is_hash from inner nonterminals so add() can
        # prefer CallExpression-with-Block over CallExpression-with-Hash.
        # Clear is_deref/is_method: CallExpression is a direct function call,
        # deref/method tags from arguments should not leak outward.
        #
        # IS_BARECALL marks alts WITHOUT injected `()` boundary (bare-form
        # list-op `foo ARGS`, `map BLOCK ARGS`, `map BLOCK`). Per perlop,
        # postfix `->` after a bare-form call cannot bind without explicit
        # parens around the call. Multiply rejects postfix-on-bare-call at
        # MethodCall/Subscript/PostfixDeref completion below.
        if ($rule_name eq 'CallExpression') {
            my $bare = ($alt_idx == 0) ? 0 : STRUCT_IS_BARECALL;
            return STRUCT_IS_CALL | $bare | ($value & STRUCT_IS_BLOCK);
        }

        # Tag MethodCall completions with parens (alts 0, 2) — preferred over
        # bare method access (alts 1, 3) so args aren't lost as separate stmts.
        # All MethodCall alts get is_method so add() prefers CallExpression
        # over MethodCall when both compete at the same PostfixExpression position.
        # IS_BARECALL rejection: per perlop, `foo @args->method()` cannot
        # method-call the bare-form call's result without explicit parens.
        if ($rule_name eq 'MethodCall') {
            return $ZERO if $value & STRUCT_IS_BARECALL;
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
        # IS_METHOD is intentionally cleared here: a MethodCall that appears
        # as an *argument* inside an ExpressionList should not propagate
        # its IS_METHOD tag outward. If it did, add() at a higher level
        # would see IS_METHOD+IS_CALL on the CallExpression containing the
        # list, triggering the "prefer non-method" rule and eliminating the
        # correct parse in favour of an incomplete one. IS_METHOD at a higher
        # level should only indicate that the outermost call is itself a
        # MethodCall (e.g. `push(@arr)->method()`), not that an argument
        # inside the call was a method call.
        if ($rule_name eq 'ExpressionList' && $alt_idx >= 1) {
            return STRUCT_IS_LIST
                | ($value & STRUCT_IS_BLOCK)
                | ($value & STRUCT_IS_HASH)
                | ($value & STRUCT_IS_CALL)
                | ($value & STRUCT_IS_DEREF)
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
            STRUCT_IS_DEREF | STRUCT_IS_METHOD | STRUCT_IS_BINOP | STRUCT_IS_VARDECL |
            STRUCT_IS_BARECALL
        );
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if $left == $ZERO;
        return $left  if $right == $ZERO;

        # Both valid: prefer is_call over non-call
        # CallExpression consumes more input than bare QualifiedIdentifier.
        my $left_call  = $left  & STRUCT_IS_CALL;
        my $right_call = $right & STRUCT_IS_CALL;

        # Both valid: prefer non-list over list (Expression vs ExpressionList).
        # Ranks ExpressionStatement alt-1 (ExpressionList) BELOW alt-0
        # (single Expression, even if that Expression is itself a CallExpression
        # with comma-separated args). The bare-list-statement form
        # `@a, @b;` remains supported as the fallback when alt-0 doesn't match.
        #
        # SKIPPED only when both sides have IS_METHOD-vs-IS_LIST competition
        # (one is_call has IS_METHOD, the other is_call has IS_LIST without
        # IS_METHOD): per perlop `,` (L21) binds looser than `->` (L2), so
        # the IS_LIST side is perlop-correct there and the IS_METHOD-prefer-
        # non-method rule below must fire instead.
        my $left_list   = $left  & STRUCT_IS_LIST;
        my $right_list  = $right & STRUCT_IS_LIST;
        my $left_method = $left  & STRUCT_IS_METHOD;
        my $right_method = $right & STRUCT_IS_METHOD;
        my $is_method_vs_list_competition = $left_call && $right_call
            && (($left_method && $right_list && !$left_list)
                || ($right_method && $left_list && !$right_list));
        if (!$is_method_vs_list_competition) {
            if ($left_list && !$right_list) {
                return $right;
            }
            if ($right_list && !$left_list) {
                return $left;
            }
        }

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
        # Bilateral: whichever side has IS_METHOD, the OTHER wins.
        # Per perlop, `->` (L2) binds tighter than `,` (L21), so when a
        # CallExpression-flavor derivation (IS_CALL only) competes with a
        # MethodCall-wrapping-call derivation (IS_CALL|IS_METHOD), the
        # CallExpression-flavor is perlop-correct.
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

        # Both valid: prefer is_hash over is_block.
        # A bare Block is not an expression, so when both Block and HashConstructor
        # produce valid parses, the hash interpretation is correct in expression
        # context (return { key => val }, $x = { ... }, f({ ... })).
        # Block is still correct in pure statement context, but there HashConstructor
        # typically doesn't produce a valid parse (semicolons inside { ; } break
        # ExpressionList, leaving Block as the only alternative).
        my $left_block  = $left  & STRUCT_IS_BLOCK;
        my $right_block = $right & STRUCT_IS_BLOCK;
        my $left_hash   = $left  & STRUCT_IS_HASH;
        my $right_hash  = $right & STRUCT_IS_HASH;
        if ($left_hash || $right_hash) {
            # When both are is_hash, prefer the one without is_block.
            # This resolves `{ {} }` where one derivation has inner HashConstructor
            # (pure is_hash) and another has trailing Block-wrapped hash
            # (is_hash + is_block).
            if ($left_hash && $right_hash) {
                if ($right_block && !$left_block) {
                    return $left;
                }
                if ($left_block && !$right_block) {
                    return $right;
                }
                # Both have is_hash and same block status — pick left
                return $left;
            }
            # One-sided: the hash side wins
            return $left_hash ? $left : $right;
        }

        # Both valid, neither is hash: prefer is_block if present.
        if ($left_block || $right_block) {
            if ($left_hash && !$right_hash) {
                return $left;
            }
            if ($right_hash && !$left_hash) {
                return $right;
            }
            # Both have is_block with same hash status — no structural preference.
            # Return arrayref so FilterComposite sees "Structural abstains" and
            # consults other semirings (Precedence, SemanticAction) for the verdict.
            return [$left, $right];
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

        # Both valid, no tag preference: return arrayref to signal abstention.
        # FilterComposite reads multi-element arrays as "no opinion," which lets
        # subsequent semirings or the tie-break handle disambiguation.
        return [$left, $right];
    }

    # slot_name: Structural reads/writes the 'structural' annotation slot.
    method slot_name() {
        return 'structural';
    }
}
