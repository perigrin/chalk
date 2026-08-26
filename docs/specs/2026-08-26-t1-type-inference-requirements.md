# T1 — what building it actually requires

**Date:** 2026-08-26
**Status:** REQUIREMENTS. T1 does not exist. This says what would have to be
true for it to.

## Why this document exists

On 2026-08-26 I attempted the loader/T1 split by deleting `from_json`'s call to
`Chalk::IR::Analysis` and changing its return shape. The corpus gate fell
**218 → 136** and the change was reverted whole.

The cause was not a bug in the edit. **There was no T1 to split to.** What
exists is `Chalk::IR::Analysis` — the same eleven passes the loader always ran,
with their bodies relocated into one file (`f92c6869`). Relocating code is not
building a transformation, and I let the two read as the same thing: perigrin
chose "build T1 as a class first, wire it after", I agreed, and then committed
a file move whose message described where T1's body *would* live.

So this document is the thing that was missing — the requirements, written
before the build, so that "did we add T1?" has an answer that is not an
impression.

## What already exists, precisely

`Chalk::IR::Analysis::run($class, $graphs, $classes = undef)` →
`($graphs, $mop)`.

- eleven passes, seventeen invocations, in a load-bearing order arrived at
  incrementally against the corpus gate;
- pass bodies now co-located (the load cycle with the serializer is gone);
- called from `from_json`, so every caller receives an analysed graph whether
  or not it asked.

That is a **pass sequence**. T1 is a transformation with a contract, and the
gap between them is this document.

## Entry contract

    Chalk::IR::Transform::TypeInference->new(...)->run($graph) -> $graph

- **`Graph -> Graph`.** The same shape optimizer passes use
  (`Optimizer::Pass`), because it composes and tests in isolation — but T1 is
  a REQUIRED STAGE, not an optimizer. The test: *can the compiler still produce
  a correct program without it?* Optimizer yes, T1 no. It must not live under
  `Optimizer::`.
- **Per graph, not per graph-set.** The current `run` takes `%graphs` because
  the whole-program passes (call resolution, cross-call argument seeding) need
  the set. Those are 4b and are separable; the per-graph core is 4a.
- **No `$classes` parameter.** Class metadata reaching inference as a separate
  hashref is the shape that broke the split: the MOP comes out of
  `_replay_classes`, one of the passes, so a caller cannot obtain a MOP without
  running inference. See "The MOP problem" below — it must be resolved before
  the entry contract is stable.
- **Entered from the pipeline**, not from the loader. `Loader > T1 >
  Optimizers > T2 > Optimizers > Scheduler`. Self-hosted there is no loader at
  all (the frontend is chalk's own parser), so anything reachable only via
  `from_json` is dead code in the configuration that matters.

## T1 receives a PARTIALLY TYPED graph

This is the input assumption, and it shapes everything else.

The frontend already stamped what it could. B::SoN carries a real lattice and
does real LCA joins; chalk's own parser will too. So T1's input is not an
untyped graph awaiting types — it is a graph carrying the frontend's answers,
some narrow, some `Unknown`, some absent.

Three consequences:

- **`Unknown` is an INPUT VALUE, not a hole.** It is the frontend saying "I
  could not determine this", which is information: it distinguishes a value
  inference genuinely failed on from one nobody has looked at. Treating it as
  absence discards that distinction. (This is also why the eventual `Unknown`
  policy decision matters — see prerequisites.)
- **T1 NARROWS, it does not assign from scratch.** Its job is to take what the
  frontend committed to and make it as narrow as the program permits, using
  information the frontend could not have: whole-program call resolution,
  cross-graph argument types, container monomorphism. Those are exactly the
  facts a single-unit frontend cannot see.
- **T1 must never WIDEN a frontend stamp without cause.** If the wire says
  `Int` and T1 produces `Scalar`, that is a regression in precision even though
  both are sound. The only legitimate widening is a JOIN that the graph
  requires (a merge whose arms genuinely disagree), and it must be traceable to
  that merge.

**And T1 does not trust the input.** "Partially typed" is not "correctly
typed": the frontend can be wrong, and today's producer has been (an aggregate
parameter unstamped for a stale reason; `@_` stamped `Unknown` because nothing
asked). So T1 re-derives what it can and **reports a contradiction** rather
than silently preferring either side — the pattern slice 2 already established
for method return types ("refusing rather than picking silently").

Self-hosted there is no second opinion to compare against, because the frontend
IS chalk. Then the check is internal consistency — conformance and soundness —
not agreement with a producer.

## What T1 owns

The type axis, and only that. It assigns lattice types; it chooses no machine
encodings and knows nothing about LLVM.

Its output is well-typed per the five conditions in
`docs/plans/2026-08-24-loader-analysis-pipeline.md` §"What well-typed means":
**total, lattice-membered, conformant, sound, maximally narrowed.** Condition 5
is part of correctness, not a quality metric: T1's output feeds a stage that
must pick an encoding, so an un-narrowed type does not produce a slower program
— it produces a boxed one, a GAP, or a later stage guessing.

## What T1 does NOT own, and must stop inheriting

Two behaviours currently sit in the loader and are inference, not
deserialization. They move to T1 — but only when T1 exists, because removing
them without it is what cost 82 corpus cases:

1. **The `Print` → `Boolean` seed** (`Serialize/JSON.pm`, in the node walk).
   Deriving an operator's result type from its semantics is inference wherever
   it happens.
2. **`%LOWERABLE_STAMP`** — a six-name filter on which wire stamps may enter
   the representation field. It asks "can the BACKEND lower this?", which is
   T2's question asked two phases early. Its effect is that the loader
   **discards type information the frontend sent**.

   MEASURED: removing it alone drops the gate to 136, with 78 failures naming
   `Unknown`. Nothing downstream can receive an un-narrowed type today because
   the phase that would resolve or cleanly refuse it does not exist. **It stays
   until T2, and it does not belong in the loader even then** — it moves to T2
   as a refusal with a diagnosis rather than a silent drop.

## The MOP problem — resolve before the entry contract

`_replay_classes` builds the MOP, and it is one of the eleven passes. So today
the MOP is an *output of inference*, which forces `run` to return
`($graphs, $mop)` and forces every consumer to obtain both together.

perigrin's position: **the MOP is part of the stamp/IR**, and
`_build_registry_from_mop` is a code smell — a second copy of what the MOP
already knows, rebuilt at lowering time. Today's failure is evidence: passing
the wrong thing produced `Can't call method "can" on unblessed reference`
rather than a typed refusal.

If the MOP rides on the IR, then T1 neither takes class metadata nor returns a
MOP; it types a graph whose class information is already present. That makes
the entry contract `run($graph) -> $graph` honestly, instead of by omission.
**This is a prerequisite, not a follow-up.**

## Acceptance

Not "the gate still reads 218" — that measures behaviour over 218 programs, and
2026-08-25 shipped three real bugs with the gate green throughout.

1. `t/bootstrap/ir/loader-reproduces-the-wire.t` reads **0** and asserts. It
   measures decode-then-re-encode; today it reads 16, every one the loader
   overwriting what the wire sent. Zero means the loader reproduces and T1
   types.
2. The five conditions hold, **including maximal narrowing** — so tests measure
   HOW NARROW, not merely whether typed. A regression widening `Int` to
   `Scalar` passes a typed/untyped check and must fail this one.

   Because the input is partially typed, narrowing is measurable as a
   **before/after comparison on the same graph**, which is stronger than an
   absolute score:

   - **no stamp may widen** without a merge that requires it — `Int` in,
     `Scalar` out, is a failure;
   - **`Unknown` count must not rise**, and should fall;
   - **the count of narrowed nodes** (strictly-below-input type) is the number
     that must trend up, per corpus case, tracked like the gate floor.

   That comparison needs no oracle: the input graph IS the baseline.
3. Conditions 1 and 2 do NOT hold today: 10 untyped Value nodes (2 `Call`,
   1 `Ref`, 7 downstream `Phi`) and `Slot` — a machine encoding — reaches the
   stamp field via the OOB path. **The first version therefore REPORTS rather
   than asserts.** An assertion that must be disabled to land is what
   `_assert_value_nodes_are_typed` already is.
4. The corpus gate holds at 218 as a floor, not as the definition of done.

## Prerequisites, in order

1. **The MOP rides on the IR** (above). Without it the entry contract is a lie.
2. **`_join_repr` calls `join_types`.** `TypeLibrary::join_types` is a correct
   total LCA and the loader calls it ZERO times; `_join_repr` reimplements a
   weaker rule beside it (return whichever ARM dominates) that returns `undef`
   for siblings. Four separate sites improvise around that `undef`. Mostly
   subtraction — see §"4a" in the plan.
3. **Settle the `Unknown` policy.** `_join_repr` DROPS `Unknown` arms and joins
   the rest; `join_types` ABSORBS (any `Unknown` operand ⇒ `Unknown`). Opposite
   policies, both defensible, and the loader depends on dropping today. Decide
   deliberately, in one place, with the reasoning attached.

## What "serialization carries the frontend IR fully" bought

`to_json` never emitted a `stamp` field, so every type a graph carried was
dropped at serialization (`2b5dfe2e`). That is fixed, and it was a prerequisite
for all of the above: the round-trip test cannot measure the loader's contract
if the serializer loses the axis being measured. It also matters beyond
testing — `to_json` is the self-hosting output path, and there is a planned
bootstrap step where B::SoN parses Chalk itself. A serializer that drops types
means chalk cannot hand a typed graph to a future chalk.
