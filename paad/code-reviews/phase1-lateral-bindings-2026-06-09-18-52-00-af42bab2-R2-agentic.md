# Agentic Code Review: R2 (node convergence Phases 0-3, aggregates)

**Date:** 2026-06-09 18:52:00
**Branch:** phase1-lateral-bindings -> pu
**Commit:** af42bab262d433fd8f91d2d1d422facbe02333f3
**Window:** 02e54ce6..af42bab2 (8 commits, fa7c0715..af42bab2)
**Files changed:** 18 | **Lines changed:** +1067 / -323 | **Category:** Medium-Large
**Method:** 4 specialists (logic, error/edge, contract+coverage, plan-alignment) + verification + 2 orchestrator spot-checks.

## Executive summary

R2 converged 11 parallel aggregate IR nodes onto the canonical vocabulary
(Length/Subscript/PostfixDeref/ArrayRef/HashRef/Assign-over-Subscript-lvalue) by
re-pointing the LLVM dispatch ladder and reusing existing lowering bodies. The
convergence is **functionally correct on the corpus** — references.t is 27/27 GREEN,
independently confirmed. **No finding is CONFIRMED LIVE** (every real bug sits on a code
path the corpus does not exercise, which reconciles with the green gate). The review
found **4 Important LATENT bugs** that share ONE structural root cause — the lowering
handles the direct construct->consume path the corpus exercises but fails when a node is
consumed through a different type-erasing path (cache reuse after type substitution) or
when a repr-polymorphic store omits the `ptrtoint` guard its construction-site analogue
has. These will bite R3/the parser path. Plus dead code (6 orphaned subs) and coverage
gaps (TypedInvariant + read-back).

## Critical Issues

None. (No silent miscompile is reachable by any corpus or currently-producible graph.)

## Important Issues (all CONFIRMED LATENT — fix before the parser emits these shapes)

### [I-A] str_const... no — cache overwrite in `_lower_subscript` corrupts a later PostfixDeref on the same ArrayRef node
- **File:** `lib/Chalk/Target/LLVM.pm:3329-3334` (ArrayRef branch), `:3348-3351` (HashRef branch)
- **Bug:** `_lower_subscript` overwrites `cache{container->id}` from `i8*` to `%Array*`/`%Hash*`.
  A subsequent `lower_value` of that SAME node (e.g. a `PostfixDeref(@$ref)` consuming the
  same `ArrayRef` node) hits the poisoned cache, gets `%Array*`, and `_lower_array_deref`
  emits `bitcast i8* %Array* to %Array*` — an LLVM type error.
- **Why corpus is green:** no corpus case uses one ArrayRef node as BOTH a Subscript
  container AND a PostfixDeref input (R4/R8 deref the result, not the raw ref node).
- **Fix:** don't mutate `cache{container->id}`; pass the resolved `%Array*` to the read
  body directly, or have the read body look up `_arr_table` itself.
- **Confidence:** 90 | **Found by:** Logic, Verifier.

### [I-B] `_lower_assign` array-lvalue store + `_lower_hash_ref` value store omit `ptrtoint` for ref-typed values
- **File:** `lib/Chalk/Target/LLVM.pm:1964` (Assign array-lvalue), `:3239` (HashRef value)
- **Bug:** both emit `store i64 $ref, ...` with no repr guard. If the stored value has
  repr `ArrayRef`/`HashRef`, `$ref` is an `i8*` and `store i64 i8*` is a type error.
  `_lower_array_ref` (3164-3172) DOES `ptrtoint` pointer elements — the asymmetry is the bug.
- **Why corpus is green:** corpus stores only `:Int` element/hash values. R8 nesting goes
  through `_lower_array_ref` (which has the guard), not the hash/assign paths.
- **Fix:** mirror the `_lower_array_ref` ptrtoint guard at both sites (`$rhs->representation
  in {ArrayRef,HashRef}` -> ptrtoint before store).
- **Confidence:** 88 | **Found by:** Logic, Error/Edge, Verifier.

### [I-C] `_lower_length` Str branch emits `extractvalue %StrPair <i8*>` — invalid IR
- **File:** `lib/Chalk/Target/LLVM.pm:3295-3303`
- **Bug:** the Str-length branch does `extractvalue %StrPair $str_ref, 1`, but `lower_value`
  returns `i8*` for Str nodes (the backend tracks length out-of-band in `_str_len_table`,
  never materializes a `%StrPair` SSA value). `extractvalue` on a pointer is invalid LLVM IR.
- **Why corpus is green:** ORCHESTRATOR-VERIFIED — the ONLY `Length` in the entire corpus
  is `Length(%arr) :Int` (references.md R1, Array operand). There is ZERO Length(Str) GREEN
  case; strings.md S5 is `L: GAP`. The specialist's "affects every length($str) in the
  corpus" (conf 100) was a FALSE claim — corrected to latent-with-no-corpus-exposure.
- **Fix:** use the existing `_str_len_for`/`_str_len_table` mechanism (compile-time len, or
  a `getelementptr %StrPair, %StrPair* ..., i32 0, i32 1` + `load` if a real StrPair value
  exists), with a loud GAP die if the length is untracked.
- **Confidence:** 95 | **Found by:** Error/Edge, Verifier.

### [I-D] `_lower_length` Array fallback assumes cache holds `i8*`, but `_lower_array_deref` puts `%Array*` there
- **File:** `lib/Chalk/Target/LLVM.pm:3281-3286` (fallback) + `_lower_array_deref` ~3828-3837 (does NOT populate `_arr_table`)
- **Bug:** `Length(PostfixDeref(@$ref))` i.e. `scalar(@$ref)` — `_arr_table` misses (deref
  never populates it), fallback reads `cache` (which holds `%Array*` after the deref) and
  emits `bitcast i8* %Array* to %Array*` — type error. Same root as I-A.
- **Why corpus is green:** corpus only does `Length(ArrayRef-node)` directly, and
  `_lower_array_ref` populates `_arr_table`, so the fallback is never hit.
- **Fix:** have `_lower_array_deref` (and `_lower_hash_deref`) populate `_arr_table`/
  `_hash_table` the way `_lower_array_ref` does; make the fallback repr-aware (Array operand
  needs no bitcast; only ArrayRef does).
- **Confidence:** 85 | **Found by:** Error/Edge, Verifier.

## Suggestions

- **[S1] Dead code — 6 orphaned subs** (ORCHESTRATOR-VERIFIED 0 call-sites each):
  `_lower_array_literal` (3077), `_lower_array_write` (3445), `_lower_hash_literal` (3492),
  `_lower_hash_write` (3682), `_lower_make_array_ref` (3781), `_lower_make_hash_ref` (3794).
  Helpers for the deleted parallel nodes; `_lower_assign` inlined the write logic. The plan's
  per-phase "Sweep" step should have removed them. Delete all 6 (~250 lines). (Plan-alignment
  agent undercounted as 3; the verified count is 6.) Conf 100.
- **[S2] Stale node-name strings in LIVE GAP messages:** `_require_repr($node,'ArrayRead')`
  at :3373 (in live `_lower_array_read`, reached via Subscript dispatch) and
  `'HashRead'` at :3575. A repr-missing Subscript dies with "GAP: ArrayRead..." — a
  node name that no longer exists. Change to `'Subscript(Array)'`/`'Subscript(Hash)'`. Conf 95.
- **[S3] Stale comment** at :3261 (live `_lower_hash_ref`) names deleted `HashWrite` as a
  consumer; correct is `Subscript`/`Assign(Hash-lvalue)`. (CLAUDE.md: a provably-false comment
  may be corrected.) Conf 95.
- **[S4] Cosmetic `.ll` comment labels:** ~50 `_emit("...; ArrayLiteral:/ArrayRead:/...")`
  strings in the canonical arms still carry old node names in the GENERATED IR comments.
  No semantic effect; contradicts the single-vocabulary goal. Label-cleanup sweep. (Already
  logged in memory `r2_node_convergence_baseline.md`.) Conf 90.
- **[S5] TypedInvariant C5 gap:** no `%OP_REQUIRED_REPR`/`%OP_PER_POSITION_REPR` entry for
  `ArrayRef`/`HashRef` (Phase 2.1) or `Assign`-Subscript-lvalue (Phase 3.1); well-typed-graph.t
  stops at H2-13 (bilateral exists for Length/Subscript/PostfixDeref only). The plan's Phase
  2.1 asked for "elements + resulting repr" check + bilateral. Add ArrayRef/HashRef element-repr
  checks + H2-14..17. Conf 90.
- **[S6] Coverage — R6/R7 element-write don't read back:** references.md R6/R7 return the
  `Assign` node (which returns `$rhs` regardless), not a subsequent `Subscript` read of the
  stored slot. A dropped store would still pass. A19 adds a `like(qr/store i1 true/)` text
  check (partial). Add a write-then-independent-read corpus case. Conf 82.

## Plan Alignment

- **Implemented:** Phase 0 (ScalarLen->Length), 1.1 (ArrayRead/HashRead->Subscript), 1.2
  (ArrayDeref/HashDeref->PostfixDeref), 2.1 (literal/make->ArrayRef/HashRef, I4 honored:
  unboxed %Array is an emitter temp in `_arr_table`, not a node), 3.0 (Assign Subscript-lvalue
  branch + A19), 3.1 (ArrayWrite/HashWrite->Assign). All 11 nodes deleted; NodeFactory clean;
  C1 behavior-unchanged honored; Cluster B (MOP) correctly NOT touched (R3 scope).
- **Deviations:** dead-code sweep incomplete (S1); TypedInvariant per-phase extension missing
  for Phase 2.1/3.1 (S5); stale comments/labels (S2/S3/S4). Phase 3.0-before-3.1 commit
  ordering: confirmed (commit 270131cb precedes 45e33360).

## Review Metadata
- **Agents:** Logic & Correctness, Error Handling & Edge Cases, Contract+Integration+Coverage, Plan Alignment, Verifier.
- **Scope:** lib/Chalk/Target/LLVM.pm, lib/Chalk/IR/Graph/TypedInvariant.pm, lib/Chalk/IR/NodeFactory.pm + 11 deleted node files, t/corpus/mdtest/references.md, t/bootstrap/ir/{llvm-array-hash,well-typed-graph,llvm-method-body-needs}.t.
- **Raw findings:** 14 | **Verified-kept:** 4 Important + 6 Suggestions | **Filtered/downgraded:** 4 (incl. the conf-100 false corpus-wide claim -> latent; one FALSE-POSITIVE reclassified to latent on re-read).
- **Reconciliation:** every "invalid IR" claim checked against references.t 27/27 GREEN — all are LATENT (uncovered path), none LIVE.
- **Steering files:** CLAUDE.md (no contradictions; the dead-code/stale-comment findings align with its drift + comment-honesty rules).
