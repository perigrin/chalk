# Consumer edges have a KIND, and the graph currently forgets it

**Date:** 2026-08-16
**Status:** PLAN, v1, and its own central premise is ALREADY FALSIFIED — see
open question 5, answered during the first pass. Retained because the defect it
describes is real and the measurements are worth keeping, but this is NOT a
blocker for anything and must not be scheduled as one.
**Motivating findings:**
`docs/research/2026-08-16-pinning-is-not-effectfulness.md` (the four op-name
lists are edge facts in node-name clothing),
`docs/plans/2026-08-13-post-merge-statement-ownership.md`.

> **READ Q5 FIRST.** This plan was drafted on the belief that step 5's four
> failed attempts each "substituted a node-kind proxy for an edge property",
> making edge kind the missing primitive. That is false for attempt 2, which
> performed the exact query directly via `control_in` and still produced
> malformed IR. Edge kind is an ergonomic improvement, not an unblock.

## Relationship to the other open work — this REPLACES nothing

Stated because it was asked, and because two adjacent things have already been
conflated in this arc:

| work | question it answers |
|---|---|
| the three-axes finding (supersedes step 4d) | WHICH nodes require ordering |
| **this plan** | HOW an ordering is carried, and how a walk QUERIES it |
| post-merge ownership (step 5) | WHO emits a post-merge statement |

They compose and none substitutes for another. The three-axes finding makes the
requirement *statable*; step 5 has to decide a contract.

**This plan's row is weaker than it looks.** The edge is ALREADY queryable —
`control_in` records a node's control predecessor, and a reader holding node N
can ask "is C a consumer whose `control_in` is N?" today. What this plan adds is
that the answer becomes DIRECT rather than reconstructed, and that
`consumers()` stops conflating two things in one list. That is ergonomics and
honesty, not capability. See Q5.

## The defect, in one line

`Chalk::IR::Node::add_consumer($node)` (`Node.pm:59`) appends to a single
undifferentiated list. Control edges and data edges go into the same array and
become indistinguishable on arrival.

The clearest symptom is `_collect_body_recursive` (`Context.pm:4147`), whose
comment states one thing and whose code does another:

    # Recurse into consumers that have this node as a control predecessor.
    my $consumers = $node->consumers // [];
    for my $c (@$consumers) {
        next unless defined $c;
        _collect_body_recursive($c, $visited, $body);
    }

The comment describes a control-edge walk. The implementation is an any-edge
walk. Nothing in the graph declares which edges are control, so the discrepancy
is invisible and survived review.

## The information EXISTS at the add site — it is discarded on arrival

This is what makes the fix small. Measured, every `add_consumer` call in
`lib/Chalk/IR/` already knows which kind it is passing, and the control ones
are syntactically distinct:

| kind | site | shape |
|---|---|---|
| control | `Node.pm:228` | inside `set_control_in`, `$ctrl->add_consumer($self)` |
| control | `If.pm:48` | `$ctrl->add_consumer($self)` after `inputs->[0] = $ctrl` |
| control | `Loop.pm:34` | `$ctrl->add_consumer($self)` after `inputs()->[1] = $ctrl` |
| control | `Loop.pm:54` | `$ctrl->add_consumer($self)` after `inputs()->[0] = $ctrl` |
| data | `NodeFactory.pm:187` | `$elem->add_consumer($node)` (arrayref input) |
| data | `NodeFactory.pm:191` | `$input->add_consumer($node)` (scalar input) |
| data | `NodeFactory.pm:230` | Phi values |
| data (assoc) | `NodeFactory.pm:225` | `$region->add_consumer($node)` — see open question 2 |
| data | `Phi.pm:23` | `$value->add_consumer($self)` |

No inference is required. The caller has the answer and drops it.

(The `add_consumer` methods on `MethodInfo`, `ClassInfo`, `FieldInfo`,
`SubInfo`, `UseInfo`, `Program` are a DIFFERENT unrelated API on the metadata
structs. Out of scope; do not touch them.)

## Readers: 35, concentrated, and several already hand-roll the filter

| file | count |
|---|---|
| `Target/LLVM/Context.pm` | 22 |
| `IR/Serialize/JSON.pm` | 3 |
| `IR/Schedule/Elaborate.pm` | 3 |
| `IR/Schedule/Dominators.pm` | 3 |
| `Target/LLVM/ElaboratedContext.pm` | 1 |
| `IR/Graph.pm` | 1 |
| `Bootstrap/Perl/Target/Perl.pm` | 1 (parked backend) |
| `Bootstrap/Perl/Target/C.pm` | 1 (parked backend) |

Sampling the `Context.pm` readers shows the missing primitive is already being
worked around, by op-name filtering at the use site:

- `:3320` — `grep { $_->operation eq 'Proj' } $if_node->consumers->@*`
- `:3502` — `next unless $c->operation eq 'Region'`
- `:3881` — walks `$loop_node->consumers` looking for a comparison, with the
  comment "This link is set by the ir-block author via
  `$cond->set_control_in($loop)`" — i.e. it wants the control consumers and
  reconstructs that by other means.

So "readers must be audited" partly overstates the cost: several are already
expressing "the control ones" in a longer, weaker way, and would become
shorter. Others genuinely want all consumers and need no change.

## The change

Additive, and `consumers()` keeps its current meaning so no reader breaks.

1. `add_consumer($node, $kind = 'data')`. Four call sites pass `'control'`.
2. `consumers()` — unchanged, returns every consumer. All 35 readers keep
   working with no edit.
3. `control_consumers()` / `data_consumers()` — new filtered accessors.
4. `remove_consumer` must drop the kind alongside the node.

Then `_collect_body_recursive` can do what its comment says.

## Verification, and the honest problem with it

**The corpus gate cannot discriminate this.** Two matches with both captures
read — and the post-merge ownership shape generally — is exactly what the shape
leg does not check: it does not check operands of control-reachable nodes
(`docs/plans/2026-08-03-effect-chain-followups.md` Part A1). A green gate after
this change proves only "no regression", never "the primitive is right".

So the test has to be unit-level and structural:

- every edge added by `set_control_in` reports kind `control`, and appears in
  `control_consumers` and not `data_consumers`
- every edge added from `inputs` reports kind `data`
- `consumers()` still returns the union, in the same order, for every node in a
  built graph (the ordering guarantee matters: memory notes DON'T change
  `Graph::nodes()` walk order, and the same caution applies here)
- `remove_consumer` removes from both views
- a node reached ONLY through a control edge is in `control_consumers` of its
  predecessor — the actual query step 5 needs

Plus the existing tiers as regression: `t/bootstrap/ir` and the corpus gate at
196, self-verified on committed HEAD.

## What this does NOT do

Stated plainly, because the temptation to over-claim here is the failure mode
this arc keeps hitting.

1. **It does not fix step 5, and it does not unblock it either.** That plan's
   diagnosis is that the collection walk and the emission walk disagree about
   who owns a post-merge statement, and that fixing one side alone yields
   double-placement or no-placement (attempts 2 and 4, both measured worse than
   baseline at 3 vs 5). Attempt 2 already ran the query this plan would make
   direct. Step 5 needs its ownership invariant written as a test first, and
   both walks changed in one commit — with or without this.
2. **It does not install the regex ordering edge.** The match family still has
   no edge from one Match to another. Edge kind gives that edge a place to
   live and a name; someone still has to build it (Graal's `FloatingReadPhase`
   installs `lastLocationAccess` in a phase, from a location-keyed memory
   state).
3. **It does not resolve the four op-name lists.** That is the three-axes
   finding's work.

## Open questions — THIS PLAN IS NOT READY UNTIL THESE ARE ANSWERED

1. **Is two kinds enough?** Graal distinguishes at least value, memory,
   association (`@Input(Association)` for a Phi's merge) and guard/anchor
   edges. Chalk has `Phi`'s region link and `Region`'s controls, which are
   arguably neither plain data nor control. Adding a third kind later is
   cheap; picking the wrong two now is not. **Needs a decision, informed by
   what the readers actually branch on.**

2. **What kind is the Phi/Region association edge?** `NodeFactory.pm:225`
   registers `$region->add_consumer($node)` for a Phi's region. The comment
   there says "The region is a use-def input even though it's tracked as a
   named field". Calling it `data` is the status quo; calling it
   `association` may be more honest. Unresolved — and it interacts with (1).

3. **Does any node have BOTH a control and a data edge to the same
   predecessor?** If so, is the kind a property of the EDGE (needing a
   multiset) or a property of the PAIR (a lookup suffices)? Not yet measured.
   **This determines the data structure and must be answered before coding.**

4. **What do the 22 `Context.pm` readers actually want?** Four were sampled;
   eighteen were not. The estimate that "several would get shorter" is based
   on three examples and should not be trusted as a cost estimate until all 22
   are classified into wants-all / wants-control / wants-data.

5. **ANSWERED, and it goes AGAINST this plan. `control_in` is already the
   answer, and the query has already been tried.**

   Attempt 2 of step 5 was, verbatim from its table: "recurse only into
   consumers whose `control_in` is this node". That is EXACTLY the query edge
   kind would enable, performed with the existing `control_in` field and no new
   primitive. Result: **3 — malformed IR, exit=1**, against a baseline of 5.
   Attempt 4 cut the same edge a different way (skip Phi consumers) and also
   scored **3**, with the collection now provably correct
   (`Proj#6 -> [Assign#7]`) and NOTHING emitting the Print.

   So the missing piece is NOT expressibility. A walk can already ask which
   consumers are control successors, today, with one field access. The failure
   is that the OTHER walk does not then pick up what the first correctly drops
   — the collection/emission contract, exactly as that plan states.

   **Consequence for this plan: it is demoted from "the primitive step 5 needs"
   to "an ergonomic and honesty improvement".** The earlier framing —
   repeated by me in two commit messages and one plan edit — that step 5's four
   attempts "each substituted a node-kind proxy for an edge property" is WRONG
   for attempt 2, which used the edge property directly. That claim should not
   be carried forward.

   What survives as justification: `_collect_body_recursive`'s comment still
   contradicts its code, several readers still reconstruct "the control ones"
   by op-name filtering, and a graph that cannot name its own edge kinds is
   harder to reason about. Those are real but they are NOT correctness
   blockers, and they do not unblock anything.

6. **Ordering.** Does `consumers()` need to preserve insertion order across the
   split? At least one existing behaviour depends on graph walk order
   elsewhere in the project; assume yes until measured.

## Sequencing — REVISED after Q5

Step 0 was "determine whether attempt 2's failure was expressibility or
contract, and if the latter, this plan drops in priority sharply." It was
answered on the first pass, from that plan's own table: **contract**. So this
plan drops in priority sharply, as specified.

It is now optional cleanup, correctly ordered AFTER the thing it was drafted to
unblock:

- **Not now:** step 5's real prerequisite is its ownership CONTRACT, written as
  a testable invariant before either walk is edited, with collection and
  emission changed in one commit. Nothing in this plan is needed for that.
- **Whenever:** if the contract work ends up wanting a cleaner way to say
  "control successors", land the primitive then, informed by what that work
  actually needs — rather than guessing the shape now from Q1-Q4.
- **Standalone value, small:** fix `_collect_body_recursive`'s comment so it
  stops describing a walk the code does not perform. That is a one-line honesty
  fix available today and independent of everything above.

Q1-Q4 remain unanswered and should stay that way until there is a consumer with
a stated need. Designing the taxonomy first is how the four op-name lists
happened.

## What this episode is evidence of

Recorded because it is the third instance in this arc of the same error.

The plan was drafted from a claim I had already written into two commit
messages and a plan edit — "step 5's four attempts each substituted a node-kind
proxy for an edge property" — without checking it against the attempt table in
the very document I was citing. The table says attempt 2 used `control_in`
directly. One `grep` falsified the premise, and it was a `grep` of a file
already open in this session.

Same shape as the `alloca` claim (`5dd833ed`), the BinOp control-slot claim
(`5f1573c7`), and the "%DATA_CLASSES is a trust boundary" claim (`52e8146d`):
a plausible mechanism asserted from adjacent reading, then built upon, then
falsified by a one-line measurement. The measurement is always cheap and always
available BEFORE the writing.
