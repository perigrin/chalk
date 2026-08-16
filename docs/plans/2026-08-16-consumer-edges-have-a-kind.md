# Consumer edges have a KIND, and the graph currently forgets it

**Date:** 2026-08-16
**Status:** PLAN, v3. NOT started, NOT a blocker for anything, and NOT the
step-5 unblock. What it is: a real duplication in how control is represented,
plus a statement of what the right fix looks like when someone does need it.
**Motivating findings:**
`docs/research/2026-08-16-pinning-is-not-effectfulness.md` (the four op-name
lists are edge facts in node-name clothing),
`docs/plans/2026-08-13-post-merge-statement-ownership.md`.

> **Iteration history. Three passes, two of my own claims falsified — both by
> measurements available before I wrote them.**
>
> **v1** was drafted on the belief that step 5's four failed attempts each
> "substituted a node-kind proxy for an edge property", making edge kind the
> missing primitive. FALSIFIED by the attempt table in the document I was
> citing: attempt 2 ran the query directly via `control_in` and still produced
> malformed IR (Q5). Demoted to optional ergonomics.
>
> **v2** claimed a second defect that would have un-done that demotion —
> control is STORED two ways (`control_in` field vs `inputs[0]` on If/Loop), so
> attempt 2's query "silently excludes every If and Loop". FALSIFIED by one
> script: If and Loop also override the READER, and their own comments say
> that is why. A built graph returns the correct control predecessor for If,
> Loop and Print alike. The storage split is real; the consequence I drew from
> it was not.
>
> **v3** keeps v2's one durable contribution — the statement of what the
> CORRECT outcome is, as opposed to the smallest diff — and restores v1's
> conclusion, which measurement has now survived twice.

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

## A second defect — CLAIMED in iteration 2, then RETRACTED by measurement

Iteration 2 found that control is STORED two ways and concluded the query was
therefore broken for two node classes. The storage claim is true; the
conclusion drawn from it was false, and the measurement that killed it took one
script.

Storage does differ by class:

| class | where its control predecessor is STORED |
|---|---|
| `Chalk::IR::Node` (base) | the `control_in` FIELD (`Node.pm:31`, set at `:222`) |
| `Chalk::IR::Node::If` | `inputs->[0]` — `set_control_in` OVERRIDDEN (`If.pm:44-50`) |
| `Chalk::IR::Node::Loop` | `inputs->[0]`, backedge at `inputs->[1]` (`Loop.pm:30-55`) |

But `If` and `Loop` **also override the `control_in` READER**, with comments
that say exactly why: "CFG nodes carry their control input in inputs[0]
(convention), not in the base $control_in field. Override the reader so a
walker that calls `$node->control_in()` gets a consistent answer."

Measured on a built graph — `$start` wired as control to an `If`, a `Loop` and
a `Print`, then queried attempt-2 style:

    If->control_in:    Start   YES
    Loop->control_in:  Start   YES
    Print->control_in: Start   YES

**The query is uniform. Attempt 2 was not silently excluding If/Loop.** The
dual storage is an internal inconsistency — two homes, one reader papering over
it — not a correctness hole in the query, and NOT an explanation for attempt 2.

So Q5's v1 answer STANDS unqualified: attempt 2 asked the right question,
correctly, and still produced malformed IR. The failure is the
collection/emission contract, exactly as the post-merge plan says.

What survives of the v2 finding: `If`/`Loop` maintain a second storage location
and a compensating reader override, which is real duplication worth removing —
but on its own merits, not as a step-5 unblock.

## The correct outcome — not the smallest change

The first draft of this section proposed adding a `$kind` argument, keeping
`consumers()` unchanged so no reader breaks, and adding two filtered accessors.
That is the smallest diff. It is not the right answer, and the Graal work says
why.

`docs/research/2026-08-16-pinning-is-not-effectfulness.md` established that
production Sea-of-Nodes compilers do not answer structural questions with
hand-maintained lists — they make the answer a property with **nowhere to put
the wrong answer**. The same standard applies here. A `$kind` parameter that
defaults to `'data'` and is passed correctly at four call sites is a
hand-maintained list with extra steps: every future `add_consumer` caller can
silently get it wrong, and nothing detects that.

What Graal actually does is worth copying at the level of PRINCIPLE, not
mechanism:

- **an edge's kind is derivable from WHERE IT IS ANCHORED, not from a label
  passed alongside it.** Graal's `@Input` vs `@Successor` annotations are
  declarations on the field, and the node's edge set is walked positionally.
  There is no per-call kind argument to get wrong.
- **one relation, one home.** A Graal node's control successors live in
  `@Successor` fields; there is no second unrelated place a control edge can
  hide.

Chalk violates the second point today, and the first point is what the `$kind`
proposal would violate tomorrow.

So the target is:

1. **One home for control.** Either `control_in` for every class (If/Loop stop
   overriding, their `inputs[0]` control slot is removed), or `inputs[0]` for
   every class (the base `control_in` field is deleted). Pick ONE. The choice is
   open (see Q7) but the ambiguity is not.
2. **`control_consumers()` / `data_consumers()` derived from that home**, not
   from a label recorded at add time. If control has one home, kind is a
   FUNCTION of the graph and cannot drift from it — the `$kind` argument is
   unnecessary and the failure mode it introduces does not exist.
3. **`consumers()` keeps returning the union**, because 35 readers depend on it
   and most legitimately want all consumers.
4. **An invariant test** asserting the two views partition `consumers()` exactly
   — every consumer is in exactly one, for every node in every corpus graph.
   That is the "nowhere to put the wrong answer" property.

Under this target `_collect_body_recursive` does what its comment says, AND the
If/Loop hole closes, AND no caller can introduce a mislabelled edge because
there is no label.

The cost is higher than the additive version: it touches `If`, `Loop`, and
every reader that reaches `inputs[0]` on an If or Loop expecting control there.
That cost is the point — the additive version leaves the second defect in place
and adds a new way to be wrong.

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

   **v1's consequence: demoted to "an ergonomic and honesty improvement".** The
   earlier framing — repeated by me in two commit messages and one plan edit —
   that step 5's four attempts "each substituted a node-kind proxy for an edge
   property" is WRONG for attempt 2, which used the edge property directly.
   That claim should not be carried forward.

   **v2 tried to qualify this and was wrong; v3 restores it unqualified.** The
   v2 argument was that attempt 2's query reads `$c->control_in`, which is
   undef for If and Loop because they store control in `inputs[0]`. Measured:
   they override the READER as well, their comments say that is deliberate, and
   a built graph returns the correct predecessor for all three node kinds. The
   query was uniform. See "A second defect — CLAIMED then RETRACTED".

   So: attempt 2 asked the right question, correctly, and still scored 3
   against a baseline of 5. Edge kind is not what step 5 is missing.

6. **Ordering.** Does `consumers()` need to preserve insertion order across the
   split? At least one existing behaviour depends on graph walk order
   elsewhere in the project; assume yes until measured.

7. **NEW in v2 — which home for control wins?** The two candidates are not
   equivalent and the choice has consequences beyond tidiness:

   - **`control_in` field for everyone** (If/Loop drop their overrides).
     Control stops occupying an `inputs` slot, so `inputs` becomes purely
     data — which makes `inputs`-based walks correct by construction and is
     closer to what `_register_consumers` already assumes. Cost: every reader
     that reaches `If->inputs->[0]` for control must change, and `Loop`'s
     backedge at `inputs[1]` needs a home too (a second field, or a
     `backedge_in`).
   - **`inputs[0]` for everyone** (the base `control_in` field is deleted).
     One list, positional, closest to C2/Graal where control is just an edge.
     Cost: much larger — every `set_control_in`/`control_in` reader across the
     codebase changes, and `content_hash` deliberately EXCLUDES `control_in`
     today (`Node.pm:25-31`: "side-effect vs pure-data uses of the same content
     should still hash-cons to the same node"), which moving control into
     `inputs` would break unless the hash explicitly skips position 0.

   That last clause is decisive-looking and must be checked rather than
   trusted: if control lives in `inputs`, does `_serialize_inputs` include it,
   and would two identical Prints at different control positions stop
   hash-consing? For per-call ops it does not matter (they never hash-cons),
   but for anything hash-consed it would be a behaviour change. **Measure
   before choosing.**

8. **NEW in v2 — is the If/Loop split load-bearing anywhere else?** It was
   found by reading `set_control_in`. Nothing has yet checked whether other
   walks silently mis-answer for If/Loop the way attempt 2's query did.
   `grep` for `->control_in` and classify each site by whether an If or Loop
   can reach it.

## Sequencing — v3

This plan unblocks nothing. Two attempts to argue otherwise were falsified by
measurement. So it is scheduled behind the work it was drafted to serve, and
the only thing available today is honesty:

- **Available now, one line:** fix `_collect_body_recursive`'s comment
  (`Context.pm:4147`) so it stops claiming a control-edge walk the code does
  not perform. Independent of everything else here.
- **File separately:** the If/Loop dual storage plus compensating reader
  override. It is real duplication and it is NOT an explanation for anything —
  file it on its own merits so it does not get re-derived as a theory of
  step 5 a third time.
- **Step 5's actual prerequisite** is its ownership CONTRACT, written as a
  testable invariant before either walk is edited, with collection and emission
  changed in one commit. Nothing in this plan is needed for it.

**When something does need this**, build the version in "The correct outcome"
— control gets one home, the two views are DERIVED from it, and a partition
invariant makes a wrong answer unrepresentable. Do not build the additive
`$kind` version; it is the smallest diff and the wrong shape, for the reason
the Graal research established.

Q1-Q4 stay unanswered until a consumer states a need. Designing the taxonomy
first is how the four op-name lists happened. The derived design also makes
Q1/Q2 much less pressing: if kind is a FUNCTION of where control is anchored
rather than a label passed per-edge, adding a third kind later changes one
derivation instead of migrating every call site.

## What this episode is evidence of

This document falsified two of its OWN central claims across three passes, and
both measurements were available before the claim was written.

**v1's premise:** "step 5's four attempts each substituted a node-kind proxy for
an edge property." I had already written that into two commit messages and a
plan edit. The attempt table in the very document I was citing says attempt 2
used `control_in` directly. One `grep` of a file already open in this session.

**v2's premise:** "If/Loop store control in `inputs[0]`, so attempt 2's query
silently excludes them." I read `set_control_in`'s override, inferred the reader
must therefore disagree, and did not read the next twenty lines — where both
classes override the reader too, with a comment saying precisely why. One
script on a built graph.

Both are the same shape as the `alloca` claim (`5dd833ed`), the BinOp
control-slot claim (`5f1573c7`), and "%DATA_CLASSES is a trust boundary"
(`52e8146d`): read part of a mechanism, infer the rest, write the inference as
a finding, build on it. Five instances now.

The specific tell, common to all five: **each inference was about what some
OTHER code must be doing, based on what the code in front of me was doing.**
The alloca claim inferred a producer from a comment about a choice. The BinOp
claim inferred the producer's shape from a test's construction convention. v2
inferred a reader from a writer. In every case the other code was one file
open away.

Worth noting what DID work, twice: the corrections came from writing the claim
down in a form specific enough to test. "Attempt 2 silently excludes If/Loop" is
falsifiable in a way that "the graph forgets edge kinds" is not. The discipline
that pays is not "measure more" in the abstract — it is stating the claim
sharply enough that the measurement is obvious.
