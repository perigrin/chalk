# Chalk v3 — Initial Design (Construction-Layer Reset)

**Date:** 2026-06-05
**Status:** North-star design document. Replaces the original clean-room PRD (a gist, history not spec) as the architectural reference.
**Lineage evidence:** `docs/plans/2026-06-05-v3-design-history-alignment-audit.md` (three era-audits of the full Feb–June decision record), `docs/plans/2026-06-05-context-to-son-postpass-vision-validation.md` (the validated vision), `docs/plans/2026-06-05-clean-control-construction-design.md` (Option X), `paad/architecture-reviews/2026-05-31-chalk-semantic-action-architecture-report.md` (the flaw catalog F1–F17).

## What this is, honestly

This is NOT a from-scratch clean-room reset. By the numbers it is a **construction-layer rewrite**: ~76% of the current tree (~13,500 lines — parser, filter semirings, SoN IR, MOP, backends) is carried forward and validated against as a differential oracle; ~24% (~4,200 lines — SemanticAction, Actions, the Context payload fields) is rewritten. The "reset" is of the *architecture's organizing principle* and the *design document*, not of the codebase. No reader should think the parser, IR, or backends are being discarded.

**This is the FOURTH attempt at the IR-construction layer.** The same root problem has been diagnosed and fixed in-place three times and drifted each time (Feb: chose flat SA-semiring; April: chose enforce-the-contract-in-place; May: chose during-parse threading). v3 must therefore justify why it won't be the third pendulum swing. See Part 0.

## Part 0: Why v3 breaks the loop (read this first)

The history (`v3-design-history-alignment-audit.md`) shows a pendulum:
- **Feb 2026** retired a two-tier "one parse before IR" split and chose SA-as-the-5th-semiring, on the reasoning *"hash-consed IR removes the limitation that forced two-tier."*
- **April 2026** diagnosed the resulting flaw EXACTLY as v3 does (`semiring-contract-drift` + `audit-5`: "the contract covers return shape, not purity; SA-as-semiring is effectful construction") and chose to **enforce the contract in place** (Phase A.2 Decision 4, which explicitly ruled out redesign). It partially executed, then re-drifted — `on_merge` still mutates a hash-consed Context in place at HEAD.
- **May 2026** chose **during-parse lateral control threading** (Option A) and shelved the post-parse fold. It sprang five control leaks across four RED audits.
- **June 2026 (this session)** reversed to the post-parse pass.

**v3's two commitments are NOT new — April named them.** So the only thing that matters is: *why does a rewrite succeed where enforce-in-place and during-parse both drifted?* The answer is a **durable diagnosis that replaces Feb's wrong one:**

> Feb claimed hash-consing was the blocker that justified going flat. That was the wrong diagnosis. The real, orthogonal-to-hash-consing blocker is that **Chalk's semantic-action layer is a pure synthesized-attribute fold (Loup Vaillant Earley model): an action sees only its children's results, with no inherited / left-sibling channel.** The one relationship control wiring needs — a statement node's left-sibling predecessor — is structurally the one a synthesized fold cannot hand across. Hash-consing never addressed this; it is an attribute-grammar-shape property. Every in-place fix (enforce-the-contract, during-parse threading) left construction *inside* the fold and therefore kept fighting this shape — which is why the contract kept drifting and the threading kept leaking.

A post-parse fold over the materialized, source-ordered tree has the left-sibling relationship directly available — it is not fighting the attribute model. **That is the structural reason this is the last swing, not a preference.** The validation (`context-to-son-postpass-vision-validation.md`) confirmed it: disambiguation provably never reads constructed IR (the 4 filters touch zero IR; no action can reject a parse), so construction can move wholly post-parse, and an adversarial search for a hidden big-bang dependency found none.

## Part 1: The two commitments

**Commitment 1 — Every FilterComposite member satisfies an ENFORCED pure Context→Context contract.** Pure (no side effects, no shared-state mutation), hash-cons-stable (identical input pairs return the same object), total, annotation-slot-based (`slot_name()` returns a defined string). "Enforced" means: the composite validates members at construction; a test asserts purity (same `multiply` twice → refaddr-equal result) AND the contract clause April never shipped (`is_zero($x)` iff `$x->is_zero()` for every member); the composite has NO special-case path for any member. Anything that cannot satisfy this — effectful IR construction — is structurally barred from being a semiring. This is April's Decision 4 plus the **purity clause April diagnosed but never enforced**, with the rewrite as the mechanism instead of in-place patching.

**Commitment 2 — IR + MOP construction is a post-parse FOLD over the disambiguated survivor tree, not a semiring.** The parse produces a survivor Context tree carrying annotation tags (no IR). A separate pass folds it into the SoN IR graph and the MOP, with full parent/sibling/child context. The post-pass is the system of record for `control_in` (Option X, already decided + alignment-audited GREEN this session). This deletes the entire downstream flaw cluster: mailbox statics (F2), Context payload hub (F3), Block rebuild god-method (F4), control smear (F5), cfg_state leak (F13), dead back-channels (F6/F8).

## Part 2: The disambiguation output is a SURVIVOR tree with residual shape artifacts — NOT a clean tree

This corrects the premise the May audits falsified (`survivor-list-architecture.md`, `fixup-audit-baseline.md`). The four filters do NOT produce a clean, fully-disambiguated, artifact-free tree:
- The output is packed-ambiguous / multi-survivor in the general case; 9.4% of merges are real Precedence-vs-Structural conflicts; 4,459+ ties exist once product semantics surface them (Boolean's `$left`-by-convention had masked them).
- Every corpus file triggers load-bearing fixups today; at least three classes (bare list-op comma-slurping, method-over-builtin, method-over-deref) are documented as NOT precedence and NOT cleanly filterable — they are IR-SHAPE rewrites, not disambiguation.

**What the fold actually consumes:** the SINGLE WINNING SURVIVOR (the filters reliably pick one and carry all tags; they touch zero IR, so the fold can consume it) — but that survivor's tree shape carries the residual artifacts. **The post-parse fold MUST explicitly own these shape rewrites** (the current `_fix_postfix_chain` / `peel_builtin` / list-op-slurp logic becomes part of the fold's normalization stage), OR each class must be retired into the grammar / a chart-merge preference rule with a named plan. v3 does NOT claim the tree is clean. v3 claims: single survivor + tags + a fold that owns normalization.

**Precondition for the fold (regression gate):** the survivor handed to the fold has a defined, deterministic shape; the fixup-audit baseline (`2026-05-09`) is the gate that measures how much normalization the fold must do. Target: drive corpus fixup classes down by retiring them into grammar/filters where possible, and absorb the irreducible remainder into the fold's explicit normalization stage (not a scattered post-hoc walker).

## Part 3: Decisions kept (settled — carry forward)

Each with a one-line why and the prior decision it honors.
- **Full Aycock DFA (LR0 + distance factoring + Leo).** The hard-won correct parser core; works on the full grammar. (`2026-03-16/24/27/31`; `%waiting_for` eliminated; static C DFA tables for determinism.)
- **Four pure filter semirings (Boolean, Precedence, TypeInference, Structural) + slot-based FilterComposite.** Verified zero IR-touches; open/closed; the Goodman 5-op API already shipped (`on-complete-elimination`, commit 6c77c805). (`2026-02-19`, `2026-04-12`.)
- **TypeInference is annotation-only flow typing** (not IR-reading); its 2026-02-20 "Future Work: post-parse type inference walking the annotated tree" is the earliest seed of v3's fold.
- **Sea-of-Nodes IR: hash-consed immutable data nodes (content-based ids), counter-id'd CFG/position nodes, `control_in` as a hash-EXCLUDED per-use decoration.** Node types If/Region/Phi/Loop/Proj kept. (Proposal-2 uniformity: VarDecl/Return/Unwind carry control in `control_in`, committed 8c6cfe0f/d01bfea3.)
- **MOP (graph-of-graphs): root owns per-method/sub/phaser IR::Graph; structure outside the graph; closed-world.** Shape kept (`2026-04-20`); construction moves to the fold.
- **Multi-backend codegen (Perl, C/XS; LLVM planned): emit from IR + MOP, target-agnostic IR.** chalk.so + per-class XS (NOT multi-class). (`2026-03-19/24`, `2026-04-21`.)
- **Determinism: byte-identical codegen.** Sort hash iteration; content-based ids; stable position-derived naming. (`2026-03-31`.)
- **Phi node + shared-slot emission** (explicit Phi at graph level → declared-var slot at codegen). (`emit_cfg_phi_if`.)
- **EagerPinning scheduler as a PLACEHOLDER.** O(n) chain-walk; GCM deferred. No architecture decision anchors on it; `control_in` correct at hand-off is the contract. (`2026-05-23/24`.)

## Part 4: Mistakes baked out (the F1 cluster) — with their prior diagnoses cited

- **Mistake 1 (root, diagnosed 2026-04-24/25): no enforced Context→Context contract → SA violated purity invisibly.** FIX = Commitment 1 (enforce, with the purity clause April skipped). The concrete still-live channel to delete: the TI→SA `set_type_context` "mailbox" (`FilterComposite.pm`, `SemanticAction.pm`) and SA's MOP/NodeFactory mutation during parse.
- **Mistake 2 (symptom cluster): SA-as-semiring (effectful during parse).** FIX = Commitment 2 (post-parse fold). Deletes mailbox (F2), Context payload hub (F3), Block rebuild (F4), control smear (F5), cfg_state (F13).
- **Smaller anti-patterns to avoid:** dead back-channels with no consumer (F6 `_transferred_scope`, F8 dead `error` field) — never add a channel without a confirmed reader; process-global per-parse config (F11) — per-parse state in per-parse instances; wrong-direction dependency (F12) — the action table calling back into the semiring engine; `(rule_name, alt_idx)`-keyed dispatch fragility (`option-b postmortem`) — the fold keys on STABLE rule identity; untested load-bearing construction code (F16) — isolated unit tests from day one.

## Part 5: The anti-F1 structural property (why F1 is impossible by construction)

Two properties, both enforced (not convention — convention failed three times):
1. **The contract is checked at the composite boundary.** A member without a defined `slot_name()` / hash-cons stability / purity cannot be added; the test harness rejects it immediately. There is no fifth special-cased member.
2. **Construction lives in a separate pass with a separate input (the immutable survivor tree) and separate output (the graph), sharing NO mutable channel with the parse.** Construction cannot influence parse acceptance (runs after); the parse cannot observe construction (filters touch zero IR — verified). A future developer cannot add effectful "during-parse IR construction" as a semiring (contract check rejects it) or through Context (no shared mutable channel). The only place construction can live is the fold — where it belongs.

This is the property all three prior in-place fixes lacked: they left construction inside the fold, so the barrier never existed.

## Part 6: Pipeline shape and boundary contracts

```
Perl source (string)
  → [Scannerless Earley: Aycock DFA + Leo; FilterComposite over 4 pure filters]
  → SURVIVOR Context tree: {focus token, ordered children, position, rule,
      annotations{boolean,precedence,type,structural}}. No IR. Single survivor
      + tags. May carry residual SHAPE artifacts (Part 2).
  → [Post-parse Context→SoN fold]: normalization (owns the shape rewrites) →
      build SoN IR graphs (per method/sub body) + MOP. Sets control_in by
      source-order walk (system of record). Explicit graph-membership merge.
  → Chalk::IR::Program (MOP root + attached graphs): correct+complete control_in,
      hash-consed data nodes, all statement nodes in $graph->nodes.
  → [Optimizer passes] (DCE, StructPromotion, peephole) over the completed graph.
  → [EagerPinning scheduler] (placeholder; reads control_in as ground truth).
  → [Backend codegen] (Perl, C/XS): byte-identical output.
```

## Part 7: Migration / execution stance — strangler-fig against the oracle

The current tree is the **differential oracle**: every new component is gated on byte-identical-or-justified-divergence against it. AI-economics make reimplementation cheap, so the design doc is the whole risk surface and the oracle is the safety net.

**Reusable as-is (carry, do not rewrite):** LR0DFA, Earley (minus the lateral-seed channel we delete), the 4 filter semirings, FilterComposite (minus SA special-casing), IR node types + NodeFactory + Graph, MOP + subtypes, both backends, EagerPinning (as placeholder).

**Newly built:** the post-parse Context→SoN fold (replaces SA + Actions); the slimmed Context (drops graph/bindings/factory/control_head/mop fields — they become the fold's working state, NOT Context fields; this REVERSES `unified-context-design` and v3 owns that reversal: the fold removes the need to thread construction state through Context, and cfg-coherence is guaranteed by the fold's single-pass ownership rather than a side-table).

**Phases (each gated on FULL suite == baseline, not a curated list — the B1 lesson):**
1. **Build the F16 unit harness FIRST** — direct Context-tree → IR/graph assertions, no full-pipeline dependency. This is the prerequisite that makes the rewrite safe; without it the migration rides only on goldens (the documented 80-90%-drift trap).
2. **Build the fold for control constructs** (the Option X slice — narrowest, most-proven), validate against goldens with the old SA path running as cross-check oracle.
3. **Move construction family-by-family** (control → MOP builders → expression/node builders), each behind golden + unit gates, old path as oracle until each family flips.
4. **Delete** SA-as-semiring, mailbox statics, Context payload fields, FilterComposite SA special-casing, the during-parse lateral-seed channel + `one_with_control`, `on_merge`, residual `should_scan`/`cfg_state` read-shim.
5. **Carried-debt retirement (enumerate, do not assume done):** codegen `MethodInfo->body` → graph-walk; `compat_class` field + StructPromotion reader; 4 dead IR node types; write-only `If/Loop->region`/`control_in`; cfg_state read-side shim + 4 consumers. Each gets a retirement gate.

## Part 8: Toolchain decisions (DEFERRED — needs research)

perigrin wants the reset to also re-set tooling: **Crochet, git-zhi, PAAD, etc.** This is well-timed (a reset is the cheapest moment to adopt new tooling — no retrofit friction). PAAD (the agentic-review/audit methodology used throughout this session) is low-risk to formalize — it is methodology, not code-coupling. Crochet and git-zhi need investigation before being baked in (what each is, what it changes about build/test/VCS workflow). This part is a PLACEHOLDER: toolchain decisions are made with the same rigor as architecture decisions, in their own investigation, and folded in here. Do not scatter tooling choices as implementation detail.

## Part 9: Explicitly out of scope / deferred
- GCM or alternative scheduler (EagerPinning is the placeholder; `control_in`-correct-at-hand-off is the contract; design against concrete GCM requirements when GCM is active).
- Eager-vs-lazy loop Phi timing (NOTE: `2026-02-24-lazy-phi-loop-design` already decided LAZY, then EagerPinning shipped; v3 must pick the BASELINE explicitly — current code is eager-pinning, so the v3 baseline is EagerPinning's behavior, and lazy-Phi is a deferred optimization, not a silent re-opening). Decide empirically when loop optimization is active.
- LLVM backend (planned; the multi-backend abstraction supports it).
- ExpressionList≥2 grammar refactor (DO NOT resurrect — rolled back, `option-b postmortem`).

## The two commitments, restated
1. Every FilterComposite member is a pure, hash-cons-stable, annotation-slot Context→Context function, ENFORCED at the composite boundary. Effectful IR construction cannot be a semiring.
2. IR + MOP construction is a post-parse fold over the survivor tree (which the fold normalizes), with no shared mutable channel back into the parse, and isolated unit tests from day one.

Everything else follows from these or is carry-forward of what works. The durable reason this is the last swing of the pendulum: the synthesized-attribute fold structurally cannot carry control's left-sibling channel, and only a post-parse pass over materialized source order can — a fact orthogonal to the hash-consing argument that drove the Feb reversal.
