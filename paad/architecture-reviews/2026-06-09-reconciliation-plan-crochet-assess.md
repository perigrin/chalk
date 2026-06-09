# crochet:assess — Target-Layer Reconciliation Plan (as PRD)

**Date:** 2026-06-09
**PRD:** `docs/plans/2026-06-08-ir-taxonomy-reconciliation.md` (revised, HEAD f4149ea4)
**Codebase:** /home/perigrin/dev/chalk/.claude/worktrees/pu
**Chain:** codegen-harness milestone (restored 2026-06-09; new ids `019eaa51-*`)
**Spec-quality gate:** SATISFIED by the prior architecture review (11 findings) +
project-plan-reviewer (5 Critical + 8 Important), both folded into the revised plan.
This assess focuses on gap analysis (Ready/Partial/Missing/Blocking) + chain placement.

## Assessment summary

The plan is **mostly Partial** against the code — the canonical IR targets it converges
onto ALL EXIST as nodes; the gap is that the LLVM backend doesn't *lower* them, and the
gate/invariant guards are thin. There are **2 Blocking** architecture conflicts, **2
genuine Missing** capabilities (the ir-block syntaxes), the rest Partial, and several
Ready foundations to build on.

---

## Ready (code already satisfies)

1. **Canonical node taxonomy exists** — `Subscript`, `PostfixDeref`, `ArrayRef`,
   `HashRef`, `Call`, `FieldAccess`, `Length`, `Assign` all present
   (`lib/Chalk/IR/Node/*.pm`, 8/8 confirmed). The plan converges ONTO these; they don't
   need creating, only LLVM-lowering. *Evidence: ls of the 8 .pm files.*
2. **`Call` is dispatch-ready** — carries `dispatch_kind` ('method'/'sub'/'builtin'),
   `name`, and a late-bound `target` (MOP::Method) with `set_target`
   (`Call.pm:23,35,49`). Phase 5 (method dispatch onto Call) lands on an abstraction
   that EXISTS and is parser-populated. *Ready — the deleted-Shim design is in place.*
3. **`FieldAccess` carries field_index + field_stash** — the field-addressing the
   plan's Phase 4.4 needs (`FieldAccess.pm`). Field READ is Ready; only field WRITE
   (Assign-over-lvalue) is new.
4. **`Coerce` node + repr-out-of-content_hash discipline** — the typed-rep model is
   done right (`Coerce.pm`, `Node.pm:41-52`); the plan explicitly protects it. Ready.
5. **MOP/metadata layer exists** — `MOP::Class`/`Field`/`Method`/`Phaser::Adjust` +
   immutable `ClassInfo`/`MethodInfo` (with id()/add_consumer). Phase 4 CONSUMES these;
   they're Ready as inputs (the conflict is HOW — see Blocking).
6. **LLVMGapMap classifies MISCOMPILE correctly** (`LLVMGapMap.pm` records
   L-GREEN/GAP/MISCOMPILE; `lli_exit!=0 → MISCOMPILE`). Phase G.1's job is to ALIGN the
   corpus gate (`MdtestCorpus`) to this existing-correct classifier — the correct
   behavior already exists in one harness. Ready as the alignment target.
7. **TypeTag single-source compare oracle** (`t/lib/.../TypeTag.pm`, pinning test).
   The libperl-free guard (Phase G.2) plugs into this. Ready foundation.

## Partial (extend existing)

1. **LLVM lowers ONLY parallel nodes; canonical nodes have ZERO arms** — the central
   Partial. `Target::LLVM` dispatches ArrayRead/HashRead/MethodCall/etc. but has no
   arms for Subscript/PostfixDeref/ArrayRef/HashRef/Call/Length. *Extension: add the
   canonical-node lowering arms (Phases 0-5), reusing the existing `_lower_array_read`
   etc. bodies.* The lowering LOGIC exists; it's attached to the wrong node names.
2. **TypedInvariant covers 6 ops** (Add/Sub/Mul/Div/Mod/Concat — confirmed). *Extension
   (Phase G.3, per-phase): add the array/hash/method/field/compare/logical operand-rep
   checks.* The mechanism is wired into the corpus gate already; only the table is thin.
3. **libperl-free guard exists per-test, inconsistently** — `unlike(qr/Perl_/)` in 5/12
   corpus .t files, varying regexes. *Extension (G.2): ONE central harness guard.*
4. **`Length` node exists but is DEAD** (no producer, no LLVM arm) while `ScalarLen`
   duplicates it. *Extension (Phase 0): give `Length` a repr-aware arm, delete ScalarLen.*
5. **`Chalk::Bootstrap::Target` base exists** but LLVM doesn't inherit it and uses a
   divergent interface (`lower` vs `generate`). *Extension (namespace section): promote
   to `Chalk::Target`, reconcile the interface.*

## Missing (new work — no code exists)

1. **`Assign(Subscript/FieldAccess-lvalue)` ir-block syntax + lowering** — `build_graph_
   from_ir` has no lvalue-store form, and `_lower_assign` has no element/field-store
   branch (it does scalar-rebind only). The plan specifies this (Phases 3.0/4.4). Truly
   new. *Suggested: extend `_build_node_from_rhs` + add the `_lower_assign` store branch.*
2. **`ClassInfo`/`MethodInfo`-as-ir-block-input syntax** — `build_graph_from_ir` has no
   way to carry a MOP metadata object into a graph. The plan specifies it (Phase 4.0).
   New. *Suggested: a ClassInfo(...) recognizer in `_build_node_from_rhs`.*
3. **Parser→graph→LLVM equivalence test** — none exists (the corpus is the sole
   producer). The plan (I3) resolves this AS the corpus-rewrite itself (not a new test)
   + a deferred future parser-test. So not Missing-blocking; a deliberate non-deliverable.

## Blocking (must resolve first — architecture conflicts)

1. **The stalled SoN-MOP migration** (`docs/plans/2026-04-21-chalk-mop-migration-plan.md`,
   ~30-40% done). Phase 4 must CONSUME `ClassInfo`/`MOP::Class` for class structure
   WITHOUT wiring the stalled migration's internals. The conflict: `class-scope-vars.t`
   already fails at `MOP/Class.pm:100` (the migration surface). *Resolution: Phase 4.0
   consumes the immutable `ClassInfo` (id()/add_consumer) as a node input only —
   explicitly avoiding the migration internals; the plan states this. The migration
   itself is NOT a prerequisite, but Phase 4's "consume MOP" must be carefully bounded
   to the immutable read-only surface. BLOCKING in the sense that mis-scoping it pulls
   in the stalled migration.*
2. **The two-tier IR is parser-unreachable + backend-only** — the convergence wires
   canonical nodes to LLVM, which is the moment a future parser's output and the corpus
   spec could diverge (F11). Not a code conflict to refactor-away, but a sequencing
   constraint: the convergence MUST land before G6/G7 build more parallel-tier lowering.
   *Resolution: the plan sequences this reconciliation BEFORE G6/G7 (correct).*

---

## Chain placement (where this belongs in the codegen-harness milestone)

**Current frontier (recovered chain):** G6 regex = IN-PROGRESS (spike done, paused);
G5b/G7 = pending (G5b ready, G7 blocked by G6); the GAP-clearing epic = pending; G2-G5
+ follow-ups = done.

**Where the reconciliation belongs:** a NEW issue (or small chain: Phase-G issue +
convergence issue + namespace issue) that lands **BEFORE G6 and G7**. Rationale (from
the plan + the reviews):
- G6's `RegexMatch` is taxonomy-conformant, but G6/G7 will ADD LLVM lowering; building
  it on the parallel vocabulary + the un-hardened gate compounds the drift the
  reconciliation fixes (F11 + F3/F4).
- So: PAUSE G6 (already paused), insert the reconciliation as a prerequisite of G6/G7,
  execute Phase G → namespace → Phases 0-5 → docs, THEN resume G6.

**Overlap/conflict with existing chain issues:**
- **No overlap** with the deferred G5b (overload/tie) — orthogonal (vtable dispatch,
  not node taxonomy). G5b stays deferred/pending.
- **Sequencing dependency on G6/G7** — the reconciliation should be wired as
  `blocks G6` and `blocks G7` (G6/G7 blocked_by the reconciliation), so the chain
  enforces "reconcile before more lowering."
- The historical done issues (G2-G5) are the SOURCE of the drift the reconciliation
  fixes — no conflict, they're closed.

**Suggested chain edit:** add the reconciliation issue(s) to codegen-harness; set
G6 (`019eaa51-c48d`) and G7 (`019eaa51-bd3e`) blocked_by the reconciliation; the
reconciliation itself blocked_by nothing (it can start now — Phase G first).

## Net
The plan is executable AFTER specifying the 2 Missing ir-block syntaxes (the plan
already does, in I1/I2) and bounding the 1 Blocking MOP-consumption to the immutable
surface (the plan states this). It builds on a strong Ready foundation (canonical nodes
+ Call dispatch + Coerce + the MOP layer + the correct MISCOMPILE classifier all exist).
The bulk of the work is Partial — re-pointing existing lowering logic from parallel
node names onto canonical ones + hardening the gate. Place it before G6/G7 as the
plan directs.
