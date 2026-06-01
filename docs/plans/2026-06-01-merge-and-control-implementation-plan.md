# Implementation Plan: Lateral Binding Propagation, Control-Chain Threading, and Merge Strategy

**Date:** 2026-06-01
**Branch:** `fixup-audit-baseline` (or a fresh feature branch off it)
**Status:** Implementation plan. Executes the decisions validated in the design briefs.

**Decision provenance (read these first):**
- `docs/plans/2026-05-31-ir-construction-substrate-design-brief.md` — Option A: control chain via during-parse lateral threading (validated flat + nested).
- `docs/plans/2026-06-01-phi-merge-strategy-brief.md` — merge = Phi node + shared-slot emission; eager-vs-lazy is empirical.
- `docs/2026-06-01-merge-representation-rationale.md` — the three-axis framing.

**Mandate (per CLAUDE.md):** strict TDD; invoke `writing-perl-5.42.0` + `test-driven-development` before any code. Perl 5.42.0 via pvm. Test green at every step; commit frequently. Do NOT `--no-verify`.

---

## The unifying insight this plan executes

Three things looked like separate problems; the investigation proved one is the **shared root cause**:

> **The `bindings` Context field does not propagate branch-final / body-final scope sibling-to-sibling at leaf entry** (`Bindings.pm:171-179`). This single defect starves BOTH the merge methods (→ ~12 TODO Phi tests fail end-to-end) AND is the same class of gap the control chain has (→ the Block rebuild exists).

So the plan is ordered to fix the root first, then build on it. The phases are sequenced by dependency, and the eager-vs-lazy loop-Phi decision (Phase 3) is deliberately deferred until Phase 1 data exists.

**Three orthogonal axes (do not conflate during execution):**
1. **Lateral propagation bug** — Phase 1 (representation-agnostic).
2. **Control-chain threading / Option A** — Phase 2 (retire the Block rebuild).
3. **Merge construction timing** — Phase 3 (eager vs lazy, empirical).
Plus: **emission + dead-code cleanup** — Phase 4.

`control_head` and merge are NOT unified (false unification, per the brief); they share transport (one Context) but keep separate per-field rules. Do not build a combined channel.

---

## Baseline capture (one-time, before Phase 1)

- [ ] **B1: Record current TODO inventory** (the green target). As of 2026-06-01:
  - `scope-if-merge.t`: 16 tests, 2 TODO, 0 real-fail
  - `cfg-loop-phi.t`: 21 tests, 4 TODO, 0 real-fail
  - `postfix-loop-phi.t`: 7 tests, 2 TODO, 0 real-fail
  - `phi-integration.t`: 15 tests, 4 TODO, 0 real-fail
  - Total: **12 TODO cases** to convert to passing.
- [ ] **B2: Record control-chain baseline.** The Block rebuild (`Actions.pm:1567-1651`) fires in 22/46 blocks (C4 audit). `bnf-target-c.t` 178/178; `mop/codegen-byte-compat.t` 19/19; `mop/*` green. These must stay green throughout.
- [ ] **B3: Confirm pre-existing failures** (unrelated, must not regress): `xs-polymorphic-dispatch.t` 59/60, `xs-int-specialization.t` 2/6.

---

## PHASE 1 — Fix lateral binding propagation (the shared root cause)

**Goal:** make branch-final and body-final `bindings` reach the If/Loop actions, so `merge_with_phis`/`merge_for_loop` receive populated scopes. Representation-agnostic — does not decide Phi-vs-anything. Unblocks the 12 TODO tests using the *already-correct* eager merge methods.

**Why this is the root:** `Bindings.pm:171-179` documents the symptom directly ("the loop action sees an empty pre-loop bindings hash, while the body leaf has captured the post-body Assigns"). The merge methods pass their unit tests (`scope-phi-merge.t`, `scope-for-loop-merge.t`) — they only fail end-to-end because the scope they're handed is empty.

### Task 1.1: Characterize the propagation gap precisely (no code yet) — DONE 2026-06-01

**FINDING (corrects the plan's and `Bindings.pm:171-179`'s premise):** the merge methods are NOT starved of input. `merge_with_phis`/`merge_for_loop` receive correct, populated branch/body-final scopes and **build the correct Phi** on the loop/if statement's own result Context (verified by instrumentation). The Phi is then **CLOBBERED** when `_mul_ctx` merges that statement with its preceding sibling: `_merge_bindings` (`SemanticAction.pm:113-117`) does `$right->merge($left)`, and `Bindings::merge` makes the **argument win** → **left (earlier) sibling wins for duplicate names**. So `my $x=0; loop{ $x=... }` resolves `$x` to the pre-loop VarDecl, not the loop's Phi. This is backwards for SSA: the **later** sibling holds the more-recent value and must win.

**Fix site: the sequential bindings reconciliation in `_mul_ctx`** (`SemanticAction.pm:128`), NOT leaf collection (works), NOT the publish path (works), NOT control_head.

**REFINEMENT (post-investigation, verified by orchestrator):** do NOT flip the shared `_merge_bindings` helper globally. Its other caller is `on_merge` (`SemanticAction.pm:536`), whose result (`_transferred_scope`) is **write-only dead code** (0 readers, confirmed in the earlier architecture audit) — so flipping wouldn't break `on_merge`, but the legacy left-wins behavior was *deliberately preserved* in C3 and something else may rely on it. **Localize the change:** make `_mul_ctx` reconcile bindings with **right-precedence at its call site** (e.g. `$left->merge($right)` or a right-wins variant), leaving `_merge_bindings`'s shared semantics untouched. Smallest, safest change.

**Stale residue to revisit (not necessarily this task):** the `Bindings.pm:171-179` comment and the `merge_for_loop` `all_names` union it justifies are likely redundant once precedence is fixed — but verify before removing; the union may still be load-bearing for the nested case.

**Per-test RED guide (simplest first):** `phi-integration.t` test 5 or `cfg-loop-phi.t` test 8 (single var, single loop, no nesting) — Foreach builds `$x`/`$sum` Phi, clobbered by the leading `my` VarDecl. `scope-if-merge.t` test 7 (if/else both assign `$x`) — same clobber. **`cfg-loop-phi.t` test 16 (nested loops) is a DISTINCT sub-gap** (inner-body ref → outer loop) — the precedence fix alone will NOT fix it; per Task 1.4 it likely belongs to Phase 3.

### Task 1.2: RED — un-TODO one representative test per shape
- [ ] Pick the simplest currently-TODO case from each shape: one if/else merge (`scope-if-merge.t`), one loop-carried var (`cfg-loop-phi.t`), one accumulator (`phi-integration.t`). Remove the `# TODO` marker so it's a hard failure. Run; confirm each fails for the *expected* reason (merge received empty/incomplete scope → no Phi built), not some other reason.

### Task 1.3: GREEN — fix the propagation, minimally
- [ ] Implement the smallest change that delivers body-final/branch-final bindings to the merge methods. Watch the three un-TODO'd tests go green. Do NOT touch control_head, the Block rebuild, or Phi representation.
- [ ] Run the full `mop/*` + `bnf-target-c.t` suite — must stay green (no regression).

### Task 1.4: Convert the remaining TODO cases
- [ ] Un-TODO the rest of the 12 cases one at a time; for each, either it now passes (remove TODO, commit) or it reveals a *distinct* sub-gap (document it; it may belong to Phase 3's eager-vs-lazy decision — specifically the "in-body read needs a header Phi before body-final exists" cases).
- [ ] **Decision gate for Phase 3:** classify each remaining-failing case as "fixed by eager merge once scope arrives" (Phase 1 closes it) vs "needs lazy header-Phi / in-body read resolution" (Phase 3, eager-vs-lazy fork). Record the split — this is the empirical input the merge-strategy brief defers to.

### Task 1.5: Commit Phase 1
- [ ] Commit: lateral bindings propagation fixed; N of 12 TODO cases converted; remaining cases classified for Phase 3. Suite green.

---

## PHASE 2 — Control-chain threading (Option A); retire the Block rebuild

**Goal:** thread `control_head` laterally so each statement action receives its predecessor's materialized node, building the control chain correctly on the first try. Retire the ~90-line Block rebuild (`Actions.pm:1567-1651`). Validated viable (flat + nested) by the Option A spikes.

**Depends on Phase 1?** Partially independent (control_head ≠ bindings), but sequence after Phase 1 so the bindings field is stable and the two field-propagation rules aren't being changed simultaneously.

**The three routing rules the threading must reproduce (from the nesting spike):**
1. Linear chain (flat case).
2. Region-advance: advance the parent chain past `$s->region` for If/Loop, not the If/Loop node (`Actions.pm:1671`).
3. Inner-block-tail-leak suppression: an inner block's tail control_head must not leak up into the enclosing control statement's predecessor.
Plus: propagate the in-flight `graph` to trailing siblings.

### Task 2.1: Instrument + characterize (temporary, reverted)
- [ ] Re-confirm against current code (post-Phase-1) the three routing rules and the graph-propagation gap, via env-gated instrumentation. Revert before implementing.

### Task 2.2: RED — a control-chain unit test that fails without threading
- [ ] Write a focused test (the gap the Option A brief noted: no behavioral unit spec exists for the rebuild — `c-schedule-tail-control.t` only covers an if-tail). Construct flat + nested bodies; assert each side-effect node's `inputs[0]` points at its true predecessor. With the rebuild still present this passes; **temporarily disable the rebuild** to confirm the test then fails — proving it tests the threading, not the rebuild.

### Task 2.3: GREEN — implement lateral control threading
- [ ] Thread `control_head` across StatementList siblings (in `_mul_ctx` or at StatementList completion — Task 2.1 decides which) implementing rules 1-3 + graph propagation. Statement actions stop guessing `// make('Start')` and receive the real predecessor.
- [ ] Keep the rebuild in place initially; assert threading produces the SAME chain the rebuild does (differential check).

### Task 2.4: Retire the rebuild
- [ ] Delete the rebuild loop (`Actions.pm:1567-1651`). Run full suite (`bnf-target-c.t`, `mop/codegen-byte-compat.t`, all `mop/*`, the Phase-1-converted Phi tests). All green at baseline counts.
- [ ] If any regression: the threading missed a routing rule the rebuild covered — restore, find the gap, fix, retry. (The nesting spike says all cases are determinate, so a regression means a missed *rule*, not an impossible case.)

### Task 2.5: Commit Phase 2
- [ ] Commit: control chain built during-parse via lateral threading; Block rebuild retired; suite green. Update `block_action_workaround_accretion.md` memory note (workaround #1 resolved).

---

## PHASE 3 — Decide and implement merge construction timing (eager vs lazy)

**Goal:** settle the one genuinely-open axis using Phase 1's empirical data, and clean the half-wired sentinel path accordingly.

**The fork (from the merge brief):**
- **3a EAGER** (if Phase 1 closed all merge cases with populated scope): keep `merge_with_phis`/`merge_for_loop`; **delete the dead lazy path** — `fork_for_loop` (`Bindings.pm:93`, no production caller) and the now-pointless Sentinel branch of `resolve_sentinel`. Account for the 4 live `_resolve_from_scope` read sites (`Actions.pm:1665/1674/1683/1692`) — they collapse to plain lookup.
- **3b LAZY** (if Phase 1 left "in-body read needs header Phi" cases): wire `fork_for_loop` into the loop-body action so reads create header Phis on demand — completing Braun. Consider whether `_remove_trivial_phi` needs to become recursive (Braun's `tryRemoveTrivialPhi`) for minimality.

### Task 3.1: Read the Phase 1 decision gate
- [ ] From Task 1.4's classification: are there remaining "in-body read before body-final exists" cases? If none → 3a. If yes → 3b.

### Task 3.2a (if eager): delete the dead lazy path
- [ ] RED: confirm a test pins "in-loop variable read resolves correctly" under eager. GREEN: delete `fork_for_loop` + Sentinel branch + `Bindings/Sentinel.pm`; collapse the 4 read sites. Suite green. Note: `scope-sentinel.t` will need deletion/rewrite (it tests the deleted path) — handle like the C3 control-input.t deletion.

### Task 3.2b (if lazy): wire the producer
- [ ] RED: the failing in-body-read cases. GREEN: install sentinels in the loop-body scope (`fork_for_loop` at loop entry); confirm reads trigger header Phis. Make `_remove_trivial_phi` recursive if minimality testing requires. Suite green.

### Task 3.3: Commit Phase 3
- [ ] Commit with the empirical rationale recorded (which fork, why, citing the Phase 1 data). Feed the outcome back to issue #735 (the paper's construction-timing data point).

---

## PHASE 4 — Emission cleanup (dead Phi apparatus)

**Goal:** remove confirmed-dead emission code; keep the Phi node type; either finish or document the slot-emission. Representation stays Phi; emission stays shared-slot (already live).

### Task 4.1: Delete the synthetic-`$_phi_` emitter
- [ ] Remove `emit_cfg_phi_if` (`Target/Perl.pm:1377`, `EmitHelpers.pm:1124`) and `EagerPinning::Phi.emit_slot` (`lib/Chalk/Scheduler/EagerPinning/Phi.pm`) — all zero-caller. Suite green (nothing consumes them). Do NOT delete `Chalk::IR::Node::Phi` — LLVM/optimizer want it.

### Task 4.2: Resolve the slot-emission ambiguity
- [ ] Either (a) finish the designed §4 slot-resolution (`son-scheduler-design.md:636-761`) — populate the Phi→source-VarDecl-slot mapping codegen reads — or (b) document explicitly that codegen intentionally emits shared-slot Assigns and the Phi is analysis/LLVM-only. Do not leave both the dead emitter and the unbuilt resolver as ambiguous residue.

### Task 4.3: Commit Phase 4
- [ ] Commit. Update `phi_merge_strategy` memory note: emission cleaned, representation = Phi-node + slot-emit confirmed in code.

---

## Sequencing rationale + guardrails

- **Phase 1 first** because it's the shared root cause and representation-agnostic; both the Phi tests and (indirectly) the cleanliness of Phase 2 depend on a stable `bindings` field.
- **Phase 2 before 3** so the two field-propagation rules (control_head, bindings) aren't both in flux at once.
- **Phase 3 is data-gated on Phase 1** — do not pre-decide eager vs lazy.
- **Phase 4 anytime after Phase 3** (it depends on which merge path survives).

**MUST NOT (per the briefs):**
- Do not build a combined control+merge lateral channel (false unification; C4 shelved the control half).
- Do not adopt the Leißa-Griebler higher-order model / parameterize Region.
- Do not delete the `Phi` node type.
- Do not pick the scheduler destination (GCM vs Cranelift) — behind the `schedule()` interface, deferred.

## Acceptance criteria
- [ ] All 12 previously-TODO merge tests pass (or any genuinely-out-of-scope ones explicitly re-TODO'd with a tracked reason).
- [ ] Block rebuild deleted; control chain built during-parse; `bnf-target-c.t` 178/178, `mop/codegen-byte-compat.t` 19/19, all `mop/*` green.
- [ ] Eager-vs-lazy decided with recorded empirical justification; the not-chosen path's dead code removed.
- [ ] Dead Phi emission apparatus removed; Phi node type retained.
- [ ] Pre-existing failures unchanged (`xs-polymorphic-dispatch.t` 59/60, `xs-int-specialization.t` 2/6).
- [ ] Memory notes + issue #735 updated with outcomes.
