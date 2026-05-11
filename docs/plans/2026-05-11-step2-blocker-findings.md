# Step 2 implementation: blocker findings (2026-05-11)

**Status:** Investigation, partial implementation reverted. Step 2 work
paused for design rethink.

## What we tried

The subagent implementation (later reverted at HEAD) made two changes
to `lib/Chalk/Bootstrap/Semiring/Precedence.pm`:

1. In `multiply`, extract `predicted` from the scan Context and pass
   to `_scan_multiply`.
2. In `_scan_multiply`, when `rule_name == QualifiedIdentifier`,
   `matched_text` is named-unary, AND `CallExpression` is in
   `predicted`, return `_intern(true, 50, 'nonassoc', true, $matched_text)`.

A follow-on fix added a pass-through clause for `Atom`/`QualifiedIdentifier`
in `_complete_prec` when the value carries `is_operator=true` with
named-unary level — without this, the catch-all clears the marker
before it can reach the outer rules.

## What worked

- Detection fires correctly. With `DEBUG_PRECEDENCE=1`, the scan trace
  prints `PREC_NAMED_UNARY: defined level=50 assoc=nonassoc` for the
  expected token.
- The level propagates through `Atom` and `Expression` completions
  with the pass-through fix.
- The `PostfixExpression` rejection logic at `_complete_prec` line ~430
  fires and rejects derivations carrying level=50, as designed.

## What broke

After the pass-through fix, `defined $h{key}` no longer parses **at
all**. Both derivations are rejected:

- **Wrong derivation** `Subscript(CallExpression(defined, [$h]), key)`:
  rejected by PostfixExpression level<0 check, as intended.
- **Right derivation** `CallExpression(defined, [Subscript($h, key)])`:
  ALSO rejected by PostfixExpression level<0 check. The right
  derivation's CallExpression also carries level=50 (because that's
  what marks it as named-unary), and its PostfixExpression wrapper
  treats level=50 the same way it treats level=50-as-Subscript-target.

## The architectural issue

The current encoding treats `level=50` as a single semantic: "this
sub-expression is a named-unary call." That fires the
PostfixExpression rejection regardless of *why* the level=50 is
there:

- Case A (reject): `level=50` on the left side of `{` (Subscript
  scan boundary). The named-unary CallExpression is being used as
  a Subscript target → wrong.
- Case B (preserve): `level=50` on the value being wrapped by
  PostfixExpression. The named-unary CallExpression IS the
  PostfixExpression → correct.

The existing code's PostfixExpression check can't distinguish A from
B because both arrive at the same site with the same value level.

## Two design options

### Option B1: separate rejection site (recommended)

Instead of routing the rejection through PostfixExpression's
`expr_level < 0 && value_level >= 0` check, add an explicit check
at the `Subscript` bracket-boundary scan in `_scan_multiply`:

```perl
# Named-unary CallExpression cannot be a Subscript target.
# `defined $h{key}` must parse as defined(...{key}), not
# (defined $h){key}.
if ($rule_name eq 'Subscript' && $matched_text =~ /^[\[\{]$/
        && defined($existing->{level})
        && $existing->{level} == named_unary_level()
        && $existing->{is_operator}) {
    return $self->zero();
}
```

This rejects only at the Subscript-target site, not at PostfixExpression
wrapping. The right derivation's `PostfixExpression(CallExpression(...))`
sees the level=50, but PostfixExpression's existing check for
`expr_level < 0 && value_level >= 0` would still fire incorrectly.

So we also need PostfixExpression completion to NOT reject when
value_level == named_unary_level (i.e., the value IS a named-unary,
which is a legitimate PostfixExpression):

```perl
if ($expr_level < 0 && defined($value->{level}) && $value->{level} >= 0) {
    # Allow named-unary CallExpression as a valid PostfixExpression.
    # The rejection of named-unary-as-Subscript-target happens at
    # the Subscript bracket-boundary scan, not here.
    return _intern(true, $expr_level, $expr_assoc, false)
        if $value->{level} == named_unary_level();
    return $self->zero();
}
```

### Option B2: separate level for "target carries named-unary"

Use TWO levels: `50` for "I am named-unary" (CallExpression
completion), `51` for "my target is named-unary" (set when Subscript
admits a named-unary CallExpression as a target). PostfixExpression
rejects level=51 but allows level=50. This adds another level value
and another marker; cleaner conceptually but more state to track.

## Recommendation

**Option B1** — same number of levels, just relocate the rejection.
Smaller diff, clearer intent: "Subscript explicitly rejects
named-unary targets, PostfixExpression allows named-unary to BE the
expression."

## Cost estimate

- Restore the reverted Step 2 changes: 5 min
- Add Subscript-target check in `_scan_multiply`: 15 min
- Add PostfixExpression named-unary-allowed clause: 15 min
- Run all six precedence-spec files + semiring-precedence.t + the L2
  TODOs verification: 15 min
- Total: 50 min

## Open question for Option B1

The `PostfixExpression` `expr_level < 0 && value_level >= 0`
rejection logic exists to kill `($a && $b)->foo()` style wrong parses
(BinaryExpression cannot be a PostfixExpression target). If we
exempt level=50 from that rejection, we need to confirm that no
non-named-unary path produces level=50 — otherwise we open a new
gap. Cross-reference: only `_scan_multiply`'s named-unary detection
emits level=50, and only PrecedenceTable::named_unary_level()
returns 50. The level is unique to this purpose. Safe.

## Cross-references

- The original plan: `docs/plans/2026-05-11-precedence-named-unary-plan.md`
- The `exists` investigation: `docs/plans/2026-05-11-exists-precedence-investigation.md`
- The RED tests: `t/bootstrap/precedence-spec.t` TODO subtests for L2 vs L10
- The reverted commit's diff: see git reflog / `git log fixup-audit-baseline`
