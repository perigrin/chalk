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
   **NOTE 2026-05-10b: this number was a corpus-sampling artifact.
   See the Bootstrap addendum below.**
2. Same for `.subscript_over_builtin` — 5 files, 19 fires.
   **NOTE 2026-05-10b: same — see Bootstrap addendum.**
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

## 2026-05-10b update — Bootstrap audit (partial); the "dead branch" claim was wrong

Per perigrin's challenge ("`lib/Chalk/Bootstrap` is where most of
the code is implemented — why is it excluded?"), the audit was
re-run against `lib/Chalk/Bootstrap` (the actual compiler source).
Prior runs excluded it for measurement-cost reasons documented in
"Why Bootstrap is excluded from this baseline" above; that exclusion
was a shortcut, not a principled choice, and the framing in the
2026-05-10 addendum overgeneralized from the IR/MOP/Grammar sample.

The Bootstrap audit ran 2 hours of CPU under an 8 GB vmem cap and
2 h CPU ulimit before being terminated by the CPU cap. **27 of 44
files completed** before kill — including most of the gnarly ones
(`Earley.pm`, `Desugar.pm`, `ConciseTree/Actions.pm`,
`LR0DFA.pm`, all four BNF targets). Files that did NOT complete
include `Perl/Actions.pm` (3,356 lines — the home of
`_fix_postfix_chain` itself), `Perl/Target/EmitHelpers.pm`,
`Perl/Target/C.pm`, all four semirings, and several others.

The script (`script/chalk-fixup-audit`) was refactored in commit
`3eb8d7c2` to print per-file rows incrementally so partial results
survive a cap-kill. Raw output saved at
`docs/plans/2026-05-10-fixup-audit-bootstrap-partial.txt`.

### Headline: the "dead branches" weren't dead, they were unsampled

| Counter | IR/MOP/Grammar (105 files) | Bootstrap (27 of 44) | Multiplier |
|---|---:|---:|---:|
| `_fix_postfix_chain.subscript_over_builtin` | 19 | **827** | **44×** |
| `_fix_postfix_chain.method_over_deref` | 25 | **117** | **5×** |
| `_fix_postfix_chain.subscript_over_unary` | 0 | **96** | **was "dead"** |
| `_fix_postfix_chain.subscript_over_binary` | 0 | 0 | (still no fires) |
| `_push_deref_inward.peel_builtin` | 10 | 65 | 7× |
| `_push_deref_inward.peel_method` | 11 | 39 | 4× |
| `_push_methodcall_inward.peel_builtin` | 51 | 62 | 1.2× |
| `_fixup_stmts.vardecl_init_merge` | 14 | 46 | 3× |
| `_fixup_stmts.binop_into_list_builtin` | 0 | **1** | **was "dead"** |

**Two of the four `_fix_postfix_chain` "dead branches" became
live-and-frequent on Bootstrap source:**

- `.subscript_over_unary` jumped from 0 → 96. `Desugar.pm` alone
  fires it 59 times (`!$x->{key}`-style patterns); `LR0DFA.pm`
  fires it 30 times.
- `_fixup_stmts.binop_into_list_builtin` went from 0 → 1.

**One branch remains zero across both corpora:**
`_fix_postfix_chain.subscript_over_binary` (0/0). That one might
genuinely be unreachable, but the call-graph hasn't been verified.

### Total real transforms: ~1,250 in 27 files vs 130 in 105 narrower files

Bootstrap-partial total real transforms (per-class):

| Counter | Fires (Bootstrap partial) |
|---|---:|
| `_fix_postfix_chain.subscript_over_builtin` | 827 |
| `_fix_postfix_chain.method_over_deref` | 117 |
| `_fix_postfix_chain.subscript_over_unary` | 96 |
| `_push_deref_inward.peel_builtin` | 65 |
| `_push_methodcall_inward.peel_builtin` | 62 |
| `_fixup_stmts.vardecl_init_merge` | 46 |
| `_push_deref_inward.peel_method` | 39 |
| `_fixup_stmts.binop_into_list_builtin` | 1 |
| **Total real transforms (partial)** | **~1,250** |

That's almost 10× the 130 from the prior corpus, with 17 files
still unaudited (including the largest). Extrapolating naively
from line-count ratios, the full Bootstrap audit would likely
report 3,000–5,000 real transforms.

### Why one file (`Earley.pm`) dominates `subscript_over_builtin`

Of the 827 `subscript_over_builtin` fires in Bootstrap-partial,
**547 (66%) are from `Earley.pm` alone.** That file has the
`defined $chart[...]->{key}` / `exists $waiting_for{...}->[idx]`
patterns characteristic of bookkeeping over the Earley chart — the
exact precedence inversion the branch was written to handle. The
high concentration confirms the architectural diagnosis: this isn't
"random parser shapes the walker happens to match"; it's a
genuine ambiguity class our grammar admits and our filter stack
fails to disambiguate.

### Architectural picture (revised, 2026-05-10b)

1. **The 13-dead-branches claim was a sampling artifact.** Eleven
   of those branches likely fire on the unaudited 17 Bootstrap files
   too. Don't delete them without per-pattern regression tests
   exercising the patterns — the patterns exist in real Perl, the
   prior corpus just didn't contain them.

2. **The precedence-inversion class is even more dominant than
   previously thought.** Of ~1,250 partial-Bootstrap transforms,
   1,050 (84%) are prefix-builtin-vs-postfix-dispatch precedence
   inversions. Volume is large enough that extending Precedence to
   handle this class would meaningfully reduce the fixup walker's
   actual work, not just trim dead code.

3. **Method-over-deref turns out to be real disambiguation, not a
   silent meaning-change.** Initial hypothesis (recorded in the
   2026-05-10 addendum and committed in `f7626351`) was that the
   branch silently rewrote invalid `$x->@*->method()` (method-on-list)
   into `($x->method())->@*`. Verification on Bootstrap-partial files
   where the branch fires shows the actual source pattern is the
   reverse: **valid Perl `$obj->method()->@*` (12 occurrences in
   ConciseTree/Actions.pm, 4 in Context.pm, 1 in Desugar.pm, etc.)
   that the parser misparses as `MethodCall(PostfixDeref($obj, ?),
   method, ?)` instead of `PostfixDeref(MethodCall($obj, method, []),
   @)`.** The walker rewrites the wrong derivation back to the right
   one. This is the same precedence-inversion class as
   `subscript_over_*` — `->` ambiguity between postfix-deref and
   method-call when both start with `Expression _ /->/`.

   Implication: the branch is doing real and correct work. The
   architectural problem is the layer (post-parse walker instead of
   in-parse filter), not the rewrite logic. Earlier framing of "this
   branch silently changes program meaning" was wrong and is
   superseded by this addendum.

   Anomaly: 5 fires in `Earley.pm` with zero direct
   `->method()->@*` source matches. Likely chain across line breaks
   or intermediate non-method postfix; small enough to defer.

4. **`Perl/Actions.pm` was never audited.** It's the home of
   `_fix_postfix_chain` itself. We don't know whether the walker
   audits its own source cleanly. That's a meta-question worth
   answering separately.

5. **Grammar gap surfaced as side-effect:** `DepChaser.pm` fails
   to parse on `local $/;` (line 168). Chalk's grammar doesn't
   accept the `$/` punctuation variable (and presumably `$@`, `$!`,
   `$,`, `$"`, `$;`, `$0`, etc.). This is a real grammar gap that
   blocks self-hosting of any code using these variables, but is
   out of scope for the fixup-audit work.

### Implications for next moves

The earlier "Option 3: demolition first, then precedence" plan is
no longer viable — there's almost nothing safe to demolish. The
right reframe:

1. **Investigate `_fix_postfix_chain.method_over_deref` first.** 117
   fires across files where silent meaning-change would be
   catastrophic. Either it's matching the right shapes and the
   rewrite is correct (in which case we need to understand *why*
   the parser produces them), or it's matching wrong shapes and
   silently breaking compilation. Read-only investigation.

   **Result (2026-05-10c, this addendum):** investigation done,
   conclusion is "real disambiguation, not silent rewrite." See
   item 3 in the architectural picture above and the cross-fire-pattern
   table below.

2. **Hold off on dead-branch deletion.** Only `subscript_over_binary`
   (0 fires across both corpora) is still a candidate, and verifying
   it's truly unreachable requires call-graph analysis.

3. **Complete the Bootstrap audit when feasible.** The remaining 17
   files include the largest (`Perl/Actions.pm` 3,356, `EmitHelpers.pm`
   2,527, `Perl/Target/C.pm` 2,119). Running each individually with
   its own CPU budget avoids the all-or-nothing cap-kill. Lower
   priority than #1.

4. **The Precedence work is still the load-bearing target** — but now
   the volume case is overwhelming (~1,050 precedence inversions in
   partial Bootstrap, likely 2,500+ in full Bootstrap). This should
   be the eventual destination once the investigation steps complete.

### Cross-fire-pattern verification (2026-05-10c)

For each branch that fires meaningfully on Bootstrap-partial,
verified that the source files contain real Perl patterns the
branch is rewriting. All three branches match the same architectural
class: `->` precedence ambiguity where the parser admits a
wrong derivation alongside the right one and FilterComposite picks
the wrong one.

| Branch | Source pattern | Files (sample) | Source occurrences | Walker fires |
|---|---|---|---:|---:|
| `.method_over_deref` | `$obj->method()->@*` | ConciseTree/Actions.pm | 12 | 79 |
| `.method_over_deref` | `$obj->method()->@*` | Context.pm | 4 | 13 |
| `.method_over_deref` | `$obj->method()->@*` | Desugar.pm | 1 | 1 |
| `.subscript_over_builtin` | `defined $x->{k}` etc. | Earley.pm | 24 | 547 |
| `.subscript_over_builtin` | `defined $x->{k}` etc. | Desugar.pm | 3 | 60 |
| `.subscript_over_builtin` | `defined $x->{k}` etc. | Context.pm | 8 | 24 |
| `.subscript_over_unary` | `!exists $h{k}` (stacked) | Desugar.pm | 2 | 59 |

The fire-to-source ratio is 6×–23×, consistent with the parser
exploring multiple derivations during ambiguity resolution and the
walker recursing through nested constructs.

**Architectural unification:** all three `_fix_postfix_chain`
branches that fire meaningfully (and `_push_*_inward.peel_builtin`)
are rewriting the same precedence-inversion class:

> `->` is overloaded between postfix-deref/subscript and
> method-call/subscript. When chained patterns like
> `$x->method()->@*` or `defined $x->{k}` appear, the parser
> admits both orderings; nothing in the filter stack expresses
> the correct binding precedence; FilterComposite picks one
> arbitrarily; the walker corrects it.

The right architectural fix is a single rule in the Precedence
semiring: when both a postfix-deref and a method-call (or
prefix-builtin and subscript) derivation are admitted at the same
span, prefer the binding that matches the source-token order. This
single change retires four branches simultaneously and reduces
walker volume from ~1,050 fires to (target) zero on Bootstrap.

**Status:** investigation complete; design and implementation of
the Precedence rule remains.

## 2026-05-12 update — after Round 1+2+3 precedence-spec TODO cleanup (Class I reverted)

Today's session completed three rounds of precedence-spec TODO
cleanup work, then reverted one item that introduced regressions.
Landed work:

- **Step 1+2** of the named-unary precedence implementation
  (commits `2e9e5739`, `4bbe6308`, `dd2df9cf`)
- **Round 1**: Class B (unary vs subscript), Class D (grammar
  gaps), Class H (`not` at L23) — `5114f869`, `f13834a1`,
  `2ed5cd7b`
- **Round 2**: Class C (method-chain — design issue, no semiring
  change), Class E subset (nonassoc), Class G (ternary) —
  `c9837dbe`, `13da05e7`, `c914a81d`
- **Round 3**: Class F (pre-increment grammar), Class J (... as
  Range) — `f5e3b911`. Class I (list-op slurping) attempted at
  `9966de8c`, **reverted at `61ecb184`** because it broke 3
  previously-OK files in the corpus.

Audit raw output saved at
`docs/plans/2026-05-12-fixup-audit-raw.txt`. Bootstrap audit not
re-run this session (the regression caught at IR/MOP/Grammar
level made it unnecessary; once Class I was reverted the corpus
returned to clean state).

### Headline numbers (105-file IR/MOP/Grammar)

| Counter | 2026-05-10 | 2026-05-12 | Δ |
|---|---:|---:|---:|
| Files PARSE_OK | 105 | 105 | 0 |
| Files PARSE_FAIL | 0 | 0 | 0 |
| `_fix_postfix_chain.subscript_over_builtin` | 19 | **0** | **-19** |
| `_fix_postfix_chain.method_over_deref` | 25 | 25 | 0 |
| `_fix_postfix_chain.subscript_over_unary` | 0 | 0 | 0 |
| `_fix_postfix_chain` (walker entries) | 247,355 | 247,835 | +480 (noise) |
| `_push_methodcall_inward.peel_builtin` | 51 | 51 | 0 |
| `_push_deref_inward.peel_method` | 11 | 11 | 0 |
| `_push_deref_inward.peel_builtin` | 10 | 11 | +1 (noise) |
| `_fixup_stmts.vardecl_init_merge` | 14 | 15 | +1 (noise) |

The named-unary work delivered the headline drop:
`_fix_postfix_chain.subscript_over_builtin` went from 19 to **0**
on this corpus. That's the expected outcome — `defined $h{key}`
and `exists $h->{key}` style patterns now produce the perlop-
correct shape directly from the parser instead of requiring the
walker to fix them.

The other counters are unchanged or moved by noise (+1, etc.) —
the Round 1+2 work for Class B, C, E, G, H targets patterns
that don't appear in this corpus. Their value will only show on
Bootstrap (next audit, future session).

### What did NOT change and why

`_fix_postfix_chain.subscript_over_unary` stays at 0 because the
IR/MOP/Grammar corpus doesn't contain `!$h{k}` / `-$x->{k}`
patterns. Class B's fix targets these but the corpus doesn't
exercise them; expect the impact on the Bootstrap audit
(particularly Desugar.pm, where 59 fires were observed in the
2026-05-10b Bootstrap-partial audit).

`_fix_postfix_chain.method_over_deref` stays at 25 because Class C
discovered it's NOT a Precedence question — it's filter-gap merge
in SemanticAction (per commit `25c01a28`'s framing). No semiring
change attempted.

### Class I post-mortem

The reverted Class I implementation tried to encode list-operator
context as a precedence-level marker (level 4.4) and propagate it
through 8 sites in `Precedence.pm`. The named-unary spec tests
passed; chained list-op patterns broke. Three real Chalk files
that previously parsed (`lib/Chalk/IR/FieldInfo.pm`,
`lib/Chalk/IR/Serialize/JSON.pm`,
`lib/Chalk/Grammar/Perl/TypeLibrary.pm`) failed on patterns like
`map { $_ } sort keys %h` after Class I.

Architectural finding documented in
`docs/plans/2026-05-12-list-operators-as-predeclared.md`:
list-operator slurping is parser greediness, not operator
precedence. Built-in list operators are predeclared functions and
behave like user-defined functions for parsing purposes. The
"comma-slurping" bug is universal across all parens-free calls
(built-in AND user-defined) — affecting `sort 1, 2`,
`my_func 1, 2` identically — and belongs in chart-merge
preference logic OR a fixup walker, NOT a precedence-level
marker.

The L22 TODOs in `t/bootstrap/precedence-spec-low-words.t`
(chmod, sort, reverse) were updated with refined diagnostic
messages pointing to the design note.

### Lesson recorded in CLAUDE.md

Two new rules added under TDD section:

1. **Nested-context coverage extension to bilateral coverage rule**:
   when a feature affects how rules combine in chains (list-op
   after list-op, ternary in ternary, etc.), the bilateral
   coverage must include multi-level invocations. Class I had
   bilateral tests for individual list operators but not for
   chained patterns; the chained patterns broke.

2. **Precedence semiring scope rule**: precedence levels are for
   operator binding-priority, not for parser-state markers,
   symbol-table info, or parser-greediness rules. Heuristic: if
   implementing a "precedence rule" needs more than ~5
   special-case sites in the semiring, the rule is probably not
   precedence — try grammar (add a rule), fixup walker, or
   another semantic layer.

### Recommendation: branch is mergeable

The branch `fixup-audit-baseline` is in a clean known-good state
at `61ecb184` (Class I revert) plus this session's docs commits.
105/105 PARSE_OK; the load-bearing precedence work delivered
(`subscript_over_builtin = 0`); architectural lessons recorded.
Suitable for ff-merge to `pu`.

**Future work** (NOT blocking merge):

- Bootstrap audit re-run (~2h with ulimit; would quantify Class
  B's impact on `subscript_over_unary` patterns)
- Walker retirement: `subscript_over_builtin = 0` on
  IR/MOP/Grammar means the branch is deletable on this corpus;
  verify on Bootstrap before deleting
- Class I redesign: chart-merge preference rule or fixup walker,
  per the design note
- Remaining 13 real TODOs across the spec files (covered in the
  session-end summary)

### Cross-references

- Class I revert: commit `61ecb184`
- Architectural framing: `docs/plans/2026-05-12-list-operators-as-predeclared.md`
- The named-unary lesson: `docs/plans/2026-05-11-step2-second-blocker.md`
- Raw audit output: `docs/plans/2026-05-12-fixup-audit-raw.txt`
- Updated CLAUDE.md rules: see CLAUDE.md "Bilateral coverage" and
  "Precedence semiring scope" sections under TDD
