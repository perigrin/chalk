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
