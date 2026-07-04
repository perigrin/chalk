# Agentic Code Review: triple-contract gate (zhi 019f1be7)

**Date:** 2026-07-04
**Branch:** phase1-lateral-bindings (scope: HEAD~2..HEAD, commits 8be18c90 + 77e4dbe0)
**Commit:** 77e4dbe003e9369e5430676423779a2642961ab7
**Files changed:** 4 | **Lines changed:** +271 / -155
**Diff size category:** Medium

## Executive Summary

The gate mechanism is sound (contracts to TypedInvariant/Graph::nodes/
build_graph_from_ir all verified correct; multiset splice is per-call-safe;
the deleted matcher pair had zero callers). The review found one
cross-confirmed measurement bug — the lower-failure path drops the loaded
graph so ~10 cases falsely report "no loaded graph" for shape/invariant —
plus a cluster of gate-honesty gaps: no non-TODO floor on gate-green, a
greedy-match false-FAIL mode, latent walker robustness, and a doc overclaim
("full triple contract") that silently narrows the brief's two-corner
behavior leg to lli-only.

## Critical Issues

None found.

## Important Issues

### [I1] Lower-failure and no-Return paths drop the loaded graph
- **File:** `t/bootstrap/corpus/son-corpus-wide.t:70,73`
- **Bug:** `return (undef, "lower: $@")` and `return (undef, "no Return node")` omit `$g`, so the runner reports `shape/invariant: no loaded graph` for cases whose graph loaded fine (~10 cases: classes field-basic/field-attrs/class-isa/adjust, references R1/R4/R5/R8, variables A5, host H3).
- **Impact:** the re-audit's per-leg counts (invariant=49, shape=9) systematically under-count; the invariant leg is most diagnostic exactly when lowering dies.
- **Fix:** thread `$g` through both returns.
- **Confidence:** High — **Found by:** Logic, Concurrency/State, Contract, Plan Alignment

### [I2] Gate-green has no failing assertion — regressions are silent
- **File:** `t/bootstrap/corpus/son-corpus-wide.t` (TODO block)
- **Bug:** every non-gate-green case is a TODO fail, so a regression of the 9 gate-green cases keeps CI green.
- **Fix:** non-TODO `cmp_ok($tally{gate_green}, '>=', 9)` floor, raised as families land.
- **Confidence:** High — **Found by:** Error Handling

### [I3] Greedy first-fit multiset match can false-FAIL a satisfiable spec
- **File:** `t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm` (`_sig_match`)
- **Bug:** a less-constrained spec sig (no repr) can consume the only real node a stricter same-kind sig needed; walk-order dependent.
- **Fix:** sort spec sigs most-constrained-first before matching; bipartite matching is the further upgrade.
- **Confidence:** Medium — **Found by:** Logic, Concurrency/State, Error Handling

### [I4] Doc overclaims "full triple contract": behavior leg is L-corner-only
- **File:** `docs/plans/2026-07-01-phase4-corpus-wide-status.md` (re-audit section)
- **Bug:** the brief's behavior leg has two corners (P = Target::Perl full-coverage, L = LLVM runtime-free slice); the runner exercises only L, and the diff dropped the previous version's behavior-only caveat without carrying the P-corner omission forward. Also unacknowledged: per-method class graphs are never shape/invariant-checked, and "structural-subset" is implemented edge-blind (named only in a code comment).
- **Fix:** doc caveat + file the P-corner/gate-fidelity follow-up issue.
- **Confidence:** High — **Found by:** Plan Alignment

## Suggestions

- `_visit_node` lacks the `ref eq 'ARRAY'`/blessed input guard Graph::nodes and TypedInvariant both carry; one arrayref-input node kills the whole run mid-loop (latent — loader emits flat inputs today). Wrap the two legs in eval in the runner. (Error Handling)
- lli deaths by signal (`$? & 127`) are classified as exit-0 success and string-compared. (Error Handling)
- `_is_pure_gap_block` passes any node-line-free block (even `L: GREEN`-only) vacuously; builder-undef downgrades a malformed spec to SKIP. Latent — no such blocks exist. (Error Handling)
- Worklist diag header still says "behavior gaps" though most entries are now shape/invariant gaps. (Logic, Contract)
- Guard-prologue duplication across shape_subset_check/_run_ir_shape_check/_run_l_verdict_check — deliberately skipped at three instances (differing verdict semantics); revisit at a fourth. (Contract)
- eval{} vs the try/catch working agreement: surrounding file uses eval; file-consistency wins. Informational. (Logic)

## Plan Alignment

- **Implemented:** shape leg (constructive-builder spec graph + signature subset), invariant leg (TypedInvariant), re-audit recorded (gate-green=9), two systemic shape families filed (019f2a50 pair), stale matcher deleted.
- **Not yet implemented:** P-corner (Target::Perl) behavior leg; per-method class-graph checking; rooted (edge-aware) structural matching.
- **Deviations:** doc's "full triple contract" claim vs L-corner-only behavior (I4).

## Review Metadata

- **Agents dispatched:** Logic & Correctness, Error Handling & Edge Cases, Contract & Integration, Concurrency & State, Plan Alignment. Security intentionally omitted: local test harness, no trust boundary.
- **Scope:** the 4 changed files + TypedInvariant.pm, Graph.pm, Serialize/JSON.pm, NodeFactory.pm, corpus .md files, all MdtestCorpus consumers.
- **Raw findings:** 13
- **Verified findings:** 4 Important + 6 Suggestions (verification inline: every finding re-read at file:line; I1 quadruple-, I3 triple-confirmed)
- **Steering files consulted:** CLAUDE.md (repo + user), memory index
- **Plan/design docs consulted:** docs/plans/2026-06-12-phase4-bson-brief.md, docs/plans/2026-07-01-phase4-corpus-wide-status.md, docs/plans/2026-06-07-mdtest-corpus-format-draft.md
