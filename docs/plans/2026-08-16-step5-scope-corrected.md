# Step 5 scope, corrected: the producer half is DELETE-THE-DISCRIMINATOR

**Date:** 2026-08-16
**Status:** SCOPE. Not started.
**Backend half:** LANDED (`60a4bec6`) — a different fix from what the
2026-08-13 plan predicted.

> **CORRECTION to `docs/plans/2026-08-16-postmerge-baseline-remeasured.md`
> (843fcd2f).** That doc said "the producer half is GONE", having checked the
> working tree and `pu` only. **It is not gone. It is PARKED**, exactly where
> the 2026-08-13 plan said to put it: branch `modifier-effect-in-arm-parked`,
> commit `98d7d24` "PARKED: effect-bearing modifier in an if/else arm builds
> real control flow" — 107 lines in `FromOptree.pm` plus a 98-line test.
> I looked for uncommitted changes and did not run `git branch`.
>
> This changes the scope below in one way worth stating: the parked commit is
> the SAME approach I started re-deriving today — build control flow at the
> refusal site, still gated on the `_arm_has_*` predicates. So it is not a
> shortcut to the work described here; it is a second instance of the design
> the prior art rejects. Read it for its test and its construction code, not
> for its gate.

## What happened today, and why the scope needed correcting

The backend miscompile was fixed (`60a4bec6`) and the remaining three cases in
the shape suite still SKIP on a producer GAP:

    GAP: statement modifier with a void effect / element store / die
         inside an if/else arm not yet lowered

I started fixing that by adding control-flow construction at the refusal site,
gated on the same `_arm_has_*` predicates the site already consults — i.e. **a
fifth arm-content scan**. perigrin stopped it by asking whether this was the
Phi-tracing question already researched. It was.

`docs/research/2026-08-13-branch-merge-prior-art.md` (107-agent survey,
adversarially verified) says, verbatim:

> **RECOMMENDATION — Take path (b): delete the discriminator, always build
> control flow in void context, add a later collapse pass. The four
> `_arm_has_*` predicates are not fixable by adding a fifth**, because the
> three bugs and the measured overlap ... are symptoms of the
> disjunctive-content-gate structure itself, which is the exact failure mode
> LLVM documented.

The edit was reverted before it was committed.

## Three reasons the discriminator cannot be repaired in place

Quoted from the survey, and one of them I re-confirmed by accident today:

1. **Nested-if is UNFIXABLE by predicate refinement.** A nested `if` inside an
   arm compiles to the SAME `and` op as a statement modifier — B::Concise gives
   `and(other->h) vK/1` for both, with no distinguishing flag. No content
   predicate at that point in the walk can separate them.

   **Re-confirmed today, the hard way.** My first producer test asserted
   against `if (1) { $a[0] = 9 if $c; }` — which already translates. The shape
   that actually GAPs is `if ($c) { if ($d) { $a[0] = 9 } }`, a nested branch
   with no modifier at all. The GAP's own message names only the modifier. A
   test written from the message passes vacuously.

2. **A disjunction of effect kinds is the wrong SHAPE, regardless of
   completeness.** LLVM asks ONE whole-instruction question,
   `isSafeToSpeculativelyExecute`, which is strictly STRONGER than
   effect-freedom — it also rejects pure-but-faulting ops (division, loads,
   malloc, terminators, PHI). Chalk's enumeration would be unsound even if it
   listed every effect kind: a collapse gated on "no call / no store / no die"
   would still wrongly hoist a Perl division or an element read of a
   possibly-nonexistent slot.

3. **Measured overlap makes the outcome order-dependent, not content-dependent.**
   From `docs/research/2026-08-13-arm-content-inspection-measured.md`: 866
   predicate calls over 117 distinct arm shapes; **101 of 117 scanned by more
   than one predicate, 60 by all four, 44 arms carrying more than one effect
   kind simultaneously.** Where several are true at once the FIRST CALLER WINS,
   so which answer the code gets depends on call-site ordering. That is
   precisely the LLVM `SimplifyCFG` pathology its own developers call "a
   horrible inconsistent mess".

## What production compilers do instead

- **Graal** erects a full If/Begin/End/Merge/Phi diamond unconditionally, even
  when one arm is a bare value copy. Because effectful nodes are fixed BY TYPE,
  an arm containing one is simply NOT EMPTY — so the collapse precondition is
  the structural test `trueSuccessor().next() instanceof AbstractEndNode &&
  falseSuccessor().next() instanceof AbstractEndNode`, `anchored().isEmpty()`,
  `hasNoUsages()`. **The side-effect question is subsumed and never asked.**
- **TurboFan** threads one effect chain through every node whose operator
  declares an effect input.
- **Braun et al.** place phis solely on variable reads, consulting only
  `sealed` and `|block.preds|`.
- Diamond-to-select collapse is **universally a LATER pass over finished IR**.

"Does this arm contain an element store" is a question the mature
implementations never ask.

## The corrected scope

### Measured today, replacing the plan's stale figures

| | 2026-08-13 plan | measured 2026-08-16 |
|---|---|---|
| predicates | 4 | 4 — `_arm_has_element_store` (:3844), `_arm_has_field_store` (:3867), `_arm_has_void_call` (:3907), `_arm_has_die` (:3951) |
| call sites | "15" | **22 references, of which 16 are real calls** at **4 gate sites**; the other 6 are comments |

The four gate sites (`~/dev/perl5-son/lib/SoN/FromOptree.pm`):

- **:380-382** — the top-level void `and`/`or` `$mem_branch` gate. THE PRECEDENT:
  when true it already builds `If` + two `Proj`s and merges via
  `$sim->merge($rhs_sim, $factory, $if_node)`.
- **:516** — a 2b-3 mixed-effect refusal inside that same handler.
- **:4119-4127** — the if/else `$elem_branch` gate (8 calls: each predicate run
  on BOTH arms).
- **:4363-4365** — the modifier/nested-branch-inside-an-arm refusal. **This is
  the site that produces the remaining GAP**, and the one I was about to add a
  fifth scan to.

Plus **:4152-4153**, two more `_arm_has_die` calls used for die-arm polarity,
which are a different question (which arm terminates) and need their own
answer, not deletion by association.

### The work

1. **Build control flow unconditionally in void context.** Delete the
   `$mem_branch` / `$elem_branch` gates; always emit `If` + `Proj`s + merge.
   The construction code already exists at :383-397 — this deletes its
   condition, not its body.
2. **Delete the four predicates and their 16 calls**, except the :4152-4153
   die-polarity use, which must be re-expressed structurally (an arm that
   terminates has no edge to the merge) rather than by scanning.
3. **Add the collapse pass** over finished IR. Its gate, per the survey's own
   "cheapest sound version": Graal's structural emptiness test — both arms
   empty of fixed nodes, no anchored usages — which `is_fixed` (LANDED,
   `20e31d5d`) already makes answerable. Plus ONE speculation-safety predicate
   over residual pure-but-faulting Chalk ops (division, modulus,
   possibly-nonexistent element read, anything that can die), modelled on
   `isSafeToSpeculativelyExecute`.
4. **Skip the cost budget initially.** It is a PROFITABILITY gate, independent
   of soundness, and its inconsistent thresholds are what LLVM's developers
   call the mess. Add it when select-formation measurably regresses.

### What is NOT in scope

- The `%CONTROL_CHAIN_OP` / three-axes work
  (`docs/research/2026-08-16-pinning-is-not-effectfulness.md`). Related — it is
  the same "structural question answered by content inspection" family — but a
  separate change.
- Consumer edge kinds (`docs/plans/2026-08-16-consumer-edges-have-a-kind.md`),
  which measurement showed unblocks nothing here.
- The backend ownership rule: already landed.

## The RED that already exists

TWO versions exist, and the difference matters:

- **on the parked branch** (`modifier-effect-in-arm-parked`, 98 lines) — written
  for the rejected gated design.
- **written today**, RED against `pu`, preserved in the session scratchpad as
  `producer-red-2026-08-16.t`. NOT left in the producer tree: an untracked file
  of that name blocks `git checkout modifier-effect-in-arm-parked`, and losing
  access to the parked branch to keep a scratch test is a bad trade.

The version written today pins the producer side:

- a nested-branch element store inside an arm must not skip the entry graph
- a nested-branch void print inside an arm must not skip it either
- the two shapes that ALREADY work must keep working — a plain
  modifier-in-arm element store, and a pure rebind, which must still merge as
  `TernaryExpr` and NOT gain control flow

That third subtest is the regression guard for step 1: building control flow
unconditionally in void context must not convert the pure-rebind merge into a
diamond, or `TernaryExpr` disappears from a case that depends on it.

Chalk-side, `t/bootstrap/ir/llvm-postmerge-read-ownership.t` (landed) runs both
polarities end to end against a perl oracle.

## Sequencing note

The backend half is landed and independently verified, so the producer half can
proceed on its own — it no longer risks converting a loud GAP into a silent
miscompile, which is why the 2026-08-13 plan said the producer change "must not
land alone".

Expected movement: `term.t` and `translate.t` are the two t/base files blocked
on this GAP (measured, `tbase-worklist.t`). Both should move from SKIP toward
PASS, though neither is guaranteed — each newly-reachable file reveals its own
next blocker, which is the pattern every prior payoff prediction in this
project got wrong.
