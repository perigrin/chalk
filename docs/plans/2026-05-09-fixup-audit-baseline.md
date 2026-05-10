# Fixup Audit — 2026-05-09 Baseline

**Purpose:** Establish a measurable baseline for filter-stack
incompleteness in Chalk's parser. Every disambiguation fixup that
fires during a parse is evidence that the filter-stack
(Boolean → Precedence → TypeInference → Structural semirings) failed
to reject the wrong derivation before SemanticAction constructed
values from it. Per the architectural framing recorded in
`docs/plans/2026-04-24-semiring-contract-drift.md` (2026-05-09
addendum, added by this commit), the filter stack is "complete" iff
zero fixups fire on the corpus.

**Branch:** `fixup-audit-baseline`. Commit produces this baseline doc
from `script/chalk-fixup-audit` output. The script and instrumentation
landed on `pu` as commit `dc92cb61`.

## How the audit was produced

```bash
# Build the corpus (this baseline excludes lib/Chalk/Bootstrap/, where
# audit cost is bound by parse cost on large files — see "Why
# Bootstrap is excluded" below).
find lib/Chalk/IR lib/Chalk/MOP lib/Chalk/Grammar -name '*.pm' | sort > /tmp/corpus.txt

# Run the audit
script/chalk-fixup-audit lib/  # (or via the inline form used to produce this baseline)
```

The audit script resets the per-file fixup counts before each parse,
parses the file through the full Earley pipeline (Boolean +
Precedence + TypeInference + Structural + SemanticAction), captures
the per-file fixup-fire count, and accumulates totals.

## Headline numbers

- **Files audited:** 105
  (lib/Chalk/IR/*.pm + lib/Chalk/MOP/*.pm + lib/Chalk/Grammar/*.pm)
- **Files parsed cleanly (PARSE_OK):** 105 / 105
- **Files with zero fixups fired:** 0 / 105
- **Files with fixups fired:** 105 / 105

**Every file in the corpus triggers at least one fixup.** The
filter stack is incomplete for every Perl-subset file in this
corpus today.

## Total fixup fires across corpus

| Fixup | Total fires | Notes |
|---|---:|---|
| `_fix_postfix_chain` | 247,355 | The PostfixDeref/MethodCall chain-shape ambiguity |
| `_fixup_stmts` | 2,594 | Split-token reconstitution (`return X` → ReturnStmt etc.) |
| `_fix_postfix_chain_deep` | 798 | Recursive walker over `_fix_postfix_chain` for nested constructs |
| `_push_methodcall_inward` | 727 | MethodCall wrapping wrong invocant (push/builtin wrappers) |
| `_push_deref_inward` | 95 | PostfixDeref wrapping wrong target (Return/Unwind/builtin wrappers) |

**Total fires:** 251,569

## Hot-spot files (top 10 by `_fix_postfix_chain`)

| File | `_fix_postfix_chain` | All fixups |
|---|---:|---:|
| `lib/Chalk/IR/Serialize/JSON.pm` | 207,558 | 208,132 |
| `lib/Chalk/Grammar/Perl/TypeLibrary.pm` | 12,731 | 12,991 |
| `lib/Chalk/Grammar/BNF/Actions.pm` | 5,241 | 5,688 |
| `lib/Chalk/IR/Shim.pm` | 4,475 | 4,687 |
| `lib/Chalk/Grammar/BNF.pm` | 3,460 | 3,614 |
| `lib/Chalk/Grammar/BNF/Generated.pm` | 3,460 | 3,614 |
| `lib/Chalk/IR/Graph.pm` | 2,751 | 3,045 |
| `lib/Chalk/IR/NodeFactory.pm` | 1,649 | 1,833 |
| `lib/Chalk/MOP/Class.pm` | 1,049 | 1,246 |
| `lib/Chalk/Grammar/Perl/KeywordTable.pm` | 842 | 867 |

`Serialize/JSON.pm` alone accounts for **~84% of all
`_fix_postfix_chain` fires** in the corpus. That single file is the
load-bearing test case for the chain-shape ambiguity. If the filter
stack starts disambiguating PostfixDeref/MethodCall/Subscript chains
correctly, that one file's count will drop dramatically and most of
the cumulative noise goes with it.

## Interpretation

### What this measures

Each fire = a parser-derivation that reached SemanticAction in the
wrong shape and required a tree-rewrite to correct. Two interpretive
notes:

1. **Fires are not bugs in the source code.** The corpus parses
   cleanly (105/105 PARSE_OK). The fires are evidence that the
   parser+filter pipeline produced *correct results* via a *workaround*
   rather than via clean disambiguation. The workaround is the
   technical debt being measured.

2. **High counts are not necessarily worse than low counts.** A file
   with 207,558 fires of one fixup means that one ambiguity class
   triggered many times in that file, not that the file is "more
   broken." When the filter stack catches that ambiguity class, the
   207,558 disappears in one work item.

### What "complete" looks like

Filter-stack completeness means: rerun this audit, every line shows
`(none)`, the totals table reads `(no fixups fired across corpus)`.
Today: every line has counts. The roadmap is "drive the table to
empty."

### Connection to the migration plan

The MOP migration plan (`2026-04-21-chalk-mop-migration-plan.md`)
Phase 2.5 ("fixup classification & redistribution") and the addendum
in `2026-05-01-phase-3a-migration-scope-reframe.md` should be
re-framed:

- The Phase 2.5 *redistribution* idea (move fixups elsewhere in the
  pipeline) is not the goal under the 2026-05-09 framing.
- The goal is **fixup retirement**: extend filtering to catch the
  ambiguity class, verify via this audit that the corresponding
  fixup's count drops, then delete the fixup method.

## Why Bootstrap is excluded from this baseline

`lib/Chalk/Bootstrap/` was excluded because:

- A first attempt to audit the full `lib/` corpus ran 21+ minutes
  before being killed (perl interpreter at 105% CPU, 1.7 GB RSS,
  steady progress but no end in sight). Several files
  (`Earley.pm`, `Perl/Actions.pm`, the C-target ones,
  `Optimizer/StructPromotion.pm`) are individually slow due to the
  C2 chart-memory-pressure perf-gate item documented in
  `2026-04-30-parser-performance-investigation.md`.
- A second attempt with the 10 known-slow files excluded (140
  files) was killed at 28/140 after 10 minutes (still progressing,
  RSS 1.8 GB, but consuming session time disproportionate to value).
- The 105-file IR + MOP + Grammar corpus completes in under 10
  minutes and provides a clean signal.

The Bootstrap audit is deferred. When the C2 perf gate clears (or
when audit time stops being a constraint), the same script run on
`lib/` produces the full picture. Expected: same fixups fire, more
total fires, no new categories.

## Per-file detail

The full per-file table is in the audit run output. To regenerate:

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/bootstrap/lib \
    script/chalk-fixup-audit lib/Chalk/IR lib/Chalk/MOP lib/Chalk/Grammar
```

## Update protocol

When a filter-stack improvement lands that targets one of the
ambiguity classes:

1. Re-run `script/chalk-fixup-audit` on this same corpus.
2. Compare totals to this baseline.
3. Append a new section to this doc (e.g., "## 2026-MM-DD update
   after [improvement description]") showing the delta.
4. When a fixup's count drops to zero across the corpus, the fixup
   method is dead code and can be deleted; record that deletion in
   the same update section.

This doc is not the punch list — the punch list is the per-file
detail in the audit output. This doc is the **headline tracker**:
what the totals were on 2026-05-09, what they are now, and the
trajectory.

## Cross-references

- Instrumentation: commit `dc92cb61`, `lib/Chalk/Bootstrap/Perl/Actions.pm`
  + `t/bootstrap/perl-actions-fixup-instrumentation.t`
- Audit script: `script/chalk-fixup-audit`
- Architectural framing: `docs/plans/2026-04-24-semiring-contract-drift.md`
  (2026-05-09 addendum, this document's basis)
- Phase 3a-migration scope (MOP plan addendum):
  `docs/plans/2026-05-01-phase-3a-migration-scope-reframe.md`
- Perf-gate constraint affecting Bootstrap audit:
  `docs/plans/2026-04-30-parser-performance-investigation.md`

## 2026-05-10 update — per-branch instrumentation in `_fix_postfix_chain`

Commit `fe920dff` adds four sub-counters inside the four
transformation branches of `_fix_postfix_chain`, distinguishing
walker entries (the original 247K fires) from actual tree rewrites.
The audit was rerun on the same 105-file corpus. **The headline
247K-fire number is ~99.98% noise — only 44 actual rewrites occur
across the entire corpus.**

### Per-branch totals

| Branch | Source pattern matched | Fires |
|---|---|---:|
| `.method_over_deref` | `MethodCallExpr(PostfixDerefExpr(X, S), M, A)` swap | **25** |
| `.subscript_over_builtin` | `SubscriptExpr(BuiltinCall(prefix, [$var]), $key)` push | **19** |
| `.subscript_over_unary` | `SubscriptExpr(UnaryOp(op, X), $key)` push | **0** |
| `.subscript_over_binary` | `SubscriptExpr(BinOp(op, L, R), $key)` push | **0** |

Total actual transforms: **44**. Compare to walker entries: **247,355**.
Hit rate: 0.018%.

### Per-file distribution

`.method_over_deref` (25 total):

| File | Fires |
|---|---:|
| `lib/Chalk/IR/Serialize/JSON.pm` | 22 |
| `lib/Chalk/IR/Graph.pm` | 2 |
| `lib/Chalk/IR/Node.pm` | 1 |

`.subscript_over_builtin` (19 total):

| File | Fires |
|---|---:|
| `lib/Chalk/IR/Graph.pm` | 7 |
| `lib/Chalk/IR/Serialize/JSON.pm` | 5 |
| `lib/Chalk/Grammar/Perl/TypeLibrary.pm` | 4 |
| `lib/Chalk/IR/Shim.pm` | 2 |
| `lib/Chalk/IR/NodeFactory.pm` | 1 |

### Interpretation: the architectural picture flips

1. **The 247K headline number was misleading.** It conflated walker
   entries with actual rewrites. Per the 2026-05-09 framing, every
   fire was supposed to indicate a filter-stack gap; in practice
   ~99.98% of those "fires" were the walker descending into nodes
   it didn't transform.

2. **`_fix_postfix_chain` is not the load-bearing fixup.** With
   only 44 real transforms across 207K source lines, this walker
   barely does anything. Removing it should produce a small,
   measurable change — not a corpus-wide regression.

3. **Two of four branches never fire.** `.subscript_over_unary` and
   `.subscript_over_binary` had zero hits across the corpus. Either
   Precedence already handles those cases, or the patterns simply
   don't appear in the code we ship. Either way, deletion candidate
   pending a regression test.

4. **`.method_over_deref` is suspect on architectural grounds.** The
   25 files that trigger it do not contain the `$x->@*->method()`
   pattern in source (verified via `ag '\->@\*\->\w+\('`). The
   branch is therefore rewriting IR shapes that the parser produces
   for *something else* — and silently changing program meaning. Per
   perigrin's 2026-05-10 review: this is a layering violation (the
   walker is a second parse over a partial CST and cannot intuit
   source intent). The branch should be disabled, tests run, and
   either the failures investigated as real bugs or the branch
   deleted.

5. **The real disambiguation volume lives in other fixups.** The
   non-`_fix_postfix_chain` counts from the 2026-05-09 baseline
   stand:
   - `_fixup_stmts`: 2,594 (split-token reconstitution)
   - `_fix_postfix_chain_deep`: 798 (recursive walker — same noise
     pattern as `_fix_postfix_chain`; needs its own per-branch
     instrumentation to know the real transform count)
   - `_push_methodcall_inward`: 727
   - `_push_deref_inward`: 95

   When attacking volume, those are the targets. `_fix_postfix_chain`
   is a near-no-op walker.

### Implications for the retirement plan

The 2026-05-09 framing — "drive the totals table to empty" — still
holds, but the numbers it should track are the per-branch transform
counts, not the walker-entry counts. The walker-entry count is a
profiling artifact, not a correctness signal.

**Suggested next moves (read-only investigation):**

1. Disable the `.method_over_deref` branch in a feature branch, run
   `./prove`, see what breaks. The 25 affected sites concentrate in
   3 files (JSON.pm, Graph.pm, Node.pm) — failures should be tractable.
2. Same for `.subscript_over_builtin` — 5 files, 19 fires.
3. Add per-branch instrumentation to `_fix_postfix_chain_deep` so its
   798-fire number can be decomposed the same way.
4. Investigate the non-zero `_push_*` and `_fixup_stmts` fixups to
   understand which ambiguity classes drive their volume. Those are
   the real filter-stack gaps under the per-branch lens.

## 2026-05-10 update (continued) — `_fixup_stmts` and `_push_*_inward` decomposition

Commit `3c8843ee` adds 19 new sub-counters across `_fixup_stmts`
(10 branches), `_push_methodcall_inward` (5 wrapper-kind counters),
and `_push_deref_inward` (4 wrapper-kind counters). Audit re-run on
the same 105-file corpus.

**Headline: the same noise pattern as `_fix_postfix_chain` repeats.
Of 130 real disambiguations across the corpus, most concentrate on
one precedence-inversion class.**

### `_fixup_stmts` — 8 of 10 branches never fire

| Sub-counter | Fires |
|---|---:|
| `.unwrap_pass_through` | **10,836** (per-loop-iteration counter, not per-call) |
| `.vardecl_init_merge` | **14** |
| `.return_with_value` | 0 |
| `.return_bare` | 0 |
| `.die_with_arg` | 0 |
| `.use_with_args` | 0 |
| `.assign_init_to_vardecl` | 0 |
| `.binop_into_list_builtin` | 0 |
| `.list_builtin_call` | 0 |
| `.prefix_builtin_call` | 0 |

The aggregate `_fixup_stmts = 2,594` is a per-call counter; the loop
iterates ~4× per call on average. Only **14 actual statement
merges** happen across the corpus, all of them the same kind
(`VarDecl(undef) + expr → VarDecl(var, expr)` declaration-init
merge). Eight of the ten merge classes are dead code.

### `_push_methodcall_inward` — 93% pure pass-through

| Sub-counter | Fires |
|---|---:|
| `.no_wrappers` | **676** |
| `.peel_builtin` | **51** |
| `.peel_return` | 0 |
| `.peel_unwind` | 0 |
| `.peel_postfixderef` | 0 |

Of 727 calls, 676 (93%) peel nothing — the function builds a plain
`MethodCallExpr` and returns. The remaining 51 calls all peel a
single wrapper kind: `BuiltinCall`. The `Return`/`Unwind`/
`PostfixDerefExpr` peel paths never fire.

### `_push_deref_inward` — only two peel kinds fire

| Sub-counter | Fires |
|---|---:|
| `.peel_method` | **11** |
| `.peel_builtin` | **10** |
| `.peel_return` | 0 |
| `.peel_unwind` | 0 |

Of 95 calls, only 21 peel any wrapper, split between `BuiltinCall`
(10) and `MethodCall` (11). The `Return`/`Unwind` peel paths never
fire.

### Cross-fixup synthesis

Combining yesterday's `_fix_postfix_chain` decomposition with today's
results, the **total real disambiguation work performed across the
entire 105-file corpus is 130 transformations**:

| Fixup | Aggregate "fires" | Real transforms |
|---|---:|---:|
| `_fix_postfix_chain` | 247,355 | 44 |
| `_fix_postfix_chain_deep` | 798 | unmeasured (same noise pattern likely) |
| `_fixup_stmts` | 2,594 | 14 |
| `_push_methodcall_inward` | 727 | 51 |
| `_push_deref_inward` | 95 | 21 |
| **Total real transforms** | — | **130** |

The original 2026-05-09 framing — "every fire is evidence of a
filter-stack gap" — was measuring the wrong number. The 247K-fire
narrative was 99.95% measurement artifact (walker descent / call
overhead). Actual filter-stack work happens in ~0.05% of fires.

### The pattern that emerges

Of the 130 real disambiguations:

- **44** are `_fix_postfix_chain` transforms (25 method-over-deref
  + 19 subscript-over-builtin)
- **51** are `_push_methodcall_inward.peel_builtin` (BuiltinCall
  wrapping a method invocant)
- **21** are `_push_deref_inward` peels (10 builtin + 11 method
  wrapping a deref target)
- **14** are `_fixup_stmts.vardecl_init_merge` (declaration-init
  reconstitution)

Three of the four categories — accounting for **86 of 130 real
transforms (66%)** — are the same precedence-inversion family:
**a prefix builtin (defined/exists/scalar/ref/etc.) parsed at lower
precedence than the postfix `->method()`, `->{key}`, or `->@*` it
should bind tighter than.** That ambiguity class is large enough,
focused enough, and in the right semiring (Precedence) to be a
worthwhile attack target.

### 13 dead branches across the fixup suite

| Fixup | Dead branches (zero fires across corpus) |
|---|---|
| `_fix_postfix_chain` | `.subscript_over_unary`, `.subscript_over_binary` |
| `_fixup_stmts` | `.return_with_value`, `.return_bare`, `.die_with_arg`, `.use_with_args`, `.assign_init_to_vardecl`, `.binop_into_list_builtin`, `.list_builtin_call`, `.prefix_builtin_call` |
| `_push_methodcall_inward` | `.peel_return`, `.peel_unwind`, `.peel_postfixderef` |
| `_push_deref_inward` | `.peel_return`, `.peel_unwind` |

Total: **13 transformation branches that never fire on the corpus.**
Each is a deletion candidate pending a regression test that exercises
the corresponding pattern (to confirm the parser already produces
the right shape directly).

### Implications for retirement work

1. **The 247K headline in the 2026-05-09 baseline is a profiling
   artifact.** Future audit reports should lead with per-branch
   transform counts, not aggregate fire counts.

2. **Most of the "filter-stack gap" surface area doesn't exist.**
   The fixup suite contains 13 dead branches and 3 mostly-noop
   walkers. The actual gap is concentrated in one precedence-inversion
   class (prefix builtin vs postfix dispatch), 86 instances corpus-wide.

3. **Deletion is the right next move for the dead branches.** Per
   regression test (one per branch), confirm the pattern produces
   correct IR without the branch, then delete. Mechanical, well-
   scoped, reduces fixup-suite size by ~70%.

4. **The Precedence semiring has a single concrete target.** Once the
   dead branches are gone, the only ambiguity class with non-trivial
   volume is "prefix builtin binding looser than postfix dispatch."
   That's the move that makes the audit numbers actually approach
   zero, and it's a real semiring extension (not a fixup retirement).
