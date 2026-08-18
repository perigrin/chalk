# Phi↔predecessor pairing is a LOOKUP everywhere else; Chalk makes it a SEARCH

**Date:** 2026-08-18
**Status:** FINDING, with prior art verified against primary sources. The
immediate miscompile is fixed (`ElaboratedContext::_proj_index_of_control`);
this records why that fix is a symptom and what removes the whole class.

## Why this was asked

perigrin, watching a third consecutive fix to the same question: *"It feels
like we are doing a lot more tree walking than maybe we need to be doing."*

The evidence for that instinct is the arc itself. Three fixes, each recovering
the same fact a different way:

1. assume phi slot 0 is the then-arm — WRONG, the producer builds Region
   inputs continuing-path-first
2. scan the Region's control inputs for a Proj with a given index (`44d1fa8c`)
   — WRONG when an arm contains an effect
3. walk BACKWARD along `control_in` from each Region input until a Proj is
   found — correct, and a search

Each fix made the search wider. That is the shape of a fact stored nowhere.

## What the other systems do (verified)

**Positional, in all three Sea-of-Nodes systems.** C2 states it verbatim
(`cfgnode.hpp:65-70`): *"Merged data inputs to PhiNodes correspond 1-to-1 with
RegionNode inputs."* Graal likewise (`PhiNode.java` javadoc): *"the order of
the values corresponds to the order of the ends."*

**And in every one of them the Region's input is a STABLE PER-EDGE CARRIER,
never "the last node in that predecessor":**

| system | what the merge's control input IS |
|---|---|
| Graal | `EndNode` — a `final class` with ZERO fields, existing only to be that edge; `verifyNode` asserts at most one usage |
| C2 | a control source at a fixed path index handed out by `next_path_num()` |
| V8 TurboFan | an `IfTrue`/`IfFalse` projection |
| **Chalk (producer)** | **the last effect in the arm** |

That last row is the defect. Nothing else does it.

**LLVM is the interesting exception**: it stores the block explicitly per
incoming value, and its `removeIncomingValue` is a *swap-with-last*, so slot
order carries no meaning at all. The Verifier sorts both lists before
comparing. LLVM chose explicit pairing precisely because predecessor order is
not stable.

## What maintains the invariant where it is positional

Three rules, identical in C2 and Graal:

1. **Born at equal arity** — C2's `PhiNode(Node *r, ...) : TypeNode(t, r->req())`;
   Graal asserts `merge().phiPredecessorCount() == valueCount()`.
2. **Grown in lockstep** — C2's `add_new_path` does `add_req` on the region and
   on *every* phi whose `region() == r`, asserting equal size.
3. **Shrunk through one choke point** — `RegionNode::Ideal` deletes index `i`
   from itself and from every attached phi; Graal's `killCFG` calls
   `removeEnd` rather than reimplementing it.

Worth stealing: C2's `del_req` is deliberately **order-destroying**
(swap-with-last) with a separate `del_req_ordered`. Applying the identical
permutation to both sides preserves PAIRING without preserving ORDER. C2 treats
predecessor order as meaningless and predecessor pairing as sacred.

## Chalk already has the ingredient, and already uses it in one of two frontends

`Proj` IS Graal's `EndNode`: a per-edge node with a stored `index` and a
`source` back-pointer (`Node/Proj.pm:10`).

Verified by hand, both sides:

- **Chalk's own frontend builds Regions from Projs** —
  `Actions.pm:2600` and `:2727`, `controls => [$true_proj, $false_proj]`.
- **The perl5-son producer does not** — `StackSim::merge` builds
  `Region(inputs => [$control, $other->control])`, i.e. each sim's current
  control, which is the last effect when the arm has one.

So this is a PRODUCER DIVERGENCE, not an IR-design constraint. One of Chalk's
two frontends already does the right thing.

Two more facts that point the same way:

- **The Loop case never breaks.** `%INPUT_SPECS` gives `Loop` named fixed-arity
  slots (`entry_ctrl`, `backedge_ctrl`) and `Phi::set_backedge` writes slot 1
  to match. `Region => ['controls']` is an unnamed variadic list — and that is
  the one that keeps breaking.
- **There is no verifier.** `TypedInvariant.pm` mentions Region once, in a
  comment, and Phi not at all. Every system surveyed closes this with an
  assertion: C2's `"broken Phi/Region subgraph"`, Graal's
  `phiPredecessorCount() == valueCount()`, TurboFan's
  `CHECK_EQ(value_count, control->op()->ControlInputCount())`.

## What removes the class

**Make a Region's control inputs be Projs, always** (fix the producer to match
Chalk's own frontend). Then `_proj_index_of_control` collapses from a bounded
backward walk with a seen-set to `$controls[$slot]->index` — a field read — and
`_phi_slot_for_proj` becomes an `indexOf` over two elements.

Fallback if producer conformance cannot be guaranteed: take LLVM's route and
store the Proj alongside each phi value, making the pairing data rather than
convention. Costs a parallel array; makes the misordering unrepresentable.

## Relationship to the edge-kind plan

`docs/plans/2026-08-16-consumer-edges-have-a-kind.md` already diagnosed the
general form — *"`add_consumer` appends to a single undifferentiated list.
Control edges and data edges go into the same array and become
indistinguishable on arrival"* — and measured that it unblocks nothing on its
own. This is the same missing primitive at the merge, where it DOES cause
miscompiles. That plan should cite this as its concrete cost.

## Honest limits

The prior-art claims are from a primary-source sweep with verbatim quotes; the
two Chalk-side claims (frontend uses Projs, producer uses the last effect) I
verified by hand in both repos before writing this. COULD NOT CONFIRM that any
compiler tried a backward-chain search like Chalk's and abandoned it — no
recognized name for the bug class was found. The closest analogue is V8
Turboshaft stamping an out-of-band `set_custom_data(kPhiInputIndex)` onto old
blocks to reconstruct correspondence, which is a side-channel serving the same
purpose and is the least-admired part of that design.
