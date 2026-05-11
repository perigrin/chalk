# Precedence semiring: named-unary level (perlop L10)

**Status:** Plan, not executed. Read-only investigation done 2026-05-11.

**Goal:** Teach the Precedence semiring that `defined`, `exists`, `ref`,
`scalar`, etc. are named-unary operators at perlop L10, so the parser
disambiguates `defined $h{key}` to `Defined(Subscript($h, key))` directly
instead of producing the wrong `Subscript(Call(defined, [$h]), key)` shape
that `_fix_postfix_chain.subscript_over_builtin` patches up.

**Success criterion:** the existing TODO subtests in
`t/bootstrap/precedence-spec.t` for `defined $h{key}`, `exists $h{key}`,
`defined $h->{key}`, and `!exists $h{key}` (the four covering the L2 (->)
vs L10 (named-unary) and stacking patterns) pass without TODO. The
`_fix_postfix_chain.subscript_over_builtin` counter drops to zero on the
five Bootstrap-partial files where it currently fires (Earley.pm 547,
Desugar.pm 60, ConciseTree/Actions.pm 36, Context.pm 24, etc.).

## Current state

### Grammar admits both derivations

`defined $h{key}` parses two ways via the grammar in `docs/chalk-bootstrap.bnf`:

1. **Right (perlop-correct):** `CallExpression(defined, [Subscript($h, key)])`
   via `CallExpression ::= QualifiedIdentifier WS ExpressionList`, where the
   `ExpressionList` is the inner subscript.

2. **Wrong (current winner):** `Subscript(CallExpression(defined, [$h]), key)`
   via `Subscript ::= Expression _ /\{/ _ Expression _ /\}/`, where the
   target Expression is `CallExpression(defined, [$h])`.

Nothing in the filter stack rejects derivation 2. FilterComposite picks one
(currently the wrong one), and `_fix_postfix_chain.subscript_over_builtin`
rewrites it post-parse.

### Precedence semiring's existing mechanism

`lib/Chalk/Bootstrap/Semiring/Precedence.pm` already knows how to assign
conceptual precedence levels to expression rules via `$EXPR_LEVELS`:

  - `PostfixExpression` → -2 (tighter than any binary op)
  - `UnaryExpression`   → -1
  - `TernaryExpression` → 100 (looser than any binary op)
  - `AssignmentExpression` → 101

It uses these to reject things like `($a && $b)->foo()` (BinaryExpression
at level 10 cannot be a PostfixExpression target).

### What's missing

The semiring has NO concept of "this `CallExpression` is actually a named-unary
operator at L10." It treats all `CallExpression`s uniformly via `_complete_prec`:

```perl
# (current code)
# Other rules: pass through value, clear operator info
return $self->one();
```

So a `CallExpression(defined, [$h])` completes with no level information,
and the outer `Subscript` doesn't see it as a wrong-precedence target.

## Implementation plan

### Step 1: extend `PrecedenceTable.pm` with a named-unary table

```perl
# lib/Chalk/Grammar/Perl/PrecedenceTable.pm
my @NAMED_UNARY = qw(
    defined exists ref scalar length chr ord
    keys values each delete substr sprintf join split
    abs int hex oct sqrt sin cos exp log
    lc uc lcfirst ucfirst quotemeta
    fileno tell wantarray caller
);

# perlop L10 sits between binary-op levels 0..14 and assignment 100.
# Use level 50 to leave room. assoc='nonassoc' per perlop (named unary
# operators do not chain: `defined defined $x` is a syntax error).
sub named_unary_level() { return 50; }
sub named_unary_assoc() { return 'nonassoc'; }

my %_named_unary_lookup;
my $_named_unary_built = false;
sub _build_named_unary_lookup() {
    return if $_named_unary_built;
    $_named_unary_lookup{$_} = 1 for @NAMED_UNARY;
    $_named_unary_built = true;
}

sub is_named_unary($name) {
    _build_named_unary_lookup();
    return exists $_named_unary_lookup{$name};
}
```

**Source for the list:** `PREFIX_BUILTINS` in `Actions.pm:29` is the closest
existing inventory. Cross-check against perlop's "Named Unary Operators"
section. Some items in `PREFIX_BUILTINS` (like `delete`, `keys`, `values`)
are *also* list operators in some contexts — for the precedence semiring,
treat them as named-unary uniformly (the perlop table doesn't distinguish).

### Step 2: extend `Precedence.pm` to detect named-unary `CallExpression`

The Precedence semiring sees scan events with `matched_text`. When the
`QualifiedIdentifier` rule scans `defined` AND the `CallExpression` rule is
predicted, we can mark the level.

The cleanest plumbing: at the `QualifiedIdentifier` scan, check if the
matched text is named-unary AND `CallExpression` is in the `predicted`
hash. If so, return a Context with level=50, assoc='nonassoc',
is_operator=true (so the multiply path treats it like an operator).

```perl
# In _scan_multiply, add a branch BEFORE the BinaryOp/AssignOp case:
if ($rule_name eq 'QualifiedIdentifier'
        && Chalk::Grammar::Perl::PrecedenceTable::is_named_unary($matched_text)) {
    # Are we inside a CallExpression?
    my $predicted = $right->annotations()->{predicted} // {};
    my $in_call = ref($predicted) eq 'HASH'
        ? exists $predicted->{CallExpression}
        : $predicted->('CallExpression');
    if ($in_call) {
        my $nu_level = Chalk::Grammar::Perl::PrecedenceTable::named_unary_level();
        my $nu_assoc = Chalk::Grammar::Perl::PrecedenceTable::named_unary_assoc();
        return _intern(true, $nu_level, $nu_assoc, true, $matched_text);
    }
}
```

But wait — `_scan_multiply` only receives `$rule_name` and `$matched_text`,
not the full `$right` Context. Need to refactor to pass the predicted hash
through, or read it inside `multiply` before delegating to `_scan_multiply`.
**This is one concrete plumbing change.**

### Step 3: extend `_complete_prec` to assign the level on CallExpression
completion

When `CallExpression` completes and the scan has marked it as a named-unary
context, propagate that level to the parent. Reuse the `is_operator` flag
for this — it already triggers the precedence-rejection logic in
`_prec_multiply`.

### Step 4: verify the wrong derivation is rejected

`Subscript(CallExpression(defined, [$h]), key)` should be killed by the
existing `_prec_multiply` when:
- The Subscript scans `{` with the named-unary `CallExpression` as its
  accumulated left operand (level=50).
- The Subscript bracket boundary already rejects `level >= 0` targets
  (Precedence.pm:200-203 for `[`/`{` and PostfixDeref).

Actually — re-reading the existing code: the bracket boundary check at
lines 200-203 ALREADY rejects targets with `level >= 0`. If we mark the
named-unary `CallExpression` with level=50, that check should fire and
reject the wrong derivation. **No new rejection logic needed in step 4 if
the existing bracket-boundary check works.**

### Step 5: test and audit

1. Run `t/bootstrap/precedence-spec.t` — the four named-unary L10 TODOs
   should pass without TODO.
2. Run `t/bootstrap/precedence-spec-arith-bit.t` and the other 4 cluster
   files — confirm no regressions.
3. Run `t/bootstrap/perl-actions-fixup-instrumentation.t` — confirm
   instrumentation still in place.
4. Run the broader `t/bootstrap/` suite (~215 files) — confirm no
   regressions. Expected concern: the 6 pre-existing failures in
   `perl-actions-fixup.t` should remain at 6.
5. Re-run `script/chalk-fixup-audit lib/Chalk/Bootstrap` — the
   `_fix_postfix_chain.subscript_over_builtin` counter should drop on the
   files that previously triggered it. Document the delta as an addendum
   to `docs/plans/2026-05-09-fixup-audit-baseline.md`.

## Risks

1. **Naming collision with subscript-style brackets.** `delete $h{k}` is
   `delete` (named-unary) wrapping a subscript. `defined $h{k}` likewise.
   But `keys %h` is named-unary wrapping a hash variable directly, no
   subscript. The level=50 mark must propagate cleanly through these.

2. **Cross-context named-unary tokens.** `length` can also be used as a
   list-operator-like form: `length $a, $b` is `(length $a), $b`, NOT
   `length($a, $b)`. The `CallExpression ::= QualifiedIdentifier WS ExpressionList`
   alternative would parse `length $a, $b` as `length($a, $b)`. The
   precedence change might force `length $a, $b` to parse as just
   `length $a` followed by a stray `, $b` — which IS perlop-correct but
   may break existing parses we currently accept. Audit before deletion.

3. **`$predicted` hash availability at QualifiedIdentifier scan.** Need
   to verify Earley actually sets `predicted` on `QualifiedIdentifier`
   scan Contexts. TypeInference reads it during `Atom` completion, but
   that's a different rule. Read `lib/Chalk/Bootstrap/Earley.pm` to
   confirm scan-Context plumbing.

4. **Walker still runs.** The walker should detect zero
   `subscript_over_builtin` fires after the fix and become deletable for
   that branch. But other branches (`subscript_over_unary`,
   `method_over_deref`) cover other ambiguity classes; don't delete the
   walker entirely until ALL its branches are zero on Bootstrap.

## Estimated cost

- Step 1 (named-unary table): 30 min
- Step 2 (semiring scan-time detection + plumbing): 1-2 hours
- Step 3 (complete-time propagation): 30 min
- Step 4 (verify rejection works): 30 min
- Step 5 (test + audit): 1 hour
- Risk investigation (especially #2 and #3): 1-2 hours

Total: 4-6 hours of focused work, likely 2 sessions.

## Cross-references

- Spec test (RED step done): `t/bootstrap/precedence-spec.t`,
  4 TODO subtests for L2 vs L10
- Walker code that this would obsolete:
  `lib/Chalk/Bootstrap/Perl/Actions.pm` `_fix_postfix_chain.subscript_over_builtin`
  branch (line ~519-555)
- Audit baseline: `docs/plans/2026-05-09-fixup-audit-baseline.md`
- Architectural framing: this is the same "filter-gap merge" class
  documented across the 2026-05-10 audit addenda.
