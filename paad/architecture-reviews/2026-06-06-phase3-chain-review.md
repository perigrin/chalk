# Chain Review: Reshaped Phase-3 Chain (LLVM Reframe)

**Date:** 2026-06-06
**Reviewer:** crochet-style chain-review (alignment + pushback), pre-execution gate.
**Method note:** the dispatched `project-plan-reviewer` agent could verify the
DESIGN DOCS but could not read git-zhi issue bodies (no git-zhi-capable tool in
that agent's sandbox). The AC-layer verification + the fixes below were completed
by the orchestrator reading the bodies directly via `git zhi issue show`.

## Scope
Chain: Phase 3a–3e + Phase 4 (B::SoN) + Phase 5 (capstone) under milestone
`codegen-harness`, decomposing `docs/plans/2026-06-06-three-axis-codegen-and-typed-ir-contract.md`
+ `docs/architecture/typed-ir-representation.md` (model, with architecture-review
holes H1/H2/H3/M1/M3 closed).

## Top-line verdict

**READY TO EXECUTE** — after one advisory was folded in during review (the
false-green guard, below). 3a is the sole ready head.

## Two-layer verification

### Layer 1 — design docs (verified by the dispatched reviewer)
All five architecture-review holes are CLOSED in the model doc and the closures
are precise: H1 (representation OUT of content_hash, per-use like `control_in`;
same-literal-two-reps reconciled by Coerce-on-edge), H2 (well-typed-graph
checkable invariant), H3 (Scalar = GAP not libperl on the L corner + mandatory
runtime-free coverage metric), M1 (Int overflow-to-NV guard), M3
(DualVar/Bool/Undef/Ref → Scalar guards). Code reality confirmed: `representation`
and `Coerce` do not yet exist (3a adds them); `control_in`/`schedule_data` are
the hash-excluded precedent (`Node.pm:31,39`); `const_type` is in-hash but does
not distinguish i64/double (model's claim accurate); `Phi.set_backedge` mutates
inputs post-construction (`Phi.pm:18-23`) — confirms the M2 Coerce-on-backedge
ordering risk is real (carried as a 3a/3c design note, not a blocker).

### Layer 2 — issue ACs (verified by orchestrator reading bodies)

**3a (019e9eda-2cf8) — STRONG.** Every load-bearing item is a concrete AC:
- C1 no-libperl: explicit NEGATIVE AC — "assert the generated .ll contains NO
  perl C-API calls (no `Perl_`, no `SV`)." ✅
- C2 well-typed-graph invariant: AC "rejects a malformed graph (operand repr !=
  op requirement, no Coerce)" + a malformed-graph test. ✅
- C3 coverage/Scalar=GAP: present. ✅
- H1 representation out-of-hash: AC "EXCLUDED from content_hash... a test that two
  same-content nodes with different representation intent do not fork identity";
  Coerce from/to "ARE in its identity hash." ✅
- perl sole oracle: explicit (`== perl`). ✅

**3b (019e9eda-2d19) / 3d (019e9eda-2d57) — GAP FOUND AND FIXED.** The false-green
guard (no-libperl negative AC + coverage metric) was present in 3a but NOT
propagated as explicit negative ACs into 3b (where slice-wide verdicts are
assigned) and 3d (where the LLVMDriver is built). This is exactly the reviewer's
CRITICAL-C1 concern. **Resolved during review:** appended a "Negative Scenarios
(false-green guard, propagated from 3a)" block to both — 3b: an L-GREEN idiom
whose .ll contains any Perl_/SV call must be GAP, and L-GREEN requires 100%
runtime-free coverage; 3d: the LLVMDriver runs lli on a libperl-free .ll and the
L record carries the coverage fraction, so P=L on a mostly-Scalar L is not valid
agreement. Verified present after the edit.

## Dependency DAG (verified via JSON)
3a (ready; blocked_by done Phase-1 epic) → 3b → 3c → 3d → 3e; Phase 4 blocked_by
3d; Phase 5 blocked_by Phase 4. Linear, acyclic, no reversed edges. 3a is the
sole ready head of the chain.

## Cancelled-issue hygiene (reviewer flagged zombie risk) — CLEAN
The two old C-corner issues (019e9a95-3682, 019e9a95-9af7) AND the mis-titled old
capstone (019e9a95-f912 "Phase 4: self-host the Earley parser") are all
`state=cancelled` (verified) — not lingering as open work. Tagged superseded.

## Advisories (non-blocking, for the executor)
- **3a sizing:** bundles representation field + Coerce node + lowering pass +
  invariant checker + lli harness — dense, but honestly a bounded one-idiom spike
  (like the D1/Add spikes). Expect it to be the heaviest single issue; if it
  doesn't validate cleanly first try, split along the bundle.
- **3c is an epic** (plumb representation across the node model; likely needs its
  own representation-lattice design doc — already noted in 3c's body). Frame as
  iterative, not a single sitting.
- **Phase 5 capstone is an epic**; Phase 4 (B::SoN) scope correctly deferred till
  Phase 3 lands and carries the directional-not-trusted framing.
- **M2 (Coerce-on-Phi-backedge ordering):** real (`Phi.set_backedge` mutates
  post-construction); surfaces in 3c when control idioms get representation.
  Carried as a design note, not a blocker for 3a (literal slice has no Phi).

## Bottom line
The chain faithfully decomposes the reviewed design; all load-bearing invariants
are now encoded as checkable ACs (the one gap — false-green guard in 3b/3d — was
closed during this review); the DAG is correct; superseded issues are genuinely
cancelled. **READY TO EXECUTE, starting with 3a.**
