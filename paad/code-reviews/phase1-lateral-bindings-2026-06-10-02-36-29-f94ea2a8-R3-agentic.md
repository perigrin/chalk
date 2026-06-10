# Agentic Code Review: phase1-lateral-bindings (R3 IR-taxonomy reconciliation)

**Date:** 2026-06-10 02:36:29
**Branch:** phase1-lateral-bindings -> ff9b4d08 (R3 start)
**Commit:** f94ea2a8593fb6954dba00f44944ffdce8d78004
**Files changed:** 28 | **Lines changed:** +1783 / -872
**Diff size category:** Large

## Executive Summary

R3 converges the 7 parallel G5 MOP/dispatch IR nodes (ClassDecl/MethodDef/FieldDef/
AdjustBlock/New/MethodCall/FieldWrite) onto the single canonical vocabulary
(ClassInfo + Call(method)/Call(new)/FieldAccess/Assign-over-lvalue), folds in the
R2-reopen V1-V5 hash-store/read ptrtoint fixes, and updates the docs. The
convergence is mechanically sound: the ClassInfo registry path reproduces the
deleted ClassDecl path's registry shape (method order, vtable_slot numbering,
:reader synth, :isa flatten), all 7 node `.pm` files + NodeFactory registrations
are cleanly removed, and the corpus + LLVM-MOP + well-typed-graph gates are GREEN
with **zero new regressions** (all 5 self-hosting-tier/mop failures are exact
known-baseline). The 6-specialist + verifier review confirmed **7 findings, none
Critical and none live** — every one is latent (no corpus/test path triggers it),
and one (F-FIELD-STR-STORE) is a pre-existing gap carried forward from the deleted
code, not a regression. Highest-value items: the Str/ref field-store payload
asymmetry, the Assign-over-lvalue hash-cons drop-store risk, and the deferred C5
TypedInvariant coverage gap.

**DISPOSITION (2026-06-10):** Both Important code findings were FIXED in this
change-set (TDD, RED test first):
- **I1** fixed — the FieldAccess-lvalue store now builds a `%StrPair` for a Str rhs
  (matching the read path) and `ptrtoint`s an ArrayRef/HashRef rhs; pinned by a new
  `llvm-mop-classes.t` Str-field-store-in-method round-trip (`Str:hi`, lli==perl).
- **I2** fixed — `Assign` over a `Subscript`/`FieldAccess` lvalue now gets per-call
  identity in `NodeFactory` (like the deleted FieldWrite/element-write), so identical
  adjacent stores stay distinct; pinned by new `t/bootstrap/ir/assign-lvalue-identity.t`
  (scalar-rebind Assign still hash-conses — preserved).
- **I3** (C5 TypedInvariant) remains deferred to `019eaf54` per perigrin.
The 4 Suggestions (S1-S4) are deferred to the follow-up issue.

## Critical Issues

None found.

## Important Issues

### [I1] FieldAccess-lvalue field store has no Str/ref payload handling (asymmetric with the read path)
- **File:** `lib/Chalk/Target/LLVM.pm` `_lower_assign` FieldAccess-lvalue branch (~1959-1964)
- **Bug:** The field-store branch coerces only `Bool` (`zext i1`) and an `else` identity `add i64 0, $rhs_ref`. A `Str` rhs is an `i8*`, so `add i64 0, <ptr>` is invalid IR; `ArrayRef`/`HashRef` rhs gets no `ptrtoint` guard, unlike the sibling Subscript-lvalue (~2006-2016) and hash-lvalue (V1, ~2086-2096) store branches. The field READ path (`_lower_field_access_in_method`) reads a `:Str` field via `inttoptr i64 -> %StrPair*`, and `_lower_call_new` builds a `%StrPair` for `:param` Str fields — so the Assign-FieldAccess-lvalue store is the divergent path.
- **Impact:** Storing a `Str` (or a ref) into a field inside a method/ADJUST body, then reading it, produces invalid IR or a type-corrupt StrPair read. ADJUST blocks computing derived Str fields would hit this.
- **Regression vs pre-existing:** **PRE-EXISTING GAP carried forward** — the deleted `_lower_field_write_method_body`/`_with_obj` had the identical Bool/`else add i64 0` logic with no Str handling. R3 preserved the behavior; it did not introduce the gap.
- **Latent:** `classes.md` only stores `:Int` fields; no corpus/test stores a Str or ref field outside the constructor.
- **Suggested fix:** Mirror `_lower_call_new`'s StrPair allocation in the FieldAccess-lvalue branch (and register `_str_len_table`), add the `ptrtoint` guard for `ArrayRef`/`HashRef`, or die loudly on `$val_repr eq 'Str'`/ref until modelled. Add an lli round-trip test that writes a `:Str` (and a ref) field in a method/ADJUST body and reads it back.
- **Confidence:** 80 (Medium)
- **Found by:** Concurrency & State, Logic & Correctness (2 agents)

### [I2] Assign-over-lvalue field/element stores are content-hash-consed; identical adjacent stores collapse (drop-a-store)
- **File:** `lib/Chalk/IR/NodeFactory.pm` (per-call-identity allowlist, ~254-285) + `lib/Chalk/IR/Node.pm` (content_hash, control_in excluded ~30/37)
- **Bug:** The deleted `FieldWrite` had per-call identity (each store a distinct side-effecting op). Its R3 replacement `Assign(FieldAccess-lvalue, value)` goes through the content-hashed `make()` path — `Assign` has no `content_hash` override (`operation | serialized_inputs` only), and `control_in` is excluded from the hash by design. So two byte-identical field-store statements (same `field_index`/`field_stash` lvalue, same constant RHS) in one body collapse to one node, dropping a store.
- **Impact:** A latent miscompile (one of two identical stores silently dropped).
- **Regression vs pre-existing:** The same is already true of element stores (`$a[$i]=v`), so R3 *widened* the class to field writes rather than introducing it.
- **Latent:** requires literally-identical lvalue + RHS (distinct fields have distinct FieldAccess lvalues; only same-field same-constant repeats collide). No corpus case triggers it.
- **Suggested fix:** Decide the contract — if duplicate side-effecting lvalue-stores must stay distinct, add `Assign`-over-lvalue to the per-call-identity allowlist (when `inputs[0]` is a Subscript/FieldAccess lvalue), or fold `control_in` into the lvalue-Assign hash. At minimum document why hash-consing identical stores is safe here.
- **Confidence:** 72 (Medium)
- **Found by:** Contract & Integration

### [I3] C5 plan gap: TypedInvariant not extended for the R3 canonical ops (deferred)
- **File:** `lib/Chalk/IR/Graph/TypedInvariant.pm`, `t/bootstrap/ir/well-typed-graph.t`
- **Bug:** The plan's C5 requirement + acceptance criterion (plan line 424) mandate per-phase TypedInvariant extension + bilateral `well-typed-graph.t` cases for the array/hash/**method/field/compare/logical** ops. R3 changed TypedInvariant only to *skip* metadata objects (a guard, not an extension). `%OP_REQUIRED_REPR`/`%OP_PER_POSITION_REPR` still cover only Add/Subtract/Multiply/Divide/Modulo/Concat/Length/Subscript/PostfixDeref — no entry for `Call(method)` (invocant repr = Object), `FieldAccess`, `Assign`, `ArrayRef`, or `HashRef`. `well-typed-graph.t` has zero Call/FieldAccess/Assign cases (27/27 pass on the existing ops).
- **Impact:** A mistyped Call/FieldAccess/Assign operand would not be caught by the well-typed-graph invariant. No correctness impact today (the invariant is a defense-in-depth check, and lowering still loud-dies on bad repr via `_require_repr`).
- **Disposition:** **EXPLICITLY DEFERRED** to git-zhi issue `019eaf54` ("R3 cleanup: S2-S6 cosmetic labels + TypedInvariant coverage"), filed 2026-06-10. NOTE for in-repo discoverability: `019eaf54` is a git-zhi tracker id (refs/zhi/*), not grep-able from the worktree — consider citing it in the plan or a code comment so the deferral link is visible in-repo (CLAUDE.md plan-discipline: unlabeled deferrals become drift).
- **Confidence:** 85 (High — confirmed real gap; tracked deferral, not unaccounted drift)
- **Found by:** Plan Alignment

## Suggestions

- **[S1] `Call(name='new')` routed to construction by name only** (`LLVM.pm:_lower_call_method` ~3831; `NodeFactory.pm` per-call-identity): a user instance method literally named `new` (inputs[0]=object, not ClassInfo) would be misrouted to construction. Latent (no corpus class defines method `new`). Fix: disambiguate on `inputs[0]->isa('Chalk::IR::ClassInfo')`. (Logic + ErrorHandling, conf 70)
- **[S2] MOP::Field builder silently drops `:param`/`:reader` on non-`"true"` values** (`MdtestCorpus.pm:577-579`): `param: 1`/`True`/`yes`/typo silently becomes false, no croak. Test-harness only. Fix: croak on anything other than `true`/`false`/absent. (ErrorHandling, conf 88)
- **[S3] `adjusts` not dedup-guarded** (`LLVM.pm:_populate_registry_from_classinfo` ~312-317): methods/fields grep-dedup, `adjusts` uses unconditional push; two distinct same-name ClassInfo objects would double-append ADJUST bodies. The `%visited{id}` guard blocks same-id reprocessing; the divergent-same-name case is the residual risk. Latent/defensive. (Concurrency, conf 62)
- **[S4] Class/method/field names interpolated raw into LLVM identifiers** (`LLVM.pm` `%${cname}.vt`, `@${cname}__vtable`, etc.): no `\w+` charset guard, while string *content* uses `_encode_c_string`. A name with a newline/quote/LLVM-metachar breaks the IR. Latent (normal pipeline names are `\w+`; only the corpus harness could author a bad name). Fix: a one-line `^\w+$` die at the name choke points, matching the file's loud-GAP convention. (Security, conf 65)

## Plan Alignment

- **Implemented:** 7 parallel nodes deleted (.pm gone + NodeFactory clean); Target::LLVM lowers canonical nodes + the MOP/ClassInfo layer; F9 dissolved (field store = Assign(FieldAccess-lvalue) carrying field_stash; class no longer from ambient mode); Phases 4+5 landed as one coherent set (Call.target/param_names); corpus ir-blocks use only canonical nodes; Phase 6 docs (sea-of-nodes-ir.md LLVM-lowering section, typed-ir-representation.md realized lattice + struck Coerce Q2/Q3, Node.pm repr comment).
- **Not yet implemented (deferred, neutral):** C5 TypedInvariant extension for Call(method)/FieldAccess/Assign/ArrayRef/HashRef + bilateral well-typed-graph.t cases — deferred to issue `019eaf54` (see I3). S2-S6 cosmetic `.ll` labels + R6/R7 read-back coverage — same issue.
- **Deviations:** None contradicting the plan. The S2-S6/C5 deferral is labeled to `019eaf54` (a git-zhi tracker id, not in-repo-grep-able — see I3 note).

## Review Metadata

- **Agents dispatched:** Logic & Correctness, Error Handling & Edge Cases, Contract & Integration, Concurrency & State, Security, Plan Alignment (+ Verifier).
- **Scope:** `lib/Chalk/Target/LLVM.pm`, `t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm`, `lib/Chalk/IR/{ClassInfo,MethodInfo,Node,NodeFactory}.pm`, `lib/Chalk/IR/Node/Call.pm`, `lib/Chalk/IR/Graph/TypedInvariant.pm`, `t/corpus/mdtest/classes.md`, the 4 new + several migrated `t/bootstrap/ir/*.t`, the doc updates — changed + adjacent.
- **Raw findings:** 7 (across 6 specialists).
- **Verified findings:** 7 (3 Important, 4 Suggestion).
- **Filtered out:** 0 (all confirmed by reading code; none live, none Critical).
- **Steering files consulted:** CLAUDE.md (project + global), MEMORY.md index.
- **Plan/design docs consulted:** `docs/plans/2026-06-08-ir-taxonomy-reconciliation.md`.
