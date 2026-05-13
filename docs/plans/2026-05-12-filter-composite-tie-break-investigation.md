# FilterComposite tie-break investigation (task #4)

**Status:** Read-only investigation, 2026-05-12 night. Includes both static
analysis (subagent) and empirical measurement (probe script run on
IR/MOP/Grammar corpus).

## The question

`lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` line 304-337 implements
`add()` for the composite semiring. When two derivations arrive at the same
chart cell:

1. `_filter_compare($left, $right)` runs each filtering semiring's `add()`.
2. The first semiring to express a preference wins (first-wins early return).
3. If ALL semirings return `'neither'`, FilterComposite **silently picks
   `$left`** as a deterministic tie-break (lines 317-323).

The comment at line 319-321 calls this out as "a grammar-audit red flag —
ambiguity that no documented class claims to resolve." The architectural
complaint: composition shouldn't have an opinion. When all four filters
admit both, the result should be ambiguity surfaced (parse error or
explicit ambiguous-IR node), not a silent pick.

This investigation answers: how often does the silent-pick path actually
fire on real Chalk source, and what's the right architectural response?

## Headline empirical finding

**0 unresolved ties across the entire 105-file IR/MOP/Grammar corpus.**

The silent left-pick path of FilterComposite is **dead code** on the
audited corpus. The architectural concern is real but its observable
impact is currently zero. The 251,569 post-parse fixup fires across the
corpus are NOT caused by the FilterComposite tie-break.

Probe script (saved at `/tmp/tie-corpus.pl`):

```perl
$ENV{CHALK_COUNT_FILTER_TIES} = 1;
# ... build parser ...
for each file:
    flush_tie_log
    parse file
    count entries with slot eq 'unresolved'
```

Output:
```
# Totals
  unresolved (silent left-pick): 0
```

No per-file lines printed (zero ties on every file).

## Static analysis — what would trigger 'neither'?

The silent-pick path requires ALL three annotation semirings to fail to
express a preference:

1. **Precedence**: `_same_value($li, $ri)` returns true iff both derivations
   carry the IDENTICAL hash-cons'd precedence object. Otherwise Precedence's
   `add()` is invoked, which always returns one of its two inputs (per
   `Precedence.pm:450-501`, every return path returns `[$left]` or
   `[$right]`). Hash-cons identity means the result is always identity-equal
   to one input, so Precedence ALWAYS expresses a preference when invoked.

2. **TypeInference**: Always bypassed by the `next if $slot eq 'type'` guard
   at line 234. TI disambiguates exclusively via `multiply` (returning zero),
   not via `add`. TI is structurally unable to express a preference in
   `_filter_compare`.

3. **Structural**: `_same_value($li, $ri)` returns true iff both derivations
   have the IDENTICAL structural integer. Otherwise `Structural.add()` is
   invoked. Structural has 9 explicit preference rules; only the catch-all
   `return $left | $right` at line 392 produces a value matching neither
   input. That catch-all requires a specific bit-pattern combination that's
   rare given the preference rules.

So 'neither' fires when:
- (a) Both derivations have identical precedence AND identical structural
  context — both filter slots skipped by `_same_value`. Two derivations
  truly indistinguishable from the filter layer's perspective.
- OR (b) Structural's catch-all returns a new OR value — extremely rare
  given the 9 preference rules.

The empirical 0-count says neither (a) nor (b) happens on the IR/MOP/Grammar
corpus.

## Why the post-parse fixups exist if 'neither' never fires

The 251,569 fixup fires across the corpus (mostly walker entries, with 130
real transforms after the per-branch decomposition) are caused by a
DIFFERENT mechanism. Specifically: at sub-rule chart cells where two
derivations DO have distinct annotations, Structural picks a winner, but
the winner is wrong because of HOW Earley's chart-merge happens — not
WHETHER it picks.

The 2026-05-12 `peel_builtin` investigation documented one example of this:
`push @arr, $obj->method()` produces two derivations at the
PostfixExpression sub-level. Structural distinguishes them (is_call vs
is_call+is_method) and DOES pick a winner — but the winner is the wrong
derivation (B, the "MethodCall wraps push" shape) because the chart
construction admits B before A and Structural's preference for is_call
(without method) over is_call+is_method picks the WRONG one. The helper
`_push_methodcall_inward.peel_builtin` then correctly rebuilds it as A.

This is task #4-adjacent but distinct. **Fixing the silent-pick has zero
effect on the post-parse fixup fires.**

## What if 'neither' became an error?

Per static analysis: zero new PARSE_FAILs on the audited corpus, because
the path never fires. The change would be a no-op for this corpus.

However, the corpus is the IR/MOP/Grammar subset (105 files); the larger
Bootstrap corpus has not been measured. Bootstrap contains gnarlier code
patterns (per the 2026-05-10b/2026-05-12 audit findings). Whether 'neither'
fires on Bootstrap is an open question deferred to when the C2 perf-gate
clears.

## Recommendation

**Option (c): keep the silent pick, surface ties in audit/diagnostic output.**

Reasoning:

1. **Empirically, 'neither' fires 0 times on the audited corpus.** Changing
   to error or Ambiguous-IR-node would have zero effect today.

2. **The 251K-fire post-parse fixup mass is NOT caused by 'neither'.** The
   fixups arise from chart-merge ordering at sub-rule levels where
   Structural DOES pick a winner. Retiring 'neither' wouldn't reduce
   walker fires.

3. **Option (a) would break parses if Bootstrap turns out to fire 'neither'.**
   Currently we don't know. Erroring on a path that has fired 0 times in
   measured cases risks regression on unmeasured cases.

4. **Option (b) Ambiguous-IR-node requires survivor-list semantics.** The
   FilterComposite.pm comment at lines 290-303 acknowledges the original
   design intended survivor lists, deferred because the Earley parser
   stores one value per chart item. Implementing survivor lists is a deep
   parser change with multi-session risk.

5. **Option (c) is mostly already implemented.** `CHALK_COUNT_FILTER_TIES=1`
   produces a `tie_log` accessible via the FilterComposite's `tie_log()`
   method. The `script/chalk-fixup-audit` script doesn't currently query
   it; adding that query (~5 lines) gives full visibility without
   architectural change.

## Concrete follow-up for Option (c)

Single small change to `script/chalk-fixup-audit`:

```perl
# Before the per-file loop, set the env var:
$ENV{CHALK_COUNT_FILTER_TIES} = 1;

# Before each parse, flush the tie log (if accessible):
my $sem = $parser->semiring();
$sem->flush_tie_log() if $sem->can('flush_tie_log');

# After each parse, count unresolved entries:
my $unresolved = 0;
if ($sem->can('tie_log')) {
    my $log = $sem->tie_log();
    $unresolved = scalar grep { $_->{slot} eq 'unresolved' } $log->@*;
}

# Add to per-file output and totals
push @per_file, [$file, $status, { %$counts, _ties_unresolved => $unresolved }];
```

Cost: ~30 minutes of work. Output: every audit run reports tie counts;
audit doc tracks ties as another retirement metric (target: 0). When
'neither' DOES fire (e.g., on a future Bootstrap audit), we'll see it in
the audit row immediately and can investigate the specific input.

## Cross-references

- The architectural complaint: `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm`
  lines 290-323
- Original design intent (survivor-list): same file, lines 290-303 comment
- Plumbing for tie_log: `flush_tie_log`, `tie_log` methods on FilterComposite
- `peel_builtin` investigation (separate concern):
  `docs/plans/2026-05-12-peel-builtin-investigation.md`
- Architectural framing precedent (precedence-level marker fights):
  `docs/plans/2026-05-12-list-operators-as-predeclared.md`
- Probe script: `/tmp/tie-corpus.pl` (this session)
- Probe output: `/tmp/tie-corpus-output.txt` (single-line "0 unresolved")

## Anomalies

1. **TI's `add()` is dead code in `_filter_compare`.** The `next if $slot eq
   'type'` guard at line 234 means TI's `add()` is never invoked from the
   tie-break path. If TI's `add()` has disambiguation logic, it's unused
   for filter-compare purposes. Worth confirming with TI's maintainer that
   this is intentional (TI disambiguates via `multiply`-zero, per the
   comment at lines 230-233).

2. **Two distinct entry types in tie_log.** The probe carefully filters by
   `slot eq 'unresolved'` because the tie_log can also contain
   `{semiring => $sr, slot => $slot_name}` entries for mid-loop non-verdict
   cases (Structural synthesizes OR or Precedence returns multi-element).
   The investigation shows zero of EITHER type on the audited corpus.

3. **The `peel_builtin` problem is architecturally separate from this.**
   Earlier framing in `2026-05-12-peel-builtin-investigation.md` referred
   to "Option C: fix the chart-merge artifact directly (open task #4
   territory)." This is misleading — task #4's silent-pick is at the
   inter-derivation merge level (cross-rule chart cells); peel_builtin's
   filter-gap merge happens at PostfixExpression's sub-level where
   Structural DOES pick a winner. The two share the framing of "filter
   layer doesn't catch the wrong derivation" but the mechanisms differ.

   **Implication:** Option C in the peel_builtin investigation should be
   re-named "investigate the chart-merge ordering at PostfixExpression
   sub-levels" and treated as ITS OWN architectural concern, NOT a
   sub-task of #4.
