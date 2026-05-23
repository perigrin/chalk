# SoN Scheduler — Prep for Next Session

**Date:** 2026-05-23
**Status:** Pre-work; this document gathers prior art and context so the
next session can start scheduler design without re-doing the recovery work.
**Branch:** `fixup-audit-baseline`
**Goal for next session:** produce a concrete scheduler design doc (likely
`2026-05-24-son-scheduler-design.md`) and an implementation plan, NOT
the implementation itself.

## Why we're doing this now

The IR completeness audit + Phase 3d/3e + the self-host probe established
that:

1. The IR layer is structurally complete for Chalk's Perl subset.
2. Codegen still walks `MethodInfo->body` (an arrayref of statement-root
   IR nodes) via a synthesis layer (`_generate_from_mop` in
   `Target/Perl.pm` lines 85-194). This is the documented Phase 4
   shortfall.
3. The conversation walking us into this work clarified that **`body`
   is "pre-scheduler workaround debt"** — it exists because no
   scheduler exists to produce a schedule from the graph. In a real
   Sea of Nodes architecture, the graph IS the program; the scheduler
   produces emit order; codegen consumes the schedule.

So before any more cleanup work on `->body` reads (which would just
polish the scaffolding), or any final codegen-correctness test corpus
(which would lock in current behavior including any latent bugs), we
need a scheduler design. That's what the next session is for.

## Prior art recovered (Feb 23 conversation + literature pointers)

The Feb 23 conversation at
`~/.config/superpowers/conversation-archive/-home-perigrin-dev-chalk/114c66cb-9f36-4ade-be96-5e6c9849387a.jsonl`
lines 759-893 contains the original research. The key finding was a
three-tier scheduling complexity table:

| Approach | What it does | Complexity | Verdict |
|---|---|---|---|
| **Full Click GCM** | Dominator tree + early/late schedule | Expensive | Overkill for structured code |
| **Nesting-tree GCM** | Implicit dominators from structured control flow | Moderate | Handles optimization |
| **Eager Pinning** | Tag each IR node with its control region at creation time | O(n) | Simplest; recommended |

**Eager Pinning was the recommendation** for Chalk. The reasoning: we
already know the control structure at parse time, so tag nodes with
their region instead of throwing that info away and reconstructing it.
This mirrors the Turboshaft (V8) approach.

### Sources to read (full session, not yet)

- **Demange & Retana, "Semantic Reasoning About the Sea of Nodes"**
  https://inria.hal.science/hal-01723236/file/sea-of-nodes-hal.pdf
  (the structured-control-flow semantics paper).
- **Cliff Click, "A Simple Graph-Based Intermediate Representation"** (1995)
  https://www.oracle.com/technetwork/java/javase/tech/c2-ir95-150110.pdf
- **Simple SoN pedagogical implementation**
  https://github.com/SeaOfNodes/Simple
  Chapters 5 (If/Region/Phi), 7 (Loops / eager Phi), 8 (lazy Phi) are
  the relevant ones for us.
- **Turboshaft / V8 paper** (the ACM one referenced in the Feb 23
  conversation) — https://dl.acm.org/doi/10.1145/3679007.3685059

## Existing local docs to harvest

Two existing design docs already address Chalk's scheduler question
at different layers:

### `docs/plans/2026-02-23-sea-of-nodes-cfg-design.md` (236 lines)

Comprehensive design for SoN CFG nodes (If/Region/Phi/Loop/Proj) and
their construction during semantic actions. **Most of this design has
shipped** — Phase 3a-infra / 3a-migration / 3b / 3c built exactly what
this doc described: scope threading, eager Phi sentinels for loops,
If/Region/Phi merge construction.

**The part not yet shipped — the section that's actively load-bearing
for our next session — is "XS Target: From Tree-Walk to Graph
Scheduling" (lines 165-188):**

> The XS target replaces tree-walking with graph scheduling.
>
> **Scheduling.** Reverse-postorder walk from Return backward through
> use-def chains. CFG nodes impose ordering; data-flow nodes emit
> within basic blocks.
>
> **Structured reconstruction.** The IR was constructed from
> structured source, so every If has a matching Region and every Loop
> has structured entry/exit. Pattern matching reconstructs `if/else`
> and `while` from the graph primitives.

This is the answer to "what does the scheduler look like for Chalk?"
Reverse-postorder + structured reconstruction. The doc has examples
for if/else and loop Phi → C variable emission patterns.

### `docs/plans/2026-02-23-eager-pinning-cfg-statements.md` (634 lines)

The eager-pinning *task-by-task implementation plan* for the cfg_state
side-table approach. This is the older approach — it stored body
statement collection in the cfg_state side-channel, not on IR nodes
directly. **Phase 3a-infra deleted the cfg_state side-channel.** The
plan's mechanism is stale; the *concept* of eager pinning (tagging
nodes with control regions at parse time) survives but is now
implemented via `MOP::Method->graph` membership and the Block
control-chain fixup pass.

This doc is mostly historical reference now. The first paragraph
("Architecture: Extend cfg_state with a `statements` field that maps
Proj/Region nodes to their body IR nodes") describes a mechanism
that no longer exists.

## What Chalk's IR currently has vs. what a scheduler needs

A reverse-postorder scheduler over the SoN graph needs the IR to
expose:

| Need | Status | Source |
|---|---|---|
| Control nodes (Start, Return, Unwind, If, Region, Loop, Proj) | ✓ Shipped | Phase 3 (CFG migration) |
| Phi at merge points (if/else, loop header) | ✓ Shipped | Phase 3b, 3c |
| Side-effect chain via `control_in` field on data nodes | ✓ Shipped | Phase 3d |
| Side-effect chain on CFG nodes via `inputs[0]` | ✓ Shipped | Phase 3a-infra |
| Post-construct merge point reachable from CFG node (`If->region`, `Loop->region`) | ✓ Shipped | Phase 3d step 4-5 |
| `Graph::nodes()` returns all reachable nodes | ✓ Shipped | Phase 7b + 3d iterative refactor |
| Dominator tree | ✗ Not built | Would need to be added |
| Loop nesting | Partial | Loop nodes exist; nesting depth not computed |
| GVN (global value numbering) | Partial | Hash consing covers expressions; not GVN proper |

The eager-pinning approach explicitly avoids the dominator-tree
requirement. That's the design's selling point: leverage what we
already have (structured control nodes with `region` accessors)
rather than building dominance from scratch.

## The shape of the next-session design doc

The next session should produce `docs/plans/2026-05-24-son-scheduler-design.md`
(or similar) with these sections:

1. **Scope.** What the scheduler does and doesn't do. Specifically:
   - Input: a `MOP::Method` (containing `$graph` + the source-order
     `$body` as a hint).
   - Output: a linear sequence of nodes suitable for codegen emit.
   - Does NOT do: GVN, dead code elimination, hoisting. Those are
     separate passes that may run before or after scheduling.

2. **Algorithm.** The eager-pinning version:
   - Each side-effect node is already "pinned" to a control region
     via its `inputs[0]` (CFG nodes) or `control_in` field (data
     nodes), thanks to Phase 3d.
   - Walk the CFG control chain forward from `Start`. At each step,
     emit the side-effect node's data dependencies (its `inputs`
     transitive closure, restricted to pure data nodes), then the
     side-effect node itself.
   - At CFG branch points (If with two Projs), recursively schedule
     each branch up to the joining Region. Emit `if (cond) { ... } else { ... }`
     reconstruction at codegen time.
   - At Loops, schedule the body (between entry and backedge), emit
     `while (...) { ... }` reconstruction. Phi nodes at the loop
     header determine which variables get loop-carried emit slots.

3. **Structured reconstruction patterns.** For each CFG-node pair the
   scheduler outputs, what does codegen emit?
   - If + Region pair → `if/else`
   - Loop + If(condition) + Region pair → `while` / `until`
   - ForStatement's pre-init VarDecl + Loop → `for` if we want
     prettier output, otherwise just `{ init; while (cond) { ... } }`
   - TryCatch → `try { ... } catch ($e) { ... }`

4. **Phi → variable mapping.** A Phi at a join point becomes an emit
   slot for the variable. For if/else Phis, declare the variable
   before the if and assign in each branch. For loop Phis, the loop
   variable is the Phi target and the backedge value is what gets
   assigned per iteration.

5. **What `MOP::Method->body` becomes.** Either:
   - **(a)** Deleted entirely — codegen no longer reads it; the
     scheduler produces the schedule from the graph.
   - **(b)** Kept as a fallback or as a "preferred source ordering
     hint" the scheduler may consult.
   The Feb 23 design implies (a). The session should commit to one.

6. **What `MethodInfo`/`ClassInfo`/`SubInfo` becomes.** Deleted; codegen
   reads `MOP::Method`/`MOP::Class`/`MOP::Sub` directly.

7. **Implementation phases.** Decompose the scheduler implementation
   into commits / commits-per-PR. Each phase should be:
   - Small (one session of work).
   - Independently testable.
   - Doesn't regress byte-compat goldens (those are the existing
     contract).

8. **Test strategy.** What does the test corpus look like? Probably a
   side-by-side comparison: feed the same source through the OLD
   codegen path (via `->body`) and the NEW scheduler-driven path,
   assert byte-identical or semantically-equivalent output. Where
   they differ, decide whether the new path's output is correct (and
   update goldens) or wrong (and fix the scheduler).

9. **Risks and prerequisites.** What could go wrong, what depends on
   things not yet built, what's the rollback path if the scheduler
   produces wrong code.

## Open questions for the next session to settle

- **Eager pinning vs. nesting-tree GCM.** Eager pinning is simpler;
  nesting-tree GCM enables more optimization (loop-invariant hoist,
  branch float-up). For Chalk's Perl backend, we want byte-compat
  with source as a starting point — eager pinning is right. But the
  decision should be explicit.

- **Pattern matching for `for`/`while`/`until`.** Do we recognize
  Loop-with-specific-Phi-pattern as `foreach` vs `while`? Or always
  emit `while` and accept slightly different (but equivalent) source?
  The audit corpus has `foreach my $n (LIST)` — if we emit
  `my $iter = ...; while (...) { my $n = $iter->next; ... }` instead,
  that's correct but uglier. Eager pinning's annotations (`loop`
  vs `foreach`-shape on the Loop node) might let us preserve the
  distinction; need to verify.

- **`MOP::Method->body` lifecycle.** Today it's populated alongside
  the graph during parse. If we delete it, do we delete the
  population code too, or keep populating it as a debug aid? Probably
  delete entirely; debug aids belong in dedicated debug code.

- **Order of operations: scheduler-then-codegen-migration, or
  codegen-migration-then-scheduler?** The current synthesis layer in
  `_generate_from_mop` would still work after the scheduler ships;
  the scheduler just provides a different (cleaner) input. We could
  ship the scheduler as a new alternative path first, keep the
  synthesis layer as a fallback, and migrate codegen incrementally.
  Or we could migrate codegen to MOP first (without a real scheduler,
  just keep using body), and then swap body for the scheduler. The
  next session should pick.

## Reading list for the next session

In order:

1. **`docs/plans/2026-02-23-sea-of-nodes-cfg-design.md`** lines 165-188
   ("XS Target: From Tree-Walk to Graph Scheduling"). This is the
   shortest path to having a concrete sketch of the algorithm.
2. **The Click 1995 paper.** Mainly for vocabulary and to confirm
   "eager pinning" is what Turboshaft calls it.
3. **The Simple SoN repo Chapter 5 + Chapter 7.** Concrete code for
   if/else and loop scheduling. Pedagogical.
4. **The Feb 23 conversation** (entire range, not just the line-760
   summary) — recover any deeper detail that got truncated.

The Demange & Retana paper is theoretical foundation; useful if a
specific question comes up but not the starting read.

## What the next session should NOT do

- **Do not write scheduler code.** This session is design only.
- **Do not refactor codegen.** The session is about the next phase's
  plan, not its execution.
- **Do not delete `MOP::Method->body`.** That's the implementation
  step's job, not the design's.
- **Do not solve the parser-performance question.** Earley scaling
  is orthogonal; defer.
- **Do not start the codegen-correctness corpus (P3).** That's
  better tackled after the scheduler design lands as a regression
  guard for the implementation.

## Cross-references

- The 2026-05-22 IR completeness audit:
  `docs/plans/2026-05-22-ir-completeness-audit.md`
- Phase 3d design:
  `docs/plans/2026-05-22-phase-3d-effect-chain-completion.md`
- IR / MOP alignment audit (smells found and remediated):
  `docs/plans/2026-05-22-ir-mop-alignment-audit.md`
- Self-host probe (post-cleanup IR readiness check):
  `docs/plans/2026-05-23-self-host-parse-probe.md`
- Corpus alignment audit (catches what real lib/ uses):
  `docs/plans/2026-05-22-corpus-alignment-audit.md`
- MOP migration master plan (Phase 4 spec):
  `docs/plans/2026-04-21-chalk-mop-migration-plan.md`
- The two existing scheduler-adjacent design docs:
  `docs/plans/2026-02-23-sea-of-nodes-cfg-design.md`
  `docs/plans/2026-02-23-eager-pinning-cfg-statements.md`
