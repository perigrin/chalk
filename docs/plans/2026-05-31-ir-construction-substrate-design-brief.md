# Design Brief: Per-Position DFA State as a Substrate for IR Construction

**Date:** 2026-05-31
**Status:** Design brief — decision-oriented, no implementation. Re-evaluates a previously-shelved mechanism under a goal it was never judged against.
**Author context:** Written during the scope/control-divorce work (branch `fixup-audit-baseline`), after a multi-agent architecture audit and a focused measurement spike.

---

## 0. The goal this is measured against

The active goal is **a robust, simplified IR-construction architecture that makes optimization, scheduling, and codegen (C / LLVM IR) straightforward.** Not "faster parsing." Not "delete the Block rebuild" (that was only ever a symptom). The question every option below is scored against is: *does it give us a clean, single-pass-ish way to build correct IR that feeds the downstream pipeline without post-hoc repair?*

This framing matters because the mechanism under re-evaluation was previously judged **only** under the parsing-robustness goal (see §2).

---

## 1. The problem, stated precisely

Chalk builds Sea-of-Nodes IR *during* the Earley parse, via semantic actions hosted in the SemanticAction semiring, threading a comonad `Context`. Per the Loup Vaillant model Chalk aligns to, this semantic-action evaluation is a **pure synthesized-attribute fold**: a rule's action receives only its children's results — there is **no inherited attribute channel**, no left-sibling→right-sibling flow.

Most of an SoN graph is fine to build this way: data-flow edges (an `Add`'s operands, a `Call`'s arguments) point at *descendants*, which are exactly what a synthesized fold has in hand. The exception is the **control chain**: a side-effect node's `inputs[0]` points at its *predecessor statement* — a *left sibling*. In a synthesized fold where each statement is an independent subtree, statement N+1's action cannot see statement N's materialized IR node. So Chalk:

1. has each statement action *guess* its control input (`$ctx->control_head // make('Start')`, ~11 sites), then
2. repairs the chain post-hoc in a ~90-line loop in `Block` (Actions.pm:1567-1651) that walks the materialized sibling list in source order and rewires each node's `inputs[0]`.

The C4 audit confirmed this rebuild is **load-bearing** (fires in 22/46 blocks). It cannot be deleted by relocation; it structurally needs the full materialized sibling list, which only exists at Block-completion.

**Root cause (not a symptom):** the IR control chain wants an *inherited* (left-to-right) value; the semantic-action layer is *synthesized-only*. The mailbox statics, the guess-then-repair, the multiple-owners-of-scope — all are workarounds for this one missing channel. (Architecture review F1/F2/F4/F5, `paad/architecture-reviews/2026-05-31-chalk-semantic-action-architecture-report.md`.)

---

## 2. Why the obvious substrate was shelved — and under which goal

There already exists, half-built, a structure that encodes per-DFA-state context: the LR0 DFA's **`completion_map`** (LR0DFA.pm:191-211), built for every state, recording which items wait on which nonterminal. It is **constructed but never read at runtime** (only `terminal_map` is consumed, Earley.pm:590).

History (recovered from commits + design docs + past-session transcripts):

- It was built as **Layer 2 of a three-layer waiter-narrowing filter** whose *sole stated purpose was parse-recognition speed* (design doc 2026-03-27 §5.3, §7.5; complexity table §11).
- It was wired up (commits `7ee20f53`, `3b08e770`), then **disconnected** (`4f30509c`) after a code review found the *speed* filter was a tautological no-op — because `state_for_core` is many-to-one with first-write-wins (LR0DFA.pm:166-177), so the per-state check pruned nothing.
- The fix that would make it bite — **per-position DFA state tracking** — was *named but never scoped or attempted* (Earley.pm:1365-1370 NOTE). The design doc itself flags "single-state-per-position" as an **unvalidated assumption** and keeps the agenda loop *because* a position may hold items from multiple DFA states (§7, 1538-1542).

**The critical finding (episodic history):** in the 2026-03-27 design conversation, the question *"Which is more **correct** though? It feels like the completion_map is the correct source of truth at that point"* was raised — and **deferred, never disproven.** Every evaluation `completion_map` ever received was through the **parsing-robustness lens** (is it useful/fast for recognition? → no). It was **never** evaluated as a substrate for **IR-construction state**. The deferral was correct *at the time* — chasing IR semantics during parser hardening would have been scope creep against the then-active goal. The decision is not stale; it is **narrow**: it answered the parsing question completely and the IR-construction question not at all.

---

## 3. The spike: is the load-bearing assumption true? (measured, not reasoned)

The whole "per-position DFA state could be an inherited channel" idea hinges on one factual question: **does a parse position genuinely hold items from multiple DFA states in practice?** If positions are effectively single-state, `state_for_core` loses nothing and per-position tracking buys nothing new. Measured on a real parse of `class A { method m($self) { my $x = 1; my $y = 2; return $x; } }`:

- **53% of non-empty positions** hold ≥2 fully-present DFA states (strict definition: all of a state's kernel items live). Histogram: 17 positions @1 state, 10 @2, 5 @3, 1 @5, 1 @6, 2 @7.
- **Multi-state concentrates at statement boundaries:** 70% of statement-boundary positions (16/23) are multi-state and carry the *entire* high tail (5/6/7 states); only 23% of non-boundary positions (3/13) are multi-state, none exceeding 2.
- **`state_for_core` provably loses information:** 89% of live core_ids (252/282) belong to >1 DFA state and are all collapsed to one. At the worked example (the `;` of `my $x = 1;`), the `StatementItem . /;/`, `Block ... . /}/`, and a 12-state fan of `Expression _ . <op>` continuations are simultaneously live — the literal "what comes after a completed expression / statement" decision — and all are collapsed to single arbitrary states.

**Verdict: REAL + COMMON, and concentrated exactly at the statement boundaries where the control-chain problem lives.** The single-state-per-position assumption is false for this grammar. Per-position DFA-state tracking would carry real, non-trivial information that `state_for_core` currently destroys.

This does **not** prove per-position state is *usable* as an inherited IR channel — only that the substrate carries real information and is currently being thrown away precisely where we'd want it. That's enough to make the question live; it is not enough to declare the answer.

---

## 4. The candidate architectures

Three options, scored against the §0 goal (clean IR construction → straightforward opt/sched/codegen), not against parse speed.

### Option A — Per-position DFA state as an inherited-attribute channel
Track the live DFA state(s) per chart position (the thing declined under the parsing goal), and use that per-position context to carry left-to-right state into IR construction — so a statement's action *can* see its predecessor's materialized control point, building the chain correctly in one pass. Revives `completion_map` as the candidate substrate.

- **Upside:** attacks the root cause directly — supplies the missing inherited channel inside the existing during-parse model. If it works, the Block rebuild, the guess-then-repair, and much of the mailbox dissolve. Keeps IR construction during the parse (preserves the "IR ≈ tree, build it as you go" thesis that Simple validates).
- **Risk / unknowns:** (1) the spike proves the *information exists*, not that it's *threadable into actions* — a position holds *multiple* states; "the predecessor's control point" must be extractable from that set, not just present in it. (2) Per-position state tracking is new machinery the project declined once (for cost, under a different goal). (3) Must not disturb the positional correctness machinery (chart/origin liveness, Leo, epoch GC, `add` ambiguity merges) the parser-robustness work established.
- **Open question it rests on:** can per-position DFA state be reduced to a single well-defined "control predecessor at this point," or does ambiguity/multi-state make that ill-defined until disambiguation completes?

### Option B — Post-parse `act`-over-Context pass
Let the parse build a disambiguated Context tree (the synthesized fold, as today, but *without* IR construction). A separate pass then walks that tree to build IR — and because it's an ordinary tree walk, it can thread inherited/left-to-right state naturally (the way Simple's recursive-descent threads `ctrl`).

- **Upside:** the inherited channel is free in a tree walk. Clean separation: parse+disambiguate, then build. Directly addressed in the architecture review's Next-Questions. Most aligned with the textbook two-phase (recognize → act) model Loup Vaillant describes (and explicitly un-fuses what Chalk fused).
- **Risk / unknowns:** (1) requires the disambiguated Context tree to survive the parse — but the spike work and `_mul_ctx` show Chalk *already* builds a `children`-linked Context tree, so the "we avoid materializing a tree" justification may be partly illusory (worth confirming how complete that tree is post-parse). (2) Moves IR construction out of the semiring — simplifies the four filter semirings (no `_wrap_sa_result`, no TI→SA `set_type_context`, SA leaves the product) but is a larger structural change. (3) Two passes vs one.

### Option C — Status quo + subtractive cleanup
Keep during-parse construction and the Block rebuild. Delete the dead `completion_map` + stale NOTE (or scope it to its only consumer, the C serializer). Fix the confirmed latent bugs the audit found (control_head dropped in two `_complete_sa` inherit blocks; dead `_transferred_scope`; dead `error` field).

- **Upside:** lowest risk, immediately test-green, removes real clutter, fixes real latent bugs. The audit's recommendation.
- **Downside (against §0 goal):** does *nothing* for the root cause. The rebuild, the guess-then-repair, the multiple-owners-of-scope all remain. It makes the current architecture tidier, not simpler-in-structure. **And deleting `completion_map` under this option would discard the Option-A substrate before Option A is evaluated** — so if A is live, C's cleanup must NOT delete `completion_map`.

---

## 5. The reframed decision

The 2026-03-27 question, finally asked under the right goal:

> *Is per-position DFA state (the `completion_map` substrate, currently dead) the correct source of truth for where-we-are-in-the-parse — and therefore the natural home for the inherited state that IR construction needs — now that the goal is robust IR construction rather than robust/fast parsing?*

The spike says the substrate carries real information, destroyed exactly where we need it. That does not decide the architecture; it makes Option A a *legitimate contender* rather than a *settled-against* idea. The honest state:

- **Option C alone is wrong for the stated goal** — it's the parsing-lens answer to a non-parsing question. (Its bug-fixes are worth doing regardless; its `completion_map` deletion is not, until A is ruled out.)
- **Options A and B both attack the root cause.** They differ on *where* the inherited channel lives: A puts it in the parser (per-position state, during-parse construction preserved); B puts it in a separate pass (post-parse, construction moved out).
- **The deciding factor between A and B** is one question the spike didn't answer: *can the multi-state-per-position information be reduced to a single well-defined control predecessor before disambiguation finishes?* If yes → A is viable and keeps the during-parse model. If no (the multiplicity is inherently ambiguous until the parse resolves) → the inherited channel can only live *after* disambiguation, which is Option B.

---

## 6. Recommended next step

**Do not implement yet. Do not delete `completion_map` yet.** One more focused spike resolves A-vs-B: take a multi-state statement-boundary position from the §3 data and determine whether the live DFA states there can be reduced — at that point in the parse, before the full parse completes — to a single, correct "control predecessor" for the next statement. Concretely: is the predecessor extractable from per-position state, or is it only knowable once `add`/disambiguation has resolved the position (which is post-parse-ish, i.e. Option B territory)?

- If extractable pre-resolution → write the Option A implementation plan (per-position state tracking + inherited control threading + retire the rebuild).
- If only post-resolution → write the Option B implementation plan (disambiguated-tree-then-act-pass), and *then* the `completion_map` cleanup is safe.

Either way, the bug-fixes from Option C (control_head drop, dead `_transferred_scope`/`error`) are safe to do now, independently — they don't touch `completion_map`.

---

## Evidence index

- **Root cause / current architecture:** `paad/architecture-reviews/2026-05-31-chalk-semantic-action-architecture-report.md` (F1, F2, F4, F5, Next-Q #1-2)
- **Block rebuild load-bearing:** commit f3a457f1; memory `block_action_workaround_accretion.md`, `phase_3a_migration_cross_stmt_scope.md`; Actions.pm:1500-1658
- **`completion_map` history:** built `99f2a2b7`/`7ee20f53`/`3b08e770`, disconnected `4f30509c`; kill rationale `paad/code-reviews/worktree-floofy-sparking-bunny-2026-03-28-...be82708c.md` [I1]; design intent `docs/plans/2026-03-27-dfa-factored-earley-parser.md` §5.3/§7.5/§11; lossiness `c57a389b`, LR0DFA.pm:166-177
- **"Which is more correct" deferral:** past session `-floofy-sparking-bunny 2026-03-27` (conversation-archive 0b318f17-...jsonl); callback-removal rationale `earley-parser.md:399-401`, `on-complete-elimination-design.md` (#708), `should_scan_removed.md`
- **Spike (multi-state-per-position):** measured this session — 53% positions multi-state, 70% of statement boundaries, 89% of core_ids collapsed by `state_for_core`; LR0DFA.pm:182-216, CoreItemIndex.pm:56-59, Earley.pm:404/1365-1370
- **Semiring contract / completion is positional:** opedal-semiring-earley-acl2023.pdf Table 1 p.3, §2 p.2; FilterComposite.pm:230-291; Earley.pm:619-651, 1361-1422
