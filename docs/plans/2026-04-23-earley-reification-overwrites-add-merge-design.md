# Earley Reification Overwrites `add`-Merged Chart Values — Design Note

**Status:** Investigation / design — no code changes yet.

**Author:** perigrin + Claude, 2026-04-23.

**Context:** Commits `2c066ae8` (preserve both derivations in `add`) and
`eafd6cc3` (tag `add` wrapper with `annotations->{ambiguous}`) established
visibility of ambiguity at the Boolean semiring boundary. They were intended
to unblock the ambiguity corpus described in
`docs/architecture/ambiguity-classes.md` Invariant #1 ("Grammar + Boolean
produces ambiguity ONLY in these seven classes").

## Finding

The Boolean semiring correctly detects ambiguity and tags merge wrappers, but
those wrappers are **not reachable from the Context returned by
`parse_value`**. On `1 + 2 * 3;` the instrumented parser shows:

- `Boolean::add` is called **40** times with two non-zero derivations.
- Each such call produces a Context tagged `annotations->{ambiguous} = true`.
- Walking the returned Context tree (143k nodes, 61k two-child) finds
  **zero** nodes with that annotation.

The tagged wrappers are created, inserted into chart slots via
`_chart_set(..., $merged_value)`, and then **overwritten** by subsequent
Earley activity on the same slot.

## Root cause

In `lib/Chalk/Bootstrap/Earley.pm` line 590 (and the analogous patterns
around lines 588-590, 1161), the reification step after completion performs:

```perl
my $complete_ctx = $self->_make_complete_context(
    $value, $rule_name, $alt_idx, $pos, $origin
);
my $completed_value = $semiring->multiply($value, $complete_ctx);
$chart[$pos][$core_id][($pos - $origin)] = $completed_value;    # unconditional
```

The assignment is a raw chart write, not a merge. When the same slot has
already been populated by a previous `add`-merge (producing an ambiguous
wrapper), that wrapper is discarded — `$completed_value` wraps the current
`$value` only, with no reference to the previously-merged alternative.

Other chart writes in the same file *do* go through `_chart_set` after
`add`-merging against the existing value (lines 938/940, 1226/1232,
1280/1282, 1357/1359, 1495/1497), each guarded by a `_chart_has` check.
The reification path at 590 is the outlier — it writes unconditionally.

## Why this wasn't caught earlier

Before commit `2c066ae8`, Boolean's `add($left, $right)` silently returned
`$left` when both were non-zero. The reification overwrite was invisible
because `add` itself discarded ambiguity. The two recent commits moved the
ambiguity-hiding one level up (into the Earley driver), surfacing a
latent issue that had been masked.

This is consistent with the pre-existing `try { ... $semiring->add(...) }
catch { die "Ambiguity in..." }` blocks at lines 634, 937, 1220, 1275, 1350,
1487 — they exist because filtering semirings' `add` implementations were
expected to die on genuine ambiguity. Boolean was the only semiring whose
`add` *couldn't* die, which is why Boolean-specific visibility was needed
in the first place.

## What this blocks

- The ambiguity corpus (`t/bootstrap/grammar-ambiguity-corpus.t`) cannot
  run meaningful assertions against `ambiguity_sites()` until the
  reification path preserves merged wrappers.
- Invariant #1 in `docs/architecture/ambiguity-classes.md` cannot be
  mechanically verified.
- `classify_site()` has no real inputs to classify.

## What this does **not** block

- `AmbiguityAnalysis.pm` (the walker + classifier stub) is correct as
  written; it just has nothing to find.
- The seven ambiguity classes documented in
  `docs/architecture/ambiguity-classes.md` are a correct specification.
  The issue is in surfacing them, not identifying them.

## Proposed fix (sketch — not a commitment)

At line 590, gate the write the same way other chart writes are gated:

```perl
my $completed_value = $semiring->multiply($value, $complete_ctx);
my $existing = $chart[$pos][$core_id][($pos - $origin)];
if (defined $existing) {
    $completed_value = $semiring->add($existing, $completed_value);
}
$chart[$pos][$core_id][($pos - $origin)] = $completed_value;
```

Concerns to verify before committing to this shape:

1. **Idempotence under re-entry.** The reification step may run multiple
   times on the same slot during agenda processing. If it does, each
   re-entry would `add` the same `$completed_value` against itself,
   producing ever-deeper ambiguous wrappers. Need to confirm whether
   re-entry is possible and, if so, whether there's a canonical
   "already-reified" marker.

2. **Filtering semirings' `add` dies on genuine ambiguity.** The existing
   `try/catch` blocks turn that into useful diagnostics. A new `add`
   call at line 590 must either be inside its own `try/catch` with a
   context-appropriate message, or proven to never fire for filtering
   semirings (e.g. because they always reject one path via zero before
   reaching this point).

3. **Performance.** 40 additional `add` calls per 9-char parse becomes
   many more at scale. Boolean `add` is cheap, but FilterComposite
   `add` threads through five semirings. Measure before/after on a
   representative input.

4. **Leo interaction.** The Leo-resolved completion at line 1265-1284
   already handles merge correctly. Need to verify the 590 path and
   the Leo path don't stack their merges in a way that double-counts.

## Alternative approaches considered

### A. Hash-cons Context so ambiguous wrappers survive by identity

Rejected: Context is not currently hash-consed, and introducing it for
this alone is a large architectural change. The problem is write-order
at the chart level, not value identity.

### B. Move `add`-merge responsibility into the semiring's `multiply`

Rejected: violates the semiring algebra. `multiply` is sequential
composition; `add` is alternative composition. They are not
interchangeable, and filtering semirings would behave incorrectly if
`multiply` tried to merge alternatives.

### C. Post-process the chart after parse to recover merge history

Rejected: requires persisting pre-overwrite values somewhere. Either
means a shadow chart (storage overhead) or structural changes to chart
shape. The fix-at-write-site approach is simpler.

### D. Defer the corpus work until the MOP migration lands

Rejected: the MOP migration and ambiguity corpus are orthogonal. MOP
is about how IR is constructed; ambiguity is about what the grammar
admits. Blocking one on the other creates artificial serialization.

## Next steps

1. Review this note — confirm the diagnosis is right and the proposed
   fix sketch is the direction we want.
2. If approved, write the fix with all four concerns above investigated
   first, each recorded in the commit message or a follow-up note.
3. After the fix, re-enable `t/bootstrap/grammar-ambiguity-corpus.t`
   with the precedence case as the first TDD cycle.
4. Proceed with one class per cycle as originally planned.

## Synthetic grammar verification

To rule out the possibility that Earley was producing spurious merges
(inflating the 40 count on `1 + 2 * 3;` beyond the grammar's real
ambiguity), five tiny synthetic grammars were exercised with
hand-computed expected merge counts. Results are now locked in as
assertions in `t/bootstrap/ambiguity-synthetic.t`:

| Grammar | Shape | Inputs | Expected merges | Observed |
|---|---|---|---|---|
| `E ::= E '+' E \| /\d+/` | both-recursive, ambiguous | `1`, `1+2`, `1+2+3`, `1+2+3+4` | 0, 0, 1, 4 (Catalan-C(n-1)) | match |
| `E ::= N '+' E \| N` | right-recursive, unambiguous | same | 0, 0, 0, 0 | match |
| `E ::= E '+' N \| N` | left-recursive, unambiguous | same | 0, 0, 0, 0 | match |
| `S ::= E ';' ; E ::= E '+' E \| /\d+/` | wrapped ambig | `1;`, `1+2;`, `1+2+3;`, `1+2+3+4;` | 0, 0, 1, 4 | match |
| `S ::= E \| E` | duplicate top-level alternatives | `42` | n/a (see note) | 0 |

The first four grammars confirm Earley invokes `add` **exactly** where
nested-nonterminal ambiguity occurs — no inflation, no omission. The
40-merge count on `1 + 2 * 3;` in the Perl grammar is therefore real
ambiguity from the grammar itself, not parser pathology.

### Two-level distinction discovered via G5

The final grammar surfaced a second, **separate** form of ambiguity that
Boolean's `add` does not observe at all:

- **Top-level start-rule alternative selection** — different alternatives
  of the start rule land in different chart slots (different `core_id`,
  because `core_id` encodes `alt_idx`). They never converge on a single
  slot, so `add` is never invoked. `_run_parse`'s final-slot extraction
  iterates alternatives at lines 897/977/992 and returns the first one
  that completes, silently dropping later alternatives.

- **Nested nonterminal ambiguity** — two derivations of the same
  `(rule, alt, span)` land in the same chart slot. This is what `add`
  merges and what our `annotations->{ambiguous}` tagging is designed to
  expose.

The seven ambiguity classes documented in
`docs/architecture/ambiguity-classes.md` are all of the nested variety.
The reification-overwrite at line 590 discards their merges; G5's
top-level-alt case is out of scope for this investigation but worth
keeping recorded because any future refactor that changes the first-match
extraction behavior may make it visible, and we want that change to be
deliberate rather than accidental.

## Artifacts from the investigation

- Diagnostic harness ran `Boolean::add` with a call-counter monkey-patch
  over `42;`, `1 + 2;`, `1 + 2 * 3;` inputs. Call counts:
  1 / 20 / 40 (all both-non-zero).
- Context-tree walk over the same inputs: 3702 / 31606 / 143222 total
  nodes; 1589 / 13621 / 61749 two-child; 0 with `ambiguous`
  annotation on any input.
- Ad-hoc diagnostic tests were not committed (deleted after investigation).
- Assert-based regression guard committed as `t/bootstrap/ambiguity-synthetic.t`.
