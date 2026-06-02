# Control-Wiring Solution Comparison (Trio of Architecture Proposals)

**Date:** 2026-06-02
**Status:** Decision record. Three independent architecture proposals for the during-parse control-wiring problem, compared. Drives the near-term execution order; the step-3 fork is left open pending a clean substrate.

**Provenance:** commissioned after an audit pair (2026-06-02) refuted the tidy "one missing sibling edge" reduction and established the defect is multi-causal. Three subagents each took a distinct lens, blind to the others. See `docs/plans/2026-06-01-merge-and-control-implementation-plan.md` Phase 2 "audited reality" for the problem statement.

## The audited problem (multi-causal)

- **(a) Lateral seed gap** — statement N+1 is predicted+seeded from `$semiring->one()` (Start) at `Earley.pm:1219` and completes bottom-up before the StatementList merge; the synthesized fold gives a node its children, never its left siblings.
- **(b) Action-layer non-consumption** — Call/Assign/CompoundAssign/RegexSubst/TryCatch actions don't read `control_head` into their control input at construction; entirely rebuild-dependent. VarDecl/Return/Unwind do read it.
- **(c) Fold/tie-break coupling** — bare/refined VarDecl identity churn; the `add()` tie-break can surface the bare (pre-init) head. Root: VarDecl/Return/Unwind carry control in the hash-cons KEY (`inputs[0]`); Call/Assign carry it in the hash-EXCLUDED `control_in` field (`Node.pm:25-31`).
- Plus: gap recurs at every Block boundary AND Program (no rebuild); nested calls `bar(foo())` leave inner `control_in=undef` even with the rebuild; If/Loop region-advance; determinism (byte-identical codegen) required.

## The three proposals

### Proposal 1 — During-parse inherited channel
Seed predicted statement items at `_predict` with the predecessor's `control_head` (a content-deterministic `one_with_control($node)` keyed by `node->id()`, NOT refaddr — solving the C8 hash-cons determinism hazard). Covers Program + Blocks structurally (one rule at the `StatementList _ . StatementItem` advance). Requires (b) as a prerequisite, and a resolution for (c).
- **Self-verdict:** ~45% confidence it retires the rebuild; **not the opening move**. Recommends: do (b) first, then relocate, then the channel as the *capstone*. Biggest risk: the multi-predecessor seed collision at if/else joins (the class of bug that killed the prior attempt fb571989).

### Proposal 2 — Node-representation uniformity
Move control off the hash-cons KEY onto the hash-EXCLUDED `control_in` field for VarDecl/Return/Unwind, so ALL node types carry control as a per-use decoration set by `set_control_in` (mutation, no identity change). The scheduler ALREADY reads control through a uniform contract (`control_in // inputs[0]`, `EagerPinning.pm:69-74`) — the `// inputs[0]` fallback IS the symptom of the non-uniformity.
- **Dissolves (c)'s identity churn** (no `make` purely to change control; Return/Unwind's gratuitous `make_cfg` goes away; init-fold copies control by reference). Collapses the rebuild's 4 branch-shapes (2 churning) to one mutation path.
- **Landmine found:** moving VarDecl control off the key makes two identical `my $x=1` in different positions hash-cons together and fight over one `control_in` field → VarDecl needs per-position (counter) identity like Return/Unwind already have. Determinism-sensitive (IR snapshot re-baseline).
- **Self-verdict:** pays for itself as REGULARITY, not rebuild deletion. Sequence it; do NOT delete the rebuild as part of it. It de-risks (a)/(b) by removing the supersede-and-orphan failure mode.

### Proposal 3 — Principled post-materialization pass
Consolidate control placement into one scheduler-owned pass. **Key finding:** the post-pass already half-exists (EagerPinning) but is *circular* — it chain-walks `inputs[0]` to recover order, and `inputs[0]` is written by the rebuild. And branch-body nesting is NOT graph-recoverable today — it lives in parser-captured `*_stmts` arrayrefs on ScheduleMeta, because branch projections don't reliably carry `control_in`. So "relocate the rebuild into the scheduler" requires real IR surgery (proper threaded projections), not relocation.
- **Decisive honesty:** in the byte-compat round-trip era, deferring control placement buys NOTHING — the scheduler is FORCED to reproduce source order (can't exploit placement freedom until Phase 8 GCM). So the Click-1995 "control is a scheduling concern" justification does not apply yet.
- **Self-verdict:** consolidation is sound but HEAVIER than the during-parse fix in the current era; purest form is blocked on IR work; **the during-parse alternative would be better if achievable.**

## Synthesis: they stack, they don't compete

None of the three architects recommended its own lens as the immediate move; all gestured at the same dependency order:

1. **(b) action-layer consumption** — ~5 mechanical sites (Call/Assign/CompoundAssign/RegexSubst/TryCatch read `$ctx->control_head` into their control input). Unblocked, low-risk, valuable under EVERY approach.
2. **Proposal 2 representation cleanup** — uniform `control_in` decoration; kills (c)'s identity-churn landmine (the failure mode that doomed the prior during-parse attempt fb571989); collapses the rebuild's branches. Handle the VarDecl counter-identity landmine deliberately.
3. **THEN decide (a):** during-parse seed channel (Proposal 1 capstone) vs complete-the-scheduler (Proposal 3). Evidence tilts toward the during-parse capstone — Proposal 3 itself argues it's lighter in the byte-compat era, and Proposal 2 removes the landmine that made it fail before. Post-pass consolidation is the fallback if (a) proves intractable.

The rebuild stays as the **differential-check oracle** throughout (the `disable_control_rebuild`/`enable_control_rebuild` toggle from fb571989), deleted LAST.

**Why every prior attempt thrashed:** wrong order. The prior during-parse attempt tried to fix (a)+(b)+(c) simultaneously on a representation (hash-keyed control) that makes (c) a determinism landmine. Do 2 first (kill the landmine), do (b) (mechanical), and the capstone (a) becomes the contained change it was originally hoped to be.

## Decision (2026-06-02)

**Execute (b) then Proposal 2, then STOP and re-visit the entire plan** with those landed and the substrate clean. The step-3 fork (capstone vs scheduler) is explicitly deferred to that re-visit — decided against the real, cleaned-up substrate rather than from reasoning.

Full proposals preserved in the session subagent transcripts (workflow/agent records 2026-06-02).

## Execution log

### Step (b) — DONE, committed 68218db2 (reviewed, APPROVED)
Side-effect statement actions (Call/Assign/CompoundAssign/RegexSubst/TryCatch) now consume `$ctx->control_head` at construction via a shared `_thread_control_head` helper (Actions.pm:119-124), applied at 6 sites. Byte-identical under rebuild-ON (goldens 19/19, bnf-target-c 178/178 twice, all mop/*); ~42% of the rebuild's set_control_in calls for these types are now no-ops. The rebuild stays as differential oracle.

**LATENT-DEBT acceptance criterion for the eventual rebuild deletion (from the step-(b) review):** `CallExpression` fires for nested sub-expression calls too, so step (b) now stamps `control_in` onto nested, non-statement-position Call nodes (e.g. the inner `foo()` in `bar(foo())`) that were previously `undef`. This is HARMLESS today only because (1) the EagerPinning scheduler is chain-walk-based (visits only Return-chain nodes, never these), and (2) the Block rebuild is the last writer for on-chain nodes. **Before deleting the rebuild (step d), VERIFY no pass reads `control_in` outside the Return-chain walk** — a future scheduler/pass iterating `$graph->nodes` reading `control_in` directly would observe these stray nested values. (Classic residue-coupling per `feedback_technical_debt_cleanup`.)

### Step Proposal-2 — IN PROGRESS
Node-representation uniformity (control off the hash key → uniform `control_in` decoration; VarDecl counter-identity landmine). Then STOP and re-visit the whole plan.
