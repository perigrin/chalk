# Design Brief: Phi / Merge Strategy for Chalk

**Date:** 2026-06-01
**Status:** Decision brief — validated by a two-track investigation + adversarial synthesis. No implementation yet.
**Relationship:** Sibling to `2026-05-31-ir-construction-substrate-design-brief.md` (Option A control-chain work). This brief is the merge/Phi half; that brief is the control half. **They are NOT the same problem** (see §1).

---

## The two questions asked

1. **Is unification smart?** Are the control-chain gap (Option A) and the Phi-merge gap the *same* lateral-propagation problem, such that one during-parse channel should feed both?
2. **Block-args vs Braun?** Independent of (1): should the merge mechanism be Leißa-Griebler block-arguments (Phi-free, "SSA without Dominance for Higher-Order Programs") or Braun-style lazy/explicit Phi?

---

## §1. Unification: NO — false unification

The control-chain and Phi-merge gaps are **categorically different data-flow shapes**, verified in code:

- **control_head** (`SemanticAction.pm` `_mul_ctx`): single-predecessor, monotonic-advance — a scalar "current tail" pointer that moves forward ("non-Start right wins, else left"). Published one node at a time via `update_control_head`.
- **merge / Phi** (`Bindings.pm` `merge_with_phis`/`merge_for_loop`): multi-predecessor convergent — takes 2+ full binding *maps*, iterates the union of variable names, emits a Phi per divergent var. A fold over a set of maps.

Forcing one lateral channel to carry both means carrying "one current control node" AND "the set of all branch-final binding maps" — two payloads, two propagation rules, i.e. not one mechanism.

**Decisive corroboration from our own history:** the C4 audit (2026-05-31, `2026-05-26-scope-control-divorce-plan.md` §C4) already empirically shelved the *control* half of unification. And the scope/control divorce *design* deliberately SEPARATED bindings and control into two Context fields with two `_mul_ctx` rules precisely because bundling them "forces them to share one propagation rule, and neither gets the rule it needs." Unification is the opposite of the shipped direction.

**The legitimate (modest) sense of "unified" that already exists:** both `bindings` and `control_head` ride the *same* Context object and the same `update_*` → `_complete_sa` → `_mul_ctx` transport — **one channel, two fields, separate per-field rules.** That is the correct architecture and it is already in place post-C1/C2. Do NOT build a single combined "current control + current bindings" lateral mechanism.

**Correcting an earlier hunch:** a prior session floated "the Phi-merge gap and the control-chain gap are the same problem, so Option A's fix makes the Phi bug fall out for free." That is FALSE: (a) the control half (Option A rebuild-retirement) is itself parse-time-blocked/shelved per C4, so there's no completed fix for the Phi bug to fall out of; (b) the failing Phi cases are body-internal-resolution problems (a var read inside a loop body / assigned in one branch isn't promoted), orthogonal to lateral propagation of either field.

---

## §2. Block-args vs Braun: a false binary — the answer is a layered hybrid

Chalk's CFG (`Region.pm`, `If.pm`, `Loop.pm`) is classic SoN with explicit control nodes, NOT higher-order "blocks-are-functions." Leißa-Griebler's dominance-free elegance *comes from* the higher-order model; a partial adoption that renames "Phi" to "Region parameter" gains none of that benefit while costing a Region rewrite. So full block-arguments is **dominated** for Chalk.

But the answer isn't "just Braun" either. The right design separates three layers:

- **Representation (graph level): keep the explicit Phi node** (Braun-style). Fits `Phi.pm` (`region` + `inputs[then,else]`/`[pre,backedge]` + `set_backedge`) and Region/If/Loop as built. **LLVM IR has Phi natively**, so keeping the Phi node makes LLVM lowering near-identity; erasing it would force Phi *reconstruction* at the LLVM boundary. The Phi node is the low-friction superset for both targets.
- **Emission (per target): lower Phi to a shared declared-variable slot.** Branches emit plain `Assign` into the pre-existing `my $x`; the Phi is never emitted as a statement. **This is block-arguments operationally, and the live codegen already does it** (`EagerPinning._expand_if`, `Target/Perl._emit_schedule_item` emit branch Assigns into the shared slot). It is the designed-but-unbuilt §4 slot strategy in `2026-05-24-son-scheduler-design.md:636-761`.
- **Construction (timing): the one genuinely open decision — eager vs lazy for loops (see §3).**

So: **Braun's Phi representation, block-arg-via-slot lowering, per-target projection** (Phi→Phi for LLVM; Phi→slot for C/Perl). The LLVM/C target split is benign — it's the normal shape of a lowering pipeline, and it argues for keeping (not erasing) the Phi node.

Confirmed dead code to remove (zero production callers): `emit_cfg_phi_if` (`Target/Perl.pm:1377`, `EmitHelpers.pm:1124` — the synthetic `$_phi_<id>` emitter the design itself calls "bad on the merits") and `EagerPinning::Phi.emit_slot` (the unbuilt slot carrier). Keep the Phi *node type*; delete the synthetic-variable *emitter*.

---

## §3. The real open decision: eager vs lazy construction for loops

The investigation surfaced — and the adversarial synthesis CAUGHT a sub-agent error on — the state of the sentinel/lazy path. **Verified directly this session:**

- `resolve_sentinel` (Braun's read-triggered lazy-Phi creator) **IS wired in production**: `Bindings.pm:109` ← `Actions.pm:201` (`_resolve_from_scope`) ← four variable-read sites (`Actions.pm:1665/1674/1683/1692`). The lazy *read consumer* is live.
- `fork_for_loop` (installs `Sentinel` bindings into a loop body) has **no production caller** (`Bindings.pm:93` def only). The lazy *producer* is dead.

So the sentinel path is **half-wired self-defeatingly**: live consumer, dead producer → `resolve_sentinel` always hits its non-sentinel early return; the lazy-Phi branch is reachable-but-never-triggered. (One sub-investigation claimed the whole path was dead and recommended deletion; that was factually inverted and the synthesis corrected it. Any decision here must account for the four live read sites.)

This means the eager-vs-lazy choice is genuinely undecided, and it touches the plumbing fix: fixing the loop case by populating `merge_for_loop`'s body-final scope commits to **eager**; fixing it by wiring `fork_for_loop` commits to **lazy/Braun**. **Decide this empirically, not by guess** (see §4 Step 2).

---

## §4. Recommended sequencing

**Step 1 — Fix the lateral-propagation bug. Representation-agnostic. First.**
The `bindings` field doesn't propagate body-final/branch-final scope sibling-to-sibling at leaf entry (`Bindings.pm:172-179`: "the loop action sees an empty pre-loop bindings hash"). Both eager-merge and lazy-resolve read the *same* `bindings` field, so this fix is upstream of and invariant to the Phi-vs-block-arg choice. The eager merge methods already build correct Phis in unit tests (`scope-phi-merge.t`, `scope-for-loop-merge.t` pass); they fail end-to-end only because the scope they receive is empty. Fixing delivery unblocks the ~10 TODO tests (`cfg-loop-phi.t`, `postfix-loop-phi.t`, `phi-integration.t`, `scope-if-merge.t`). This is the divorce plan's bindings track, not new architecture.

**Step 2 — Let the post-Step-1 tests decide eager (2a) vs lazy (2b) for loops.**
- **2a (eager):** ensure `merge_for_loop` receives populated body-final scope; then delete the dead `fork_for_loop` + the now-pointless `resolve_sentinel` sentinel branch; the four `_resolve_from_scope` sites collapse to plain lookup.
- **2b (lazy/Braun):** wire `fork_for_loop` into the loop-body action so in-body reads create header-Phis on demand.
- **Diagnostic:** the TODO failures shaped as "a var referenced inside the body isn't promoted" are the test for whether 2a suffices. If Step 1 + eager fixes them → 2a. If in-body reads still fail (a read needs a header Phi before the body-final value exists) → 2b. Do not pre-commit; medium confidence (~65%) it lands on 2a.

**Step 3 — Delete confirmed-dead emit apparatus** (`emit_cfg_phi_if` ×2, `EagerPinning::Phi.emit_slot`) regardless of 2a/2b. Keep the Phi node type. Either finish the §4 slot-resolution or document that codegen intentionally emits shared-slot Assigns and Phi is analysis-only — but don't leave both the dead emitter and the unbuilt slot resolver as ambiguous residue.

## §5. What must NOT be touched yet
- Do NOT build any combined control+merge lateral channel (false unification; C4 shelved the control half).
- Do NOT adopt the Leißa-Griebler higher-order model / parameterize Region (payoff needs the full CFG rewrite Chalk doesn't need).
- Do NOT delete the Phi node type (LLVM wants it; optimizer/scheduler may). Delete only the synthetic-`$_phi_` emitter.
- Do NOT pick the scheduler destination (Click GCM vs Cranelift) now — it's behind the `schedule()` interface (`son-scheduler-design.md` Decision E) and deliberately deferred; deciding it would prematurely force the block-args question, which has no current consumer.

## §6. The do-nothing steelman (largely endorsed)
The representation is already correct for analysis and LLVM (explicit Phi). Emission already does block-arg-via-slot operationally. The only thing actually broken end-to-end is the `bindings` plumbing bug (Step 1). Nothing currently consumes the answer to block-args-vs-Braun, and the scheduler destination is deliberately deferred. So: **fix the plumbing, clean the dead code, defer the representation commitment.** The steelman's one caveat: "do nothing to the representation" must NOT mean "do nothing to the dead/half-wired code" — the half-wired sentinel and dead `$_phi_` emitter are exactly the residue that caused a sub-investigation to misread the architecture this session. Resolve them (Steps 2-3).

## Evidence index
- Unification refutation: `SemanticAction.pm` `_mul_ctx` (single-pred control select), `Bindings.pm:171-212`/`221-255` (multi-pred merge); C4 audit `2026-05-26-scope-control-divorce-plan.md` §C4; divorce design (deliberate separation).
- Representation/backend: `Region.pm:18`, `Phi.pm:9-24`, `EagerPinning.pm` (never references Phi), `son-scheduler-design.md:636-761` (§4 slot strategy) + `:42` (scheduler destinations behind `schedule()` interface).
- Dead code: `emit_cfg_phi_if` (`Target/Perl.pm:1377`, `EmitHelpers.pm:1124`), `EagerPinning::Phi.emit_slot` — zero callers.
- Sentinel half-wiring (verified this session): `resolve_sentinel` live via `Actions.pm:201`/1665/1674/1683/1692; `fork_for_loop` dead (`Bindings.pm:93` def only).
- Construction timing / lazy history: `2026-02-24-lazy-phi-loop-design.md` (sentinel = Click/Simple lazy-Phi; read-trigger landed, fork didn't).
- Raw validation output (3-agent workflow + adversarial synthesis): saved at /tmp/phi-validation-raw.json this session.
