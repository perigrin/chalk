# Agentic Code Review: 019eb6ff (cache/identity follow-up family — Phase 4 Gate 0)

**Date:** 2026-06-13 12:45:45
**Branch:** phase1-lateral-bindings (issue scope: `d8406a4^..3de55c3a`, 7 commits)
**Commit:** 3de55c3a

## Executive Summary

The six follow-up fixes (match-family identity, at-use aggregate pointers,
literal-alloc identity, collector table-read, loop-exit guard, full :isa
inheritance) are behaviorally sound and all revert-proven. The review found
ONE real miscompile in the new code — multi-level / sort-order-sensitive
inheritance dying in lli — plus three coverage gaps and a duplication
suggestion. The miscompile and the highest-value gaps are FIXED; two
low-severity symmetric gaps are filed. No issue survives open.

## Critical (FIXED)

### [C1] Multi-level / sort-order inheritance dies in lli
- `lib/Chalk/Target/LLVM.pm` `_emit_class_registry_ir` (struct-type
  emission) × the fix-6 ADJUST flatten.
- An inherited ADJUST flattened into a child carries the declaring
  ancestor's `field_stash`, so `@Child__ADJUST` GEPs into `%Ancestor.obj`.
  Struct types were emitted inline per class block in `sort keys` order, so
  the GEP referenced an undefined (opaque, unsized) struct whenever the
  child sorted before its ancestor → lli "base element of getelementptr
  must be sized". Reproduced by BOTH the Logic and Test-Reality agents
  (3-level G→Mid→Kid; 2-level Apple :isa Zoo). The shipped T6 test was a
  false positive (Base < Kid sorts parent-first).
- **Fix:** hoist every class's vtable + object-struct type into a pre-pass
  before any class body. RED-first tests added: child-sorts-before-parent
  (Int:21), 3-level field+ADJUST chain (Int:42).
- **Found by:** Logic (conf 95), Test-Reality (conf 88), independently.

## Coverage gaps

### [G1] Match (qr-apply) per-call identity was factory-id-only — FIXED
- Only RegexMatch had a behavioral lli test; Match lowers via
  `_lower_match_apply` and is testable. Added a qr-re-applied-after-reassign
  lli subtest (Bool: vs stale Bool:1). (NotMatch/BacktickExpr have no
  backend lowering yet — factory-id is the legitimate ceiling there.)

### [G2] Inherited :reader / field-inheriting override untested — FIXED
- Both probed correct-but-untested by Test-Reality; added an lli subtest
  (inherited :reader 5 + override-reading-inherited-field 105 = 110) to
  lock the fix-6 "full inheritance" claim.

### [G3] Aggregate-keying symmetric gaps — FILED (low severity)
- fix-2 tested array subscript-read + element-store after reassign. Hash
  read/store, Length-after-reassign route through the SAME `_container_ptr`
  (structurally covered). PostfixDeref (`@$ref`/`%$ref`) uses a DIFFERENT
  path (`_lower_array_deref`/`_lower_hash_deref`, bitcast + cache by node
  id) that the fix did not touch — untested for the reassign scenario.
- Filed as a 019eb6ff follow-note (below); not gating — the deref path
  predates this issue and is not in the fix's claim.

## Suggestion (APPLIED)

The `VarDecl + %STATEMENT_EFFECT_OPS` membership test was open-coded at 3
collector sites (+If/Loop at two). Extracted
`Chalk::IR::NodeFactory::is_statement_node($op)`; all three collectors call
it — adding a table op is now a single-site change. Flagged by Contract and
Test-Reality agents (conf 70).

## Verified clean (no findings)

- No double-malloc: ArrayRef literals (now per-call #N) are NOT in the
  Family-B mutable-read predicate, so `lower_value(ArrayRef)` hits the value
  cache after first lowering — `[1,2][0]` emits exactly 2 mallocs. Per-call
  identity is hash-cons-only, orthogonal to the SSA value cache. (Logic.)
- No double-lower of value-position matches: a match consumed as a VarDecl
  input (no control_in) is not independently collected (collectors walk
  consumers, not inputs); the second lower_value is a cache hit. (Logic.)
- Loop-exit GAP guard cannot false-positive: a Phi is a consumer only of
  its own `region` arg, so a nested-if Phi never appears on the loop's exit
  Region. (Logic.)
- All 6 %STATEMENT_EFFECT_OPS readers migrated (incl. the un-named-in-brief
  Elaborate site); no site hardcodes the old 5-op list; %ALLOC_OPS is
  correctly value-only. (Contract.)
- _arr_table/_hash_table fully deleted (no dangling reads/writes/init);
  _wire_region_phis deleted (no callers; the if/else
  _wire_region_phis_with_preblock is untouched). (Contract.)
- Serializer round-trips the new per-call ops; cross-load (31 ok) +
  ir-serialize (37 ok) green. Registry-shape change consumed correctly by
  _lower_call_new + _emit_class_registry_ir. (Contract.)
- All new tests behavioral + revert-proven (each one-line fix stashed,
  corresponding test confirmed failing); full corpus green; the 3 mop
  failures are pre-existing on the base commit. (Test-Reality.)

## Follow-note (filed, not gating)

PostfixDeref (`@$ref`/`%$ref`) does not use `_container_ptr` — a ref-var
reassign followed by a postfix-deref read could serve a stale typed pointer
(same class as the fix-2 bug, different code path). Symmetric hash-reassign
+ Length-after-reassign lli cases would close coverage cheaply. Low
severity; route through the deref path on a future aggregate pass.

## Review Metadata

- **Agents:** Logic & Correctness, Contract & Integration, Test Reality (3,
  parallel)
- **Raw findings:** 9 | **Verified:** 1 Critical + 2 gaps fixed, 1 gap
  filed, 1 suggestion applied, 4 cleared
- **Cross-agent agreement:** C1 by 2 (both live repros); the duplication
  suggestion by 2
