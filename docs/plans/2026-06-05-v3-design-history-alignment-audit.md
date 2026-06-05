# v3 Design — History Alignment Audit (Feb–June 2026 decision record)

**Date:** 2026-06-05
**Purpose:** Three parallel auditors checked the proposed "Chalk Clean-Room Reset v3" design against the FULL Bootstrap-era decision record (120 docs in docs/plans/, Feb–June 2026), not just the recent learning. This file records what they found so v3 can cite its lineage and not silently re-litigate or resurrect prior decisions. This is the evidence base for the revised v3 doc.

## The meta-pattern (the headline finding)

**v3 is the FOURTH attempt at the IR-construction layer. The same problem has been diagnosed and "fixed" in-place three times, and drifted every time.**

| Era | Decision | Outcome |
|-----|----------|---------|
| 2026-02-19 (`semiring-architecture-correction`) | RETIRED the two-tier "one parse before IR" (ChalkSyntax/ChalkIR) split; chose SA-as-5th-semiring. Stated reason: "hash-consed IR removes the limitation that forced the two-tier split." | The flat effectful-SA architecture that became F1. |
| 2026-04-24/25 (`semiring-contract-drift`, `audit-5`, `phase-a2-synthesis`) | Diagnosed v3's "Mistake 1" VERBATIM — both halves: contract shape-drift AND the purity gap ("the contract covers return shape; it does NOT cover purity"; SA-as-semiring is effectful construction). Chose **enforce-in-place** (Decision 4). Phase A.2 explicitly ruled out architecture redesign "out of scope by construction." | Partially executed, then re-drifted. At HEAD `on_merge` still mutates a hash-consed Context in place; SA still mutates MOP/NodeFactory during parse; the mechanical "is_zero iff is_zero" enforcement test appears never written. |
| 2026-05-26/31 (`scope-control-divorce-design`, `ir-construction-substrate-design-brief`) | Chose **Option A (during-parse lateral control threading)**, KEEP IR construction in the semiring; explicitly SHELVED Option B (post-parse fold). | Sprang FIVE distinct control-leak blockers across FOUR RED rebuild-deletion audits (postfix, C-for my-init, elsif, C-for bare-init, my-decl-postfix), each patched with bespoke tree-walks — the whack-a-mole. |
| 2026-06-05 (this session — `clean-control-construction-design` = Option X, `context-to-son-postpass-vision-validation`) | Reversed to **post-parse pass as system of record**; validated the full vision (move ALL IR+MOP construction post-parse) as VIABLE. = v3's two commitments. | Pending — v3 is the codification. |

**Consequence for v3:** it must NOT present its two commitments as discoveries. It must cite April's diagnosis + decision, explain why **rewrite succeeds where three in-place fixes drifted**, and — critically — replace Feb's WRONG diagnosis with the durable one. Feb said hash-consing was the blocker that justified going flat. The real, orthogonal-to-hash-consing blocker is: **the synthesized-attribute fold (Loup Vaillant Earley model) structurally cannot carry the inherited left-sibling-predecessor channel that control needs.** That is the load-bearing reason two-tier is correct, and it is what breaks the two-tier→flat→during-parse→post-parse loop. Without this paragraph, v3 is just the next swing of the pendulum.

## Finding A — CORRECTED: the "4 filters produce a clean unambiguous tree" premise is TRUE at HEAD (the May evidence below is STALE)

**This finding was initially recorded as "premise FALSE" based on the May-era docs cited below. Direct instrumentation at HEAD (d87b7ccf) REFUTED that — the four pure filters produce a single unambiguous survivor (0 ambiguous Contexts ever constructed; 0 multi-survivor packs; the named fixups were deleted as dead code in commit `38e6af60`, having fired 0 transformations across the 105-file corpus). The "251k fires" was a node-visit counter, not transformations. v3 Part 2 now records the TRUE state. The May evidence below is preserved as the historical record of what was true BEFORE the post-May robustness work — it is no longer the state of the code.**

Stale May-era evidence (what motivated the original-but-wrong "false premise" reading):
- `2026-05-09-fixup-audit-baseline.md`: "filter stack is complete iff zero fixups fire" — it never reaches zero. **All 105 corpus files trigger fixups**; ~130 real transforms remain (IR/MOP/Grammar), 1,250+ on Bootstrap-partial.
- `2026-05-17-survivor-list-architecture.md`: under honest product semantics, **9.4% of merges are real Precedence-vs-Structural conflicts; 4,459+ ties** surface that Boolean's `$left`-by-convention had masked. The output is packed-ambiguous / multi-survivor, not a single clean tree. The `peel_builtin` walker STAYS load-bearing (~30 residual cases); "Derivation C" is genuine IR-shape rewriting, not disambiguation.
- `2026-05-12-list-operators-as-predeclared.md` + `peel-builtin-investigation.md`: at least two disambiguation classes (bare list-op comma-slurping; method-over-builtin/deref) are documented as NOT precedence and NOT cleanly filterable; their homes are a chart-merge preference rule or a fixup walker.

**What v3 must say instead:** the four filters produce a SINGLE WINNING SURVIVOR that carries all annotation tags and touches zero constructed IR (verified — so the fold CAN consume it), but that survivor's tree shape still carries load-bearing artifacts (peel_builtin, list-op slurp, method-over-deref) that today's walkers repair and **the post-parse fold inherits**. v3 must either (a) commit the fold to owning these shape rewrites explicitly, or (b) commit to retiring each class into the grammar/chart-merge with a named plan. v3 must NOT claim the tree is "clean."

## Finding B — what v3 keeps vs reverses, reconciled against prior decisions

CONTRADICTS prior decisions (v3 must name and justify each reversal):
- `2026-02-19` Retired Axiom (one parse before IR) — v3 resurrects it (see meta-pattern; durable reason = synthesized fold).
- `2026-04-12-unified-context-design.md` — deliberately UNIFIED graph/cfg/mop/bindings/control_head ONTO Context (to kill the `%_cfg_state` side-table coherence bug). v3 SLIMS exactly those fields off. v3 must state: the post-parse fold removes the need to thread construction state through Context, so those fields move to the fold's working state — and name where cfg-coherence is now guaranteed, so it doesn't read as resurrecting the retired side-table problem.
- `2026-04-20-program-graph-of-graphs/MOP design` — has TI/Structural/SA enriching the MOP via `$ctx->mop()` DURING parse (live at `Actions.pm:1411`). v3 keeps the MOP shape (root + per-method graphs) but bars during-parse semiring enrichment; the MOP is built by the fold.
- `2026-04-25-phase-a2-synthesis.md` — explicitly bounded remediation to "no architecture redesign, out of scope by construction." v3 IS that redesign; must own the boundary crossing and say why enforce-in-place (Decision 4) was insufficient (it drifted).

CONSISTENT — v3 correctly inherits (so we know they're captured):
- 4 pure filter semirings + filter-semantics `add()` contract + single-survivor assertion (`2026-02-19`).
- Comonad `extend()` annotation model (`2026-02-20/21`); the `type`-as-annotation slot; TI's own "Future Work: post-parse type inference via SA walking the annotated tree" (2026-02-20) is the EARLIEST seed of v3's fold.
- LR(0) DFA + distance factoring + Leo + static C tables + `%waiting_for` elimination (`2026-03-16/24/27/31`).
- The Goodman 5-op pure semiring API — `2026-04-12-on-complete-elimination-design.md` ALREADY SHIPPED it (commit 6c77c805); v3's "redefine the API" is ~80% pre-built.
- chalk.so + per-class XS multi-backend codegen; IR-level optimizer/peephole (`2026-03-19/24`).
- Byte-identical determinism (`2026-03-31`).
- SoN IR node types (If/Region/Phi/Loop/Proj) + per-graph hash-cons + control_in hash-excluded.
- EagerPinning as placeholder, GCM deferred (`2026-05-23/24 son-scheduler-prep/design` recommend EagerPinning, defer GCM — matches v3 exactly).

DO NOT RESURRECT (dead/abandoned ideas):
- `should_scan` (removed 2026-04-12; residue in KeywordTable.pm/Structural.pm).
- Single-SO / multi-class XS (abandoned; per-class is the architecture).
- The `cfg_state` side-table (being dismantled; v3's "no shared mutable channel" finishes it).
- The Option-B grammar refactor `ExpressionList ≥2 elements` (`2026-04-24-option-b-grammar-refactor-postmortem.md` — rolled back; broke `push @arr,$x`). Real lesson: `(rule_name, alt_idx)`-keyed semiring dispatch is fragile under grammar edits → the fold should key on STABLE rule identity, not (rule_name, alt_idx).

## Finding C — carried migration debt is NOT inert (v3 "carry the rest" must enumerate it)

The April auditor confirmed the SoN/MOP migration is NOT 30-40% stalled at HEAD (that's the stale April snapshot); it advanced to ~Phase 7d/8 in May (compat_class setters in Actions.pm = 0, body fields gone, Shim deleted, mop.md exists, cfg write-side side-channel deleted). BUT real residue remains and v3 inherits it:
- `compat_class` field still declared on `Node.pm` + read by `StructPromotion.pm`.
- `on_merge` still mutates a hash-consed Context in place (the April purity violation, still live).
- Codegen still walks `MethodInfo->body` (not graph-walk); `If/Loop->region`/`control_in` are write-only in production (`2026-05-22-ir-mop-alignment-audit.md`).
- cfg_state READ-side shim + 4 codegen consumers persist.
- 4 dead IR node types (Slice/Length/Stringify/Yada) per audit-3 (not re-verified at HEAD).
- `one_with_control` added to Boolean (`Boolean.pm:39`) — effectful control hook on the semiring path, contra the pure contract (this is OUR during-parse channel; retired under Option X).
- F16: the construction code (Block rebuild) has NO isolated unit spec — exercised only end-to-end.

v3's migration section must enumerate these as carried debt with retirement gates, not assume done — this is the exact 80-90%-drift pattern CLAUDE.md and all three auditors warn about.

## Finding D — identity/determinism hazards v3 inherits and must name
- `2026-05-21-earley-identity-audit.md`: `_mul_ctx` hash-conses by `refaddr($left):refaddr($right)`; `_complete_sa` deliberately NOT hash-consed; SA::add dedups on Context refaddr. Earley itself has zero refaddr calls (identity lives in the semiring stack).
- `2026-05-21-factory-unification-audit.md`: three factories per parse (since narrowed by Phase 7d singleton deletion).
- **Benefit for v3 to claim:** moving construction post-parse ELIMINATES the `_complete_sa`/`_mul_ctx` refaddr-identity coupling, because construction no longer rides the Context fold. v3 should claim this as a benefit of Commitment 2, and state node identity is content-hash-based (never refaddr, never creation-order) and that Context-level refaddr keys never leak into byte output.

## Per-era auditor reports
Full per-doc classification tables for each era (Feb-Mar, April, May+June) are in the session subagent transcripts (2026-06-05). The findings above are the synthesis.
