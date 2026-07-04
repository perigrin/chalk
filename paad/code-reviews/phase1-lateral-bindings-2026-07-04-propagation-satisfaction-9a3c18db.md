# Agentic Code Review: propagation-satisfaction (zhi 019f2a50)

**Date:** 2026-07-04
**Branch:** phase1-lateral-bindings (commit 9a3c18db, review fix follows)
**Scope:** t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm (_mark_pad_scaffolding + And/Or repr concession), t/bootstrap/corpus/shape-subset-check.t, format doc.

## Executive Summary

Propagation-satisfaction lets the corpus keep the pad-explicit lexical shape
while matching a B::SoN graph that propagated the pad away (gate-green 16→28).
Three reviewers (false-green, logic, quality). Quality and logic came back
CLEAN with runnable-probe verification. The false-green reviewer found ONE
real regression, empirically reproduced and fixed TDD.

## Important Issues (fixed)

### [I1] Unconditional pad subsumption dropped the repr check → mis-typed kept pad false-PASSed
- **File:** MdtestCorpus.pm `_mark_pad_scaffolding`
- **Bug:** every PadAccess/VarDecl was subsumed unconditionally, dropping its repr constraint. A pad-KEEPING producer (Chalk) that stamps a lexical `:Str` where the spec demands `:Int` — a real type-lowering bug — PASSed post-diff (FAILed pre-diff). Empirically reproduced (`PASS` with `missing=[]`).
- **Found by:** false-green (conf 85).
- **Fix:** concede EXISTENCE only, not repr. Subsumption fires per-kind only when the real graph propagated that pad kind away (has zero of it). A producer that keeps the pad is not conceded — its pad nodes must match including repr. Test 23 (teeth: FAILs correctly for the mis-typed kept pad). Corpus gate-green held at 28 (B::SoN graphs have no pads, so subsumption still fires for the propagated path).

## Suggestions

- **[Finding 2, forward-composability]** `_mark_pad_scaffolding` is not consumer-guarded like `_fold_satisfied_ids`. Safe today (effectful writers survive on the control chain, not as PadAccess data consumers), but the deferred Assign/CompoundAssign propagation (019f2d47) could subsume a PadAccess feeding an Assign as a data operand. Noted on 019f2d47: give that work the fold path's fixpoint discipline. (conf 62; deferred with the work it affects.)
- **[pre-existing, not this diff]** the matcher is edge-blind (multiset); PadAccess `varname` and CompoundAssign `op` are not in the signature, so a `+=`-vs-`*=` swap or a varname mismatch isn't caught. Predates this diff; tracked under the rooted-matching item (019f2af2).

## CLEAN (verified with probes)

- Name-Constant sole-consumer guard: correct (a shared name-Constant survives).
- Wrong propagated value still FAILs (value node keeps its signature; _visit_node traverses into subsumed nodes' inputs).
- And/Or/DefinedOr repr concession: accepts ONLY unstamped real repr for exactly those three kinds; a wrong stamped repr still FAILs; no leak to other kinds. Verified truth-table.
- fold ∩ pad subsumption merge does not over-subsume.

## Review Metadata

- **Agents:** false-green (critical), logic, quality (reuse+simplification). Security/concurrency omitted (single-process test harness).
- **Verified + fixed:** 1 Important (empirically reproduced). 1 deferred forward-note. Quality CLEAN.
- **TDD:** RED test reproducing the false-green → fix → GREEN, gate-green held.
