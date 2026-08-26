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

**WHAT THAT FAILURE DOES AND DOES NOT ESTABLISH.** It is not decisive about the
design, and this document originally over-read it. Removing a phase that eleven
passes depend on, while changing nothing else, breaks the things that depended
on it — that is a fact about the current wiring, and the goal is NOT to preserve
the current implementation. T1 is expected to differ from `Analysis` in shape,
in what it consumes, and in what it guarantees.

Read the numbers as a FLOOR: they say what breaks if only the wiring changes,
which is useful for sequencing and useless as a constraint on the target design.
Every "prerequisite" below is a prerequisite for keeping today's code working —
a different T1 may dissolve several of them rather than satisfy them.

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

**A frontend stamp is EVIDENCE, not an axiom.** "Partially typed" is not
"correctly typed", and today's producer has shipped wrong stamps: an aggregate
parameter left unstamped because a comment described a die that had stopped
happening; `@_` stamped `Unknown` because nothing ever asked; an ADJUST block
dropped from the wire entirely by a bare `eval`. All three found by accident.

So where T1 independently derives a type and its answer CONTRADICTS the wire's,
that is an error to report — not a value to silently overwrite in either
direction. Slice 2 already does this for method return types: seed from the
wire, die on disagreement, "refusing rather than picking silently".

Three things this deliberately does NOT mean:

- **not** re-derive everything and discard the wire — that throws away the
  frontend's work, and "a pass to validate/update the values that ship across
  the wire is very different from throwing all of the data out";
- **not** distrust `Unknown` — it is an honest answer on input, with nothing to
  contradict;
- **not** an obligation to audit. T1 checks what it computes anyway; it does
  not do extra work to police the producer.

And note the frame breaks down at self-hosting, where the frontend IS chalk.
There is no second party to trust: a disagreement is chalk contradicting
itself, in one of two places you own. The check is internal consistency, not
verification of a supplier.

Self-hosted there is no second opinion to compare against, because the frontend
IS chalk. Then the check is internal consistency — conformance and soundness —
not agreement with a producer.

## THE EXIT CONDITION

**T1 NEVER HAS AN ABSENT TYPE — it normalizes on entry.** A Value node
arriving without a stamp is treated as `Unknown`, because that is what absence
means: no type was determined here. The only difference between the two is
whether some pass bothered to write the fact down, and that is not a difference
worth carrying through a transformation.

So there is exactly ONE exit condition:

> **No Value node leaves T1 stamped `Unknown`.**

Normalizing is not giving up on those nodes — it is the opposite. An absent
stamp is invisible to inference (nothing to narrow FROM, and guards that ask
"already decided?" read absence inconsistently); `Unknown` is a value in the
lattice that every rule can act on. Normalize first, then narrow as far as the
program permits. Absent means "not yet asked"; `Unknown` means "asked, and here
is the honest answer" — T1's job is to move nodes off `Unknown`, and it can
only do that for nodes it can see.

This also matches the producer, where the rule already holds structurally:
`SoN::IR::Value` requires a stamp at construction, so absence is impossible on
that side.

### Absent IS a distinct bug class — in the FRONTEND, not in T1

The distinction dissolves *for T1*, which normalizes both and treats them
identically from entry onward. It does not dissolve upstream, and conflating
the two there loses real information:

- **`Unknown` on the wire** — the frontend looked and honestly could not
  determine a type. Correct behaviour. Nothing to fix.
- **ABSENT on the wire** — the frontend never looked. No stamping rule covers
  that node kind. **That is a frontend bug.**

The producer's own design says so: `SoN::IR::Value` requires a stamp at
construction, so absence is structurally impossible there. **An absent stamp
arriving on the wire means something bypassed that constructor** — which is
exactly the shape of two bugs already found and fixed this month: `ArgsSource`
defaulting to `Unknown` because nothing asked, and aggregate signature
parameters left unstamped because a comment described a die that had stopped
happening.

So T1 normalizes, but **must not erase the signal**. Every node that ARRIVES
absent is recorded and reported as a frontend defect, whether or not T1 later
narrows it. Reporting it only when the node stays `Unknown` — as an earlier
draft of this section had it — hides exactly the cheapest cases: an absent node
that T1 successfully types is still a frontend rule that does not exist, and it
disappears from the record precisely because T1 did its job.

Measured today: **10 such nodes** across the 218-case corpus (2 `Call`, 1
`Ref`, 7 downstream `Phi`). That is a frontend punch list, not a T1 backlog.

**Control nodes have no type OF THEIR OWN.** `Start`, `Region`, `If`, `Loop`
define no value, so asking "what is this `If`'s type" is a category error and
answering it is a bug — an early round-trip run showed
`Start: wire=(none) reloaded=Int`, which was corruption, not under-typing. The
totality condition is over Value nodes precisely, and a checker that walks
"every node" is wrong in a way that will look like progress.

**But control nodes CARRY TYPE INFORMATION, and this is unresolved.** A branch
is a type guard: `if (defined $x)` establishes that `$x` is not `Undef` on the
then-edge and is `Undef` on the else-edge. Same for `if (ref $x eq 'ARRAY')`
and plain truthiness. That is a fact about ANOTHER node's type, conditioned on
an edge — so "control nodes carry no type" is true and beside the point.

Condition 5 (maximal narrowing) REQUIRES this: without flow-sensitivity, `$x`
inside the guard keeps its entry type and T1 leaves narrowing on the table that
the program plainly supports.

### RESOLVED: the refinement is a VALUE NODE (Pi-style)

Researched against Graal, C2, TurboFan/Turboshaft and TypeScript
(2026-08-26). The answer is not close:

| system | where refinement lives |
|---|---|
| Graal | `PiNode` — value node with a guard input |
| HotSpot C2 | `ConstraintCast` family — value node, control edge `in(0)` |
| V8 TurboFan | `TypeGuard` — a `kPure` node that nonetheless takes a control input |
| V8 Turboshaft | block-keyed side table — **and it abandoned floating nodes to do that** |
| TypeScript, Kotlin, mypy, C# | recomputed on demand over a CFG |

**The dividing line is not language or paradigm — it is whether the IR
floats.** A floating value has no position, so the only way to say "this fact
holds only here" is to make the fact BE a value whose inputs pin it. Chalk's IR
floats, so the side-table option is not available at an acceptable price.

**And this preserves "control nodes carry no stamp".** Graal's `GuardingNode`
is a **marker interface with zero methods** — the guard is not a condition
object, it is any node occupying a control position where the fact holds (a
plain `BeginNode` qualifies). In Chalk terms the Pi's guard input is the
`Proj`/`Region` for the taken branch. Control nodes INFLUENCE stamps by being
pointed at; they still carry none. Soundness falls out of ordinary dominance
with no scheduler changes.

Three design points to copy, each with its failure mode:

1. **Store the DELTA, not the result.** Graal keeps `piStamp` = "what the guard
   proves and nothing more", and computes the effective stamp as
   `piStamp ⊓ input.stamp` on demand, asserting monotonicity on strengthening.
   The node then cannot go stale when a later pass improves the input, and
   re-running inference is idempotent — which matters because Chalk builds IR
   during parse.
2. **Never fold the narrow stamp back onto the guarded input.** Graal permits
   it only under `guard == null && !hasMoreThanOneUsage()` — both conditions,
   and their conjunction amounts to "this was not actually flow-sensitive".
   Folding back asserts the fact globally; its own comment: *"the type injected
   by the PiNode is only true at this point in the control flow."*
3. **Two independent bits, not one.** C2's master split `_floating` (may this
   move?) from `_narrows_type` (removable once the input is that narrow?).
   Collapsing them has a documented failure: an array access floating above its
   range check.

Also worth knowing: Graal's `FixReadsPhase` **deletes every Pi** once reads are
pinned, then re-derives the same facts positionally. Pis exist exactly as long
as things float. If Chalk's scheduler pins before codegen, the Pis should die
there — or they become permanent clutter with no remaining job.

**On `remove(σ, Undef)` specifically:** the canonical formalism is
Tobin-Hochstadt & Felleisen's occurrence typing (POPL 2008, ICFP 2010), which
attaches a then/else proposition pair to every expression and defines exactly
this environment operation. POPL 2008 §1 names **Perl** as a motivating
language. Nullability narrowing is the base case of the machinery, not a
special case bolted on.

### The aliasing boundary — START CONSERVATIVE

Every system surveyed has a soundness hole here, and Perl's is worse than most
because its aliasing is idiomatic rather than exceptional:

- **`foreach` aliases the loop variable to each element** — `for (@a) { $_ = 1 }`
  mutates `@a`;
- **`@_` aliases the caller's arguments** — `sub f { $_[0] = 5 }` writes the
  caller's variable;
- **`\$x` escapes the location** — anything holding the reference can write
  through it;
- **`local` swaps a package variable's value dynamically** across a call.

A refinement is a claim about a NAME; the value lives at a LOCATION; Perl lets
other names reach that location. `if (defined $x) { f(); ... }` is unsound the
moment `f` can write through a path that reaches `$x`.

**What makes this tractable: SSA already answers it.** A value that stays in
value-SSA has no alias — that is what SSA means. Chalk already demotes on
escape ("taking a reference to a variable makes it address-taken; it must be
demoted from value-SSA to memory"). So:

> **THE POLICY: a refinement holds only on a value that never leaves
> value-SSA.** Anything in memory is not refined, and no analysis is required
> to know that — the demotion already happened.

This is sound, needs no new machinery, and costs only precision. Take it as the
default and do not apologise for it.

**Liberalising it is optimization work, and fertile ground.** Each of these
buys precision by discharging a proof, and each belongs in an optimizer pass
rather than in T1:

- **non-escaping locals survive calls.** Flow's two-tier model: a call
  invalidates PROPERTY refinements but not refinements on locals proven not to
  escape. Needs the escape analysis slice 4b already scopes.
- **`foreach` over a container nothing else writes.** A monomorphism/no-write
  proof over the loop body makes `$_`'s refinement survive.
- **`@_` when the callee provably does not write its arguments.** Whole-program,
  and the call graph is already being built.
- **a reference that provably never escapes its scope** can stay in value-SSA
  rather than being demoted at all — this one improves far more than
  refinement.

Note the shape: every liberalisation is "prove the alias cannot happen, then
keep the refinement". That is exactly the narrowing-ladder pattern from
`docs/architecture/ir-and-lowering.md` §5, where `%Slot` disappears once
monomorphism is proven. Same principle, different axis.

**Name the policy in the code**, not just here. Every system that wrote its
boundary down (Kotlin's stability rules, mypy's aliasing note, Flow's
`is_const_like`) fared better than the ones that discovered it in a bug report.

## Why no `Unknown` may leave

A graph that exits T1 carrying an `Unknown` is an **error**, not a
less-narrowed success. Absence normalizes to `Unknown` on entry, so this one
condition covers every Value node the graph carries.

This follows from what `Unknown` means on each side of the pass. On INPUT it is
honest: the frontend sees one compilation unit and is saying "I could not
determine this". On OUTPUT it is not, because T1 sees the whole program — call
graph, cross-unit arguments, every store into a container. If T1 cannot
determine a type, no later phase has more information to work with, so shipping
`Unknown` only defers the failure to a phase equipped to diagnose it worse.

`Unknown` at the exit is therefore an **unfinished analysis**, not an
un-narrowed type.

**`Scalar` is NOT in the same category and must not be conflated with it.**
`Scalar` is a real answer — "one value, genuinely not narrowable further here"
— and a legitimate exit type. The backend's own diagnosis already draws this
line: *"Scalar is a legitimate static answer, Unknown is an inference failure."*
So condition 5's "maximally narrowed" is a TREND for everything else and a
BINARY at this one point: `Scalar` may exit, `Unknown` may not.

Two consequences worth stating up front:

- **Guard reporting stops being optional.** "Error: Unknown at node N" is
  unactionable across a 218-case corpus. T1 has to name what it could not
  determine and what would have determined it. That was deferred as a
  follow-up; this exit condition makes it load-bearing.
- **Today this would fail broadly.** The producer emits `Unknown` heavily — 976
  of ~1800 stamps in one four-program measurement. Most should narrow once
  whole-program inference actually runs; "most" is not "all", and the residue
  is precisely the interesting set. Expect the first implementation to REPORT
  the residue rather than die on it, and to shrink it deliberately.

It also settles `%LOWERABLE_STAMP` (below): if `Unknown` cannot exit T1, it
cannot reach the backend, so the filter is guarding against a phase that no
longer produces it. That makes the filter deletable on T1's completion rather
than T2's.

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

   MEASURED, and read carefully: removing it **with nothing else changed**
   drops the gate to 136, with 78 failures naming `Unknown`. That is a fact
   about the CURRENT wiring — today's backend cannot receive an un-narrowed
   type — not a demonstration that the filter is load-bearing in principle.

   **The exit condition settles this.** If no `Unknown` may leave T1, then no
   `Unknown` reaches the backend, and the filter is guarding a case that has
   stopped occurring. It is deletable on T1's completion — not T2's, as an
   earlier draft of this document guessed.

   **The measurement is a floor, not a constraint on the design.** What remains
   structural is only this: "can the backend lower this type?" is the lowering
   phase's question, so wherever the filter ends up, it is not the loader.

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

Note which direction the dependency runs: this is a prerequisite for
`run($graph) -> $graph` being TRUE, not a prerequisite forced by today's
breakage. `_replay_classes` being one of the eleven passes is a property of the
current implementation; a T1 that does not inherit those eleven passes may
never face the question. **Resolve it because the contract needs it, not
because the failed split demanded it.**

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
   - **`Unknown` count at the exit must reach ZERO.** Absence is normalized to
     `Unknown` on entry, so this is the whole EXIT condition. Counted over
     Value nodes only; a control node carrying a stamp is its own failure, not
     a success. Until the count reaches zero the residue is REPORTED, naming
     what each node needed and why it was unavailable;
   - **arrived-absent count is reported separately, and is a FRONTEND metric.**
     Not an exit condition — T1 normalizes those nodes and may well type them —
     but every one is a frontend rule that does not exist, and the count is
     only visible here. It must be reported whether or not T1 narrows the node,
     or the easiest frontend bugs vanish from the record by being fixed
     downstream;
   - **the count of narrowed nodes** (strictly-below-input type) is the number
     that must trend up, per corpus case, tracked like the gate floor.

   That comparison needs no oracle: the input graph IS the baseline.
3. The exit condition does NOT hold today, and by a wide margin. Measured: 10
   Value nodes reach the end of the current pass sequence with no stamp at all
   (2 `Call`, 1 `Ref`, 7 downstream `Phi`) — those normalize to `Unknown` and
   join the far larger `Unknown` population the producer already ships (976 of
   ~1800 stamps in a four-program sample). Separately, `Slot` — a machine
   ENCODING — reaches the stamp field via the OOB path, which condition 2
   (lattice membership) rejects.

   **The first version therefore REPORTS rather than asserts.** An assertion
   that must be disabled to land is what `_assert_value_nodes_are_typed`
   already is.
4. The corpus gate holds at 218 as a floor, not as the definition of done.

## Prerequisites, in order

Each of these is a prerequisite for a T1 that INHERITS the current passes.
A T1 built differently may dissolve rather than satisfy them — that is a
legitimate outcome, and preferable where it applies.

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
