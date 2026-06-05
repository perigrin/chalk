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
- **April 2026** diagnosed the resulting flaw EXACTLY as v3 does (`semiring-contract-drift` + `audit-5`: "the contract covers return shape, not purity; SA-as-semiring is effectful construction") and chose to **enforce the contract in place** (Phase A.2 Decision 4, which explicitly ruled out redesign). It partially executed, then re-drifted — at HEAD `on_merge` still runs as an effectful side-channel (it writes to the dead `_transferred_scope` annotation, SemanticAction.pm:562/569 — a contract violation, though it no longer mutates Context identity in place, which it cannot since the caller holds the reference), and SA still mutates the MOP/NodeFactory during parse (verified).
- **May 2026** chose **during-parse lateral control threading** (Option A) and shelved the post-parse fold. It sprang five control leaks across four RED audits.
- **June 2026 (this session)** reversed to the post-parse pass.

**v3's two commitments are NOT new — April named them.** So the only thing that matters is: *why does a rewrite succeed where enforce-in-place and during-parse both drifted?* The answer is a **durable diagnosis that replaces Feb's wrong one:**

> Feb claimed hash-consing was the blocker that justified going flat. That was the wrong diagnosis. The real, orthogonal-to-hash-consing blocker is that **Chalk's semantic-action layer is a pure synthesized-attribute fold (Loup Vaillant Earley model): an action sees only its children's results, with no inherited / left-sibling channel.** The one relationship control wiring needs — a statement node's left-sibling predecessor — is structurally the one a synthesized fold cannot hand across. Hash-consing never addressed this; it is an attribute-grammar-shape property. Every in-place fix (enforce-the-contract, during-parse threading) left construction *inside* the fold and therefore kept fighting this shape — which is why the contract kept drifting and the threading kept leaking.

A post-parse fold over the materialized, source-ordered tree has the left-sibling relationship directly available — it is not fighting the attribute model. **That is the structural reason this is the last swing, not a preference.** The validation (`context-to-son-postpass-vision-validation.md`) confirmed it: disambiguation provably never reads constructed IR (the 4 filters touch zero IR; no action can reject a parse), so construction can move wholly post-parse, and an adversarial search for a hidden big-bang dependency found none.

## Part 1: The two commitments

**Commitment 1 — Every FilterComposite member satisfies an ENFORCED pure Context→Context contract.** Pure (no side effects, no shared-state mutation), hash-cons-stable (identical input pairs return the same object), total, annotation-slot-based (`slot_name()` returns a defined string). "Enforced" means: the composite validates members at construction; a test asserts purity (same `multiply` twice → refaddr-equal result) AND the contract clause April never shipped (`is_zero($x)` iff `$x->is_zero()` for every member); the composite has NO special-case path for any member. Anything that cannot satisfy this — effectful IR construction — is structurally barred from being a semiring. This is April's Decision 4 plus the **purity clause April diagnosed but never enforced**, with the rewrite as the mechanism instead of in-place patching.

**Commitment 2 — IR + MOP construction is a post-parse FOLD over the single unambiguous survivor tree, not a semiring.** The parse (four pure filters) produces a single unambiguous survivor Context tree carrying annotation tags (no IR — verified at HEAD, Part 2). A separate pass folds it into the SoN IR graph and the MOP, with full parent/sibling/child context. The post-pass is the system of record for `control_in` (Option X, already decided + alignment-audited GREEN this session). This deletes the entire downstream flaw cluster: mailbox statics (F2), Context payload hub (F3), Block rebuild god-method (F4), control smear (F5), cfg_state leak (F13), dead back-channels (F6/F8).

## Part 2: The four filters produce a SINGLE UNAMBIGUOUS SURVIVOR tree (verified at HEAD)

**The earlier draft of this section claimed the parse output was packed-ambiguous with load-bearing IR-shape fixups, based on the May-2026 `survivor-list-architecture.md` / `fixup-audit-baseline.md`. That claim is STALE and was falsified by direct instrumentation at HEAD (d87b7ccf). The four pure filters DO produce a clean, unambiguous, single-survivor parse.** The robustness/audit/oracle work done after the May audit is what got us here, and it belongs in this design as a settled result.

Verified at HEAD (instrumentation, not inference):
- **BPTS parser (Boolean+Precedence+TypeInference+Structural, NO SemanticAction) yields a single survivor on every May-flagged hard case** — `push @arr, $x` (list-op slurp), `$obj->method()->@*` (method-over-deref), `f g X` / `f { } g X` (list-op nesting), ternary, `grep { } @nums` (BLOCK LIST), `bar(foo())`, precedence chains, subscript/method chains. All `is_ambiguous()=false` at top, **zero packed-ambiguous nodes nested anywhere.**
- **Zero `is_ambiguous` Contexts are ever constructed**, at any level, in any probed parse (wrapped `Context->new` across the full pipeline: 0 ambiguous Contexts; wrapped `_pack_survivors`: 0 multi-survivor packs).
- **Disambiguation is genuinely exercised and never abstains:** ~110 merge calls on a 5-construct sample resolved to 1 explicit filter verdict + 109 deterministic identity tie-breaks, **0 abstention packs.** The single survivor is the product of real filter work, not a recognizer silently dropping alternatives. The 4,459 "ties" the May audit surfaced resolve deterministically (identical annotation slots → identity tie-break); they do NOT produce packed survivors.
- **The `_fix_postfix_chain` / `peel_builtin` / `_push_methodcall_inward` / `_push_deref_inward` "load-bearing fixups" the May audit cited DO NOT EXIST at HEAD.** Commit `38e6af60` (2026-05-19, "delete dead `_fix_postfix_chain` walker scaffolding") deleted them: all 4 transformation branches fired ZERO times across the 105-file corpus per the May-09 baseline; the "251k fires" was an aggregate node-visit counter (pure walking overhead), not transformations. Only stale comments remain.
- **The Earley.pm:1116-1125 "Phase 4 stopgap: if packed-ambiguous, pick first survivor" is DEAD defensive code** on the real corpus — it can only fire when the top result `is_ambiguous`, and no ambiguous Context is ever created.

**What the fold consumes: a single, deterministic, unambiguous survivor tree carrying all filter annotation tags, with zero IR.** The fold has full parent/sibling/child context and chooses among no alternatives.

**Distinction the fold must keep clear (the one real thing remaining):** the fold still owns legitimate **IR-CONSTRUCTION / NORMALIZATION** concerns — implicit-return synthesis, control-flow schedule collection, control-chain threading (the work currently in `_finalize_body_graph` / Block). This is graph CONSTRUCTION over the single survivor, NOT disambiguation-residue shape rewriting. v3 must NOT motivate the fold by citing retired postfix-chain fixups (they're gone); it motivates the fold purely as "build the SoN graph + MOP from the unambiguous tree, with control threaded by source-order walk."

**Two incidental grammar-coverage gaps surfaced during this verification (unrelated to ambiguity, track separately):** `<$fh>` readline and `@{...}` block-deref in argument position failed to parse. Not blockers for the architecture; file as grammar issues.

**Determinism gate retained:** the survivor handed to the fold has a deterministic shape; node identity is content-hash based (never refaddr/creation-order). The fixup-audit baseline (`2026-05-09`) now reads ~0 transformation fires — it is a regression gate proving the filters stay complete, not a measure of normalization debt.

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
5. **Carried-debt retirement (enumerate, do not assume done — all verified live at HEAD f0ed19b3):** codegen `MethodInfo->body` → graph-walk (Target/Perl.pm:563/764/790/817 still walk `->body`); `compat_class` field (Node.pm) + StructPromotion reader; 4 dead IR node types (Slice/Length/Stringify/Yada — dead in Chalk's own pipeline but still reachable via B::SoN JSON cross-load in tests, so the retirement gate must account for that path before deleting the NodeFactory registrations); **write-only `If/Loop->region`** (only `set_region` writers + Phi-only `->region()` readers; no If/Loop region reader); the `cfg_state` read-shim (a Context method, Context.pm:205) + its 4 read call-sites across 2 codegen files (EmitHelpers.pm, Perl.pm). Each gets a retirement gate. **NOTE: `control_in` is NOT carried debt — it is the system of record, READ by EagerPinning as ground truth (EagerPinning.pm:58-123). Do not list it as write-only.**

## Part 8: Toolchain decisions (researched 2026-06-05)

The reset is the cheapest moment to adopt tooling (no retrofit friction). SIX tools were evaluated from source (git-zhi, crochet, PAAD, perl-development-plugin, superpowers, claude-session-driver). **The headline finding: this stack is the productized, integrated form of the agentic workflow we ran by hand all this session** — and two of the six (superpowers, PAAD) are ALREADY active in this environment and were used throughout. The ad-hoc loop we used — brainstorm/plan, TDD RED-GREEN, dispatch parallel specialist agents, verify findings against code + git history to filter false positives, track "what's next / what's ready in parallel," gate work against acceptance criteria, audit plan-vs-code drift — is exactly what these tools formalize, as a single composed pipeline (next subsection). Adopting them replaces improvisation with a repeatable harness, much of which is already running.

### The stack (layered, and three of four are perigrin's own — low dependency risk, full roadmap control)
- **git-zhi** (`github.com/perigrin/git-zhi`, Go, `git zhi`): a git-native task graph — "what to do next, for developers and agents." Task state lives in `refs/zhi/`; no external DB. Agent-first: `git zhi issue show --format json` (structured context: paths, commands, acceptance_criteria), `git zhi next --actor 'agent:claude-code'` (per-worker scheduling), `git zhi list --ready` (parallel-runnable set), `git zhi verify <milestone>` (run all AC commands). Critical-Chain (Goldratt) forecasting from observed velocity, not estimates. **This is the foundation** — it gives the v3 migration a machine-readable task graph that agents query directly.
- **crochet** (`github.com/perigrin/crochet`, Claude Code plugin): the "intelligence layer for git-zhi." Decomposes specs into executable task chains, validates implementations against requirements, enforces retrospectives at milestones. Skills: `crochet:assess`, `crochet:refinement`, `crochet:execute`, `crochet:verify`. Interacts with chain state *exclusively* via `git zhi` CLI (porcelain-over-plumbing). Coordinates specialist agents (architect, decomposer, SQE, tech writer). **This is the orchestration layer** — it turns a v3 design doc into a decomposed, dependency-ordered, verifiable task chain.
- **PAAD** (`github.com/ovid/paad`, Curtis Poe's; Claude Code plugin): **P**ushback, **A**lignment, **A**rchitecture, **D**iscipline — defense-in-depth review skills. `paad:pushback` (challenge specs before build), `paad:alignment` (requirements/design/plan match before coding), `paad:agentic-architecture` (5 specialists, 14 strength + 34 flaw categories), `paad:agentic-review` (branch review w/ severity ranking + dedup), with a **verification phase that filters false positives by reading code and checking git history.** **This is the review/discipline layer.** We used it by hand all session; its verification discipline is exactly what caught the stale Part-2 claim.
- **perl-development-plugin** (`github.com/perigrin/perl-development-plugin`, Claude Code plugin): version-aware Perl skills — `perl:write-5.42` (the `feature class` skill CLAUDE.md already mandates), `perl:test` (Test2::V0, prove, real-data), perlcritic/perltidy, matrix regression. **This is the implementation/test layer**, version-pinned to 5.42 which v3 requires.
- **superpowers** (`github.com/obra/superpowers`, Claude Code plugin; ALREADY ACTIVE this session): "a complete software development methodology built on composable skills" — brainstorming (Socratic design), implementation planning, subagent-driven-development with two-stage review, TDD RED-GREEN-REFACTOR, verification-before-completion, git-worktree management. **This is the methodology spine.** Its principles ("Evidence over claims — verify before declaring success"; "Systematic over ad-hoc") are the discipline we operated under all session; crochet's `execute` uses its TDD inner loop.
- **claude-session-driver / csd** (`github.com/obra/claude-session-driver`, shell; superpowers marketplace): orchestrates MULTIPLE Claude Code sessions — launches tmux workers, assigns tasks, monitors via JSONL event logs, collects results. Patterns: delegate-and-wait, fan-out, pipeline, supervise, hand-off. **Cross-session/autonomous parallelism** — a different mechanism from in-process subagents (the Agent tool); use when work needs genuine parallel SESSIONS (e.g. the strangler migration's family-by-family construction moves).

### How they compose with v3's architecture and migration
- **No conflict with the Perl 5.42 / `./prove` substrate** — perl-development-plugin IS the 5.42 + prove workflow, formalized. git-zhi is orthogonal (git-native, language-agnostic).
- **They operationalize the strangler-against-oracle migration:** git-zhi holds the phase/family task graph with acceptance criteria = "byte-identical-or-justified vs the oracle"; `git zhi verify` runs those AC gates; crochet decomposes v3's Part 7 phases into the chain; PAAD reviews each landing. This is precisely the manual loop of this session (dispatch → verify against HEAD → gate against goldens), made repeatable.
- **PAAD's plan-vs-code verification is a structural defense against the exact failure that produced this very session's stale claims** (history-doc drift from code). Baking `paad:alignment` in before each phase, and PAAD's "check git history" verification after, is the discipline that would have caught Part 2 earlier.

### The stack is INTEGRATED, not competing (corrected framing)

An initial read treated the overlaps (superpowers vs crochet on orchestration; superpowers vs PAAD on review; csd vs in-process subagents) as conflicts requiring a winner-per-concern. That is WRONG: these tools were **designed to integrate**, with deliberate overlap where they reinforce each other. Verified evidence: `crochet:execute` is documented as "TDD with **Ralph Loop inner cycle and PAAD outer gate**" — crochet does not compete with PAAD, it INVOKES PAAD as its review gate. csd is distributed through the superpowers marketplace. PAAD "complements rather than replaces." So the model is **layered per-concern with intentional reinforcing overlap**, a single composed pipeline:

```
git-zhi          = durable task-state substrate (refs/zhi/; agent-queryable)
  ↑ driven via CLI by
crochet          = spec → decomposed verifiable task chain; orchestration
  │  crochet:execute = TDD inner loop + PAAD outer gate
  ├─ PAAD        = review/discipline gate (pushback/alignment/architecture/
  │                review, w/ code+git-history verification)
  ├─ TDD inner   = (superpowers' RED-GREEN-REFACTOR; the methodology spine,
  │                already the active substrate this session)
  └─ over
perl-development-plugin = Perl 5.42 + prove + critic/tidy (lang/test layer)

csd (claude-session-driver) = orthogonal: cross-session/autonomous tmux
   fan-out for parallel WORKERS — a different mechanism from in-session
   subagents; used when work needs genuine parallel sessions, not when an
   in-process Agent fan-out suffices.
```

Two already active in THIS environment (installed + used all session): **superpowers** (the brainstorm/TDD/subagent/verify discipline we've operated under) and **PAAD** (every audit this session is a PAAD-pattern review, archived in `paad/*-reviews/`). So adopting the stack is largely *formalizing what is already in use* + adding git-zhi/crochet/perl-plugin/csd.

### Recommendation: ADOPT the integrated stack, sequenced by dependency

1. **git-zhi first** — the substrate everything rides on. Encode v3's Part 7 migration phases + acceptance criteria (AC = "byte-identical-or-justified vs the oracle") as the initial issue/milestone graph.
2. **perl-development-plugin** + **superpowers** — already-mandated/already-active; formalize the 5.42+prove+TDD spine.
3. **PAAD** — formalize the review gate (already in use by hand); `paad:alignment` pre-phase, `paad:agentic-review`/`agentic-architecture` post.
4. **crochet** — the orchestrator that ties git-zhi + TDD + PAAD into `assess→refinement→execute→verify` chains. Adopt once git-zhi + the v3 task graph exist (depends on git-zhi on `$PATH`).
5. **csd** — adopt opportunistically, for genuinely-parallel multi-session work (the v3 strangler migration's family-by-family construction moves are a natural fan-out candidate). Not required for the linear phases.

**Caution (honest, unchanged):** git-zhi/crochet are early-stage (perigrin's own, evolving), so the reset's *process* couples to their maturity. Mitigation: low lock-in — everything is porcelain over git (zhi state is just refs; crochet/PAAD/superpowers/csd are skills/scripts); if any stalls, the underlying work (git refs, prove, manual review, in-process subagents) survives. For a project that IS an AI-driven-development testbed, dogfooding this stack is itself aligned with Chalk's purpose, and the dependency-control upside (4 of 6 are perigrin/obra collaborators' own) outweighs the maturity risk.

**Determinism/repo note:** git-zhi stores task state in `refs/zhi/` — orthogonal to source and to Chalk's byte-identical-codegen determinism (touches no build output). No conflict.

## Part 9: Explicitly out of scope / deferred
- GCM or alternative scheduler (EagerPinning is the placeholder; `control_in`-correct-at-hand-off is the contract; design against concrete GCM requirements when GCM is active).
- Eager-vs-lazy loop Phi timing (NOTE: `2026-02-24-lazy-phi-loop-design` already decided LAZY, then EagerPinning shipped; v3 must pick the BASELINE explicitly — current code is eager-pinning, so the v3 baseline is EagerPinning's behavior, and lazy-Phi is a deferred optimization, not a silent re-opening). Decide empirically when loop optimization is active.
- LLVM backend (planned; the multi-backend abstraction supports it).
- ExpressionList≥2 grammar refactor (DO NOT resurrect — rolled back, `option-b postmortem`).

## The two commitments, restated
1. Every FilterComposite member is a pure, hash-cons-stable, annotation-slot Context→Context function, ENFORCED at the composite boundary. Effectful IR construction cannot be a semiring.
2. IR + MOP construction is a post-parse fold over the survivor tree (which the fold normalizes), with no shared mutable channel back into the parse, and isolated unit tests from day one.

Everything else follows from these or is carry-forward of what works. The durable reason this is the last swing of the pendulum: the synthesized-attribute fold structurally cannot carry control's left-sibling channel, and only a post-parse pass over materialized source order can — a fact orthogonal to the hash-consing argument that drove the Feb reversal.
