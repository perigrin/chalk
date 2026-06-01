# Why Chalk Uses a Braun/Leißa-Griebler Hybrid for SSA Merges

**Date:** 2026-06-01
**Status:** Rationale document — the principled justification for Chalk's merge-representation choice. Intended to be paper-ready (a follow-up paper could be built on this), so it argues the *general* case, not only the Chalk-specific one, and states threats to validity.

> **Citation-verification caveat (read first):** the technical characterizations of Braun et al. and Leißa-Griebler below are written from working knowledge; the source PDFs were not machine-readable at authoring time. Every claim attributed to a paper is marked ⟨verify⟩ until checked against the primary source. Do not publish any ⟨verify⟩ claim without confirming it. The *architectural* claims about Chalk are verified against code (file:line cited).

---

## 0. Thesis in one paragraph

A compiler that constructs SSA *during a single parse pass* and targets *both* a Phi-native backend (LLVM) and a Phi-free backend (C / Perl source) is best served by **decoupling the merge into three independent layers** — representation, emission, and construction-timing — and choosing each layer on its own merits rather than adopting one SSA-construction paper wholesale. Chalk's resulting choice — **an explicit Phi node at the IR level (after Braun), lowered to per-predecessor assignments into a shared slot at emission (the operational content of Leißa-Griebler block arguments), with construction timing decided empirically** — is not a compromise between two papers but a recognition that the two papers answer *different questions* and Chalk has *both* questions.

The contribution worth writing up is precisely that framing: **representation, emission, and construction are orthogonal axes of SSA "form," and conflating them is why "which SSA paper should I use?" is the wrong question.**

---

## 1. The two papers answer different questions

### Braun et al., "Simple and Efficient Construction of SSA Form" (CC 2013)
⟨verify⟩ Braun is about **construction**: how to *build* SSA on the fly, per basic block, via `readVariable`/`writeVariable`, inserting Phi nodes lazily when a read crosses a block boundary, using "sealed blocks" and "incomplete Phis" to handle not-yet-known predecessors (loops), and recursively removing trivial Phis (`tryRemoveTrivialPhi`). Its headline result: minimal SSA for reducible CFGs **without computing dominance frontiers** (contra Cytron et al.). ⟨/verify⟩

Braun keeps **explicit Phi nodes**. Its question is *when and how do I create them cheaply, in one pass, without dominance precomputation.* That is a **construction-timing + construction-mechanism** answer. It says nothing about how Phis are *represented downstream* or *emitted* — it assumes the IR has Phi instructions and stops there.

### Leißa, Griebler (& Hack), "SSA without Dominance for Higher-Order Programs"
⟨verify⟩ Leißa-Griebler eliminates Phi nodes entirely by modeling basic blocks as **functions** and merges as **block parameters**: a predecessor "passes an argument" by jumping/calling with values, and the merge block names them as formal parameters. Dominance never needs computing because the higher-order (functional / CPS-ish) structure subsumes it — scoping is lexical in the nested-function structure. ⟨/verify⟩

Leißa-Griebler is about **representation**: it changes *what a merge is* (a parameter, not a Phi instruction). Its dominance-freedom is a *consequence of the representation*, not of a construction trick. Its question is *what should the IR look like so that merges and scoping fall out of ordinary function structure.*

### The category error these papers invite
Both are routinely cited as "how to do SSA," which tempts a reader to pick one. But:
- Braun answers **construction** (assuming Phi representation).
- Leißa-Griebler answers **representation** (and gets construction-simplicity as a side effect of the higher-order model).

They are not competing answers to one question. They are answers to two of the **three** questions any during-parse SSA builder must answer:

1. **Representation** — is a merge a Phi node, or a block parameter? *(Leißa-Griebler's domain.)*
2. **Emission** — how does the merge become target code (a Phi instruction? per-edge assignments to a shared location?)
3. **Construction timing** — when are merges materialized (eagerly at the merge point? lazily on first read across a boundary?) *(Braun's domain.)*

A compiler can mix-and-match these. The "hybrid" is not splitting the difference between two papers; it is **answering three orthogonal questions, each with the locally-correct answer, where two of those answers happen to originate in different papers.**

---

## 2. Why Chalk must keep an explicit Phi node (the representation axis)

The decisive constraint is **multi-target lowering**:

- **LLVM IR has `phi` natively.** If the Chalk IR carries no Phi node (full block-arguments), then targeting LLVM requires *reconstructing* Phi nodes at the LLVM boundary — i.e. re-deriving the merge structure the block-argument form deliberately dissolved. That is work, and it is the exact work Leißa-Griebler's representation was designed to avoid having to *do* — except here we'd be doing it *backwards* (block-args → Phi) at the worst possible place (codegen).
- **C and Perl source have no merge construct at all.** A merge becomes per-predecessor assignment to a shared variable (`my $x` written in each branch; the join reads `$x`). This *is* the operational content of a block parameter: each predecessor "passes its argument" by writing the shared location.

So the two backends pull in opposite directions: LLVM wants Phi; C/Perl want per-edge assignment. The representation that is the **low-friction superset of both** is the explicit Phi node, because:
- Phi → LLVM `phi` is near-identity (keep it).
- Phi → C/Perl is "lower each Phi to per-edge assignments into a shared slot" (drop it; the branches already carry the assignments).

A block-argument IR would make C/Perl trivial but LLVM costly; a Phi IR makes LLVM trivial and C/Perl a standard lowering. Since LLVM is a named Chalk target and Phi-reconstruction-at-codegen is the more error-prone direction, **Phi-as-representation dominates** for a Phi-native-plus-source multi-target compiler.

**Why not adopt the full Leißa-Griebler higher-order model anyway?** Its elegance (dominance-freedom) is a *theorem about the representation*: it holds because blocks are functions. Chalk's IR is classic Sea-of-Nodes with explicit `Region`/`If`/`Loop` control nodes (`Region.pm:18` is a bare merge node with a `head` back-pointer and no parameter list). Adopting block-arguments *partially* — renaming a Phi's operands to "Region parameters" while keeping Region as a plain merge node — gains **none** of the dominance-free benefit, because that benefit requires the whole higher-order CFG, not the parameter syntax. You would pay a CFG rewrite and get a Phi with a different field name. So: take Leißa-Griebler's **operational lowering** (per-edge assignment), not its **IR model**.

---

## 3. Why the emission layer is block-argument-shaped (the emission axis)

Independently of representation, the *emission* of a merge to C/Perl is per-predecessor assignment into a shared slot — and **Chalk's live codegen already does exactly this** (verified): the schedule-driven emitter (`EagerPinning._expand_if`, `Target/Perl._emit_schedule_item`) emits each branch's `Assign` into the pre-existing `my $x` slot and never emits a Phi statement. The SSA-out is implicit in the branch bodies.

This is the operational definition of a block parameter: the merge block's "parameter" is the shared slot; each predecessor's "argument pass" is its assignment. So Chalk's emission is *already* Leißa-Griebler in content, expressed in Phi-lowering vocabulary. The designed-but-unbuilt slot-resolution strategy in `son-scheduler-design.md:636-761` (§4) formalizes this: the Phi is never emitted as a statement; it resolves to the source `VarDecl`'s slot, and branches stay as plain `Assign`s.

The honest framing for the paper: **the IR keeps Phi for analysis and LLVM; emission to a Phi-free target is Phi-elimination-to-shared-slot, which coincides with block-argument lowering.** One representation, two projections.

(Confirmed dead, to be removed: the synthetic `$_phi_<id>` emitter `emit_cfg_phi_if` in `Target/Perl.pm:1377` and `EmitHelpers.pm:1124`, and the unbuilt `EagerPinning::Phi.emit_slot` carrier — zero callers. These are a *third*, worse emission strategy (materialize a synthetic merge variable) that the design itself calls "bad on the merits." Their existence as dead code is residue, not a chosen option.)

---

## 4. Why construction timing is a separate, empirically-decided axis (the construction axis)

Braun's contribution is on this axis: lazy, read-triggered Phi creation with sealed blocks. Chalk's *current* construction is the opposite — **eager** merge at the If/Loop completion (`merge_with_phis`, `merge_for_loop` in `Bindings.pm`), building a Phi for every variable differing across branches, with immediate trivial-Phi removal (`_remove_trivial_phi`, a single-shot non-recursive analog of Braun's `tryRemoveTrivialPhi`).

Crucially, **construction timing is independent of both representation and emission.** You can build Phi nodes eagerly or lazily; either way they're Phi nodes (representation) lowered to slots (emission). So Chalk does not have to take Braun's *timing* to use Phi *representation*.

Whether eager or lazy is right for Chalk is **genuinely open and should be decided empirically**, because:
- Eager fits the synthesized-attribute fold: at If/Loop completion the branch bodies have completed (bottom-up), so their branch-final scopes are available — a pure synthesized operation. This is why the eager merge methods pass their unit tests.
- Lazy (Braun) triggers Phi creation on a *read inside a block before the value exists* — which needs an inherited per-block "current SSA value" channel. Chalk's fold is synthesized-only; a piece of the lazy path (`resolve_sentinel`, the read trigger) is in fact wired in production (`Actions.pm:201` ← variable-read sites 1665/1674/1683/1692), but its producer (`fork_for_loop`, which installs the loop-body sentinels) is dead, so the lazy branch never fires. The path is half-built.

The deciding test: after the orthogonal lateral-propagation bug is fixed (see §5), do the in-loop-body-read cases resolve under eager merge, or do they require a header Phi materialized before the body-final value exists? If eager suffices → delete the half-built lazy path. If in-body reads genuinely need lazy header-Phis → finish Braun's lazy construction. **This is the one place Chalk might adopt Braun's actual mechanism, and only if measurement demands it.**

---

## 5. The confound that must not contaminate the rationale: the lateral-propagation bug

A *third* thing is currently broken and is **orthogonal to all three axes**: Chalk's `bindings` Context field does not propagate branch-final / body-final scope laterally at leaf entry (`Bindings.pm:172-179` — "the loop action sees an empty pre-loop bindings hash"). This starves the merge methods of their inputs, so merges silently produce nothing end-to-end (~10 TODO tests) even though they work in isolation.

For the paper this matters because it would be easy — and wrong — to attribute the merge failures to the construction strategy and conclude "eager doesn't work, switch to Braun." The failures are a *plumbing* defect in an unrelated layer (the synthesized fold's lateral binding propagation, the subject of the separate "Option A" work). **The merge representation/emission/construction choice is independent of, and must be evaluated after, fixing this bug.** Stating this prevents the classic confound of blaming the SSA algorithm for a delivery bug.

---

## 6. The general claim worth publishing

> SSA "form" is not one decision but three orthogonal ones — **representation** (Phi node vs block parameter), **emission** (Phi instruction vs per-edge assignment to a shared location), and **construction timing** (eager-at-merge vs lazy-on-read). The SSA-construction literature largely fixes representation and emission implicitly and varies construction (Cytron, Braun), or varies representation and lets construction follow (Leißa-Griebler). A multi-target, single-pass compiler whose backends disagree on the merge construct (LLVM wants Phi; source targets want assignment) should decouple the three axes and choose each independently. The locally-correct choices — Phi representation (for the Phi-native backend), block-argument-shaped emission (for the Phi-free backends), and empirically-selected construction timing — read as a "Braun/Leißa-Griebler hybrid," but the hybrid is an artifact of the literature attaching each axis to a different paper, not a designed compromise.

### Threats to validity / reviewer attacks to preempt
1. **"This is just standard Phi-lowering; nothing new."** Partly fair — Phi→assignment lowering is textbook. The contribution is the *framing* (three orthogonal axes) and the observation that the multi-target setting makes the "which SSA paper" question ill-posed, plus the during-parse construction-timing independence. Position modestly: an experience/insight paper, not a new algorithm.
2. **"Why not just use block-arguments everywhere and lower to Phi for LLVM?"** Must quantify the cost of block-args→Phi reconstruction vs Phi→assignment lowering and argue the latter is simpler/less error-prone. ⟨needs measurement to be defensible⟩
3. **"Eager construction isn't minimal SSA; Braun is."** True — eager-at-merge can create dead Phis that Braun's read-driven construction wouldn't. Chalk mitigates with trivial-Phi removal, but does not claim minimality. Either claim non-minimal-but-cheap, or adopt Braun's recursive `tryRemoveTrivialPhi` to recover minimality — and be explicit which.
4. **Reducibility.** Braun's minimality guarantee is for reducible CFGs ⟨verify⟩. Chalk's source language (restricted Perl subset) — characterize its CFG reducibility; if all constructs are structured (if/while/for, no goto), the CFG is reducible and the guarantee applies.
5. **Generality beyond Chalk.** The three-axis framing should be shown on at least one other compiler's choices (e.g. Cranelift = block-args representation + block-args emission; LLVM frontends = Phi representation + Phi emission; a transpiler = Phi or block-args representation + assignment emission) to argue it's not a Chalk idiosyncrasy.

---

## 7. Decision record (the Chalk-specific bottom line)

| Axis | Choice | Origin | Why |
|------|--------|--------|-----|
| Representation | Explicit Phi node | Braun-class / classic SoN | LLVM-native; fits Region/If/Loop/Phi as built; superset for multi-target |
| Emission | Per-edge assignment into shared slot | Leißa-Griebler operational content | C/Perl have no merge construct; live codegen already does it; LLVM keeps Phi |
| Construction timing | Eager-at-merge (provisional); lazy only if measurement demands | Eager = Chalk current; lazy = Braun | Eager fits the synthesized fold; decide empirically post-plumbing-fix |
| (Confound) Lateral-propagation bug | Fix first, axis-independent | — | Must not be misattributed to the SSA strategy |

**Do not:** adopt the full higher-order CFG model; erase the Phi node type; pick scheduler destination now; build a combined control+merge channel (separate false-unification finding).

Companion documents: `docs/plans/2026-06-01-phi-merge-strategy-brief.md` (the decision brief), `docs/plans/2026-05-31-ir-construction-substrate-design-brief.md` (the orthogonal control-chain / Option A work), `docs/plans/2026-05-24-son-scheduler-design.md` §4 (the slot-emission strategy).
