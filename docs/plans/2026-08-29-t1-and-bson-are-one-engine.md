# T1 and B::SoN's typing are one engine written twice

**Date:** 2026-08-29
**Status:** FINDING + proposed direction. Not yet ruled on.
**Origin:** perigrin — *"T1 and bson's typing have very similar shapes … probably
two implementations of the exact same engine, and probably we should have a
single implementation that is just duplicated between namespaces."*

## The evidence: five passes share a NAME

| chalk `IR/Analysis.pm` | perl5-son |
|---|---|
| `_propagate_computed_reprs` | `_propagate_computed_reprs` |
| `_infer_param_field_types` | `_infer_param_field_types` |
| `_infer_field_types_from_stores` | `_infer_field_types_from_stores` |
| `_stamp_field_access_reprs` | `_stamp_field_access_reprs` |
| `_stamp_method_call_reprs` | `_stamp_method_call_reprs` |
| `_seed_direct_call_arg_reprs` | `_stamp_calls_from_callees` |
| `_element_repr` | `_stamp_literal_subscripts` |
| `_join_repr` | `_stamp_merges` |
| — | **`_infer_backward`** |

Five identical names is not convergent design. It is one engine written twice.

**And the producer's is the more complete one.** `_infer_backward` has no chalk
equivalent, and it is what took wire `Unknown` 233 -> 80.

## It has already happened once, and been named

`lib/B/SoN/TypeLibrary.pm` (145 lines) is a DELIBERATE mirror of chalk's
`%BINARY_OP_SIGNATURES`, created 2026-08-29. Its header states the mechanism
that produced it:

> three partial copies of one table, none of them labelled as such

— `%OPERAND_REQUIRES` held the input half, `%SELF_TYPED_OPS` the fixed-result
cases, and a third table was about to be added. So the accidental-duplication
failure mode is documented, and the deliberate-mirror remedy is already in use
for the table. This proposal is that remedy applied to the ENGINE.

## Why a shared dependency is not available

The SoN/Chalk namespace divorce: B::SoN stands alone, and a runtime dependency
on chalk would put the producer inside the consumer. So the choice is not
"share vs duplicate" — it is **deliberate mirror vs accidental re-derivation**,
and only one of those is honest.

## What this changes about T1

T1 has been planned as something to BUILD. It is not: a working implementation
exists on the producer side. So the work is EXTRACT AND MIRROR, not author.

Consequences worth stating before anyone acts:

- **The registry question may dissolve.** Chalk's registry ruling exists so T1
  can reach more than one graph. The producer's engine already solves whatever
  it solves without one; look at how before designing chalk's.
- **`_infer_backward` is the biggest single import**, and its rule comes with
  it: *fill a hole, never preempt a source* — valid only on `PadAccess`,
  `FieldAccess`, `Parameter`. It binds chalk HARDER, since T1 can resolve
  callees the producer cannot.
- **Sizes:** chalk `Analysis.pm` 1842 lines; producer inference split across
  `B/SoN.pm` (2123) and `SoN/IR/Serialize/JSON.pm` (1334). Neither is a small
  extraction, and the shared subset is what matters, not the totals.

## RULED 2026-08-29 (perigrin): the producer's implementation IS the source

> For Chalk the source of truth is to take the Producer's implementation and
> modify it to run against a loaded graph.

So chalk does not author T1 and does not import `_infer_backward` into
`Analysis.pm`. It takes the producer's engine and adapts it. That is the
opposite direction from the one I had assumed.

**And the adaptation is smaller than the ruling's wording implies, because the
engine is ALREADY graph-based.** Measured 2026-08-29:

| pass | lines | optree references |
|---|---|---|
| `_stamp_field_reads` | 25 | 0 |
| `_stamp_reader_accessors` | 35 | 0 |
| `_stamp_calls_from_callees` | 19 | 0 |
| `_stamp_literal_subscripts` | 17 | 0 |
| `_stamp_merges` | 40 | 0 |
| `_stamp_derived` | 17 | 0 |
| `_infer_backward` | 69 | 0 (the one grep hit is the `B::SoN::TypeLibrary::` package prefix) |
| **total** | **222** | **0** |

`_infer_backward($graphs)` takes a graph set and iterates `$graph->nodes->@*`.
There is no `B::` optree access anywhere in the engine. So "modify it to run
against a loaded graph" is not a rewrite from optree-walking to graph-walking —
it is a VOCABULARY translation (`SoN::IR::Value` -> `Chalk::IR::Value`, the
stamp accessor) plus an entry point.

222 lines against chalk `Analysis.pm`'s 1842 is also the shape of the answer to
question 2 below: the ENGINE is small, and most of `Analysis.pm` is this side's
plumbing.

## What must be decided, and is NOT decided here
2. **What exactly is the engine?** The seven passes measured above (222 lines)
   are the strong candidate. What is NOT yet established is which parts of
   chalk's 1842-line `Analysis.pm` the mirror REPLACES versus which are
   genuinely chalk-side plumbing that must survive.
3. **What enforces agreement?** For `TypeLibrary` the answer is already stated:
   chalk's corpus gate runs producer output through chalk's lowering, so a
   disagreement surfaces BEHAVIOURALLY rather than silently. That is the only
   enforcement mechanism either side has, and it must cover the engine too or
   the mirror rots.

---

## CORRECTION 2026-08-29: 222 was an undercount, and the duplication is worse
## than "one engine written twice"

**The 222-line figure counts only `B/SoN.pm`.** The producer has FIVE more live
inference passes in `SoN/IR/Serialize/JSON.pm` (each with 2 references —
definition plus call, so none is dead):

| pass | lines |
|---|---|
| `_propagate_computed_reprs` | 89 |
| `_stamp_method_call_reprs` | 60 |
| `_stamp_field_access_reprs` | 51 |
| `_infer_field_types_from_stores` | 42 |
| `_infer_param_field_types` | 14 |
| **subtotal** | **256** |

So the engine is **~478 lines**, not 222. I flagged this as a risk to the
reviewer before checking it; it is real, and it roughly doubles Path A's port.

**And the location is the finding.** Those five live in the producer's
`SoN/IR/Serialize/JSON.pm`, which has its own `from_json` (`:663`) and calls
inference from inside it (`:717`). That is the SAME FUSION chalk has —
inference inside deserialization, in a file of the same name, in both repos.

This is not two implementations of one engine. It is **one architectural defect
duplicated on both sides**: the loader doing inference. Chalk's Phase 5 exists
to split that on the chalk side (`JSON.pm:707`); nothing has proposed splitting
it on the producer side, and the ruling to adopt the producer's implementation
would import the fusion along with the engine unless the port separates them.

Which sharpens the open question about what "the engine" is: the passes are
identifiable, but on BOTH sides they are entangled with a loader, and the port
has to disentangle rather than copy.

---

## Adversarial review, 2026-08-29: ruling UPHELD, scoped by three amendments

A Fable reviewer was asked to build the strongest case AGAINST the ruling and
endorse it only if it survived. It survives.

**The decisive evidence, which neither the ruling nor my analysis had:** diff
the five shared passes. Verified independently by me:

| pass | diff lines, chalk vs producer |
|---|---|
| `_infer_param_field_types` | **0 — byte-identical** |
| `_infer_field_types_from_stores` | **0 — byte-identical** |
| `_stamp_field_access_reprs` | 45 |
| `_propagate_computed_reprs` | 84 |
| `_stamp_method_call_reprs` | 106 |

One engine written twice, **already mid-divergence**. That is what settles the
direction: Path B (keep chalk's, import what it lacks) does not avoid the drift,
it INSTITUTIONALISES it. A declared source of truth is the only thing that stops
two copies drifting further.

### The three amendments, all binding

1. **The ruling is scoped to the STAMPING/INFERENCE subset — it is NOT
   "replace `Analysis.pm`".** My earlier wording ("`Analysis.pm`'s inference is
   replaced by the port") overstates what is replaceable. `Analysis.pm` also
   does loader LINKING and REWRITING with no producer equivalent:
   `_resolve_direct_calls`, `_replay_classes` (MOP sealing),
   `_attach_call_targets`, `_insert_str_coercions`,
   `_narrow_unknown_coercions`, `_assert_value_nodes_are_typed`. Those stay
   chalk's. Discarding them would throw away working, gate-load-bearing code.

2. **Entry-point adaptation is mandatory, not cosmetic.** `_infer_backward($graphs)`
   and its siblings take a graph SET; spec §2 forbids `Map<String, Graph>` in a
   public signature. And note chalk's `_stamp_method_call_reprs` diverged by
   growing a `$mop` parameter — **chalk's drift is ARCHITECTURAL** (MOP edges),
   so converging those three passes is RECONCILIATION, not copy-paste.

3. **Land additively, converge incrementally.** Import the 7-pass engine first
   (pure addition — chalk has no `_infer_backward` at all), then converge the
   three diverged passes ONE AT A TIME against the gate. Blast radius per step
   is one pass, not one 1842-line file.

### Explicitly NOT settled

**Which direction each of the three diverged passes should converge.** The
reviewer flagged, correctly, that "producer wins" must not be assumed per-pass —
chalk's `$mop` parameter is a chalk-side improvement, not drift to be undone.
Settle per pass, during convergence, on evidence.

The reviewer also did not verify the `Unknown 233 -> 80` figure and ran no
tests; both are stated as reasoned rather than measured.

---

## The IR-op alias: tried, MEASURED, reverted (2026-08-29)

perigrin, on `%IR_OP_SOURCE_NAME`: *"This feels like it's duplicating the
TypeLibrary again, especially the operator signatures … add an alias to the
signatures rather than duplicating the entire dictionary?"*

The diagnosis is right. `%BINARY_OP_SIGNATURES` is keyed by SOURCE OPERATOR
(`'+'`, `'eq'`), which suits its two parser-side callers, while every
IR-pipeline caller holds a node's `operation` (`Add`, `StrEq`). The bridge
between them is a SECOND NAMING SYSTEM for one set of facts, and it drifts
silently: a missing key returns `undef`, and callers read `undef` as "no
requirement" rather than "not in the map". Measured: `Add`, `Subtract` and
`Multiply` were absent, so `$x + 1` imposed no constraint at all — the
motivating case for backward inference, quietly inert.

The alias approach is also right in structure: the table already assigns SHARED
HASHREFS (`$num_num_num` is one object under six keys), so adding IR names as
further keys onto the same refs is genuinely not a copy, and the two names
cannot disagree.

**It was implemented and it REGRESSED THE GATE 207 -> 169, with 102 behavioural
mismatches** (`lli ''` against `perl '30'`, `'-10'`, `'6'` …). Reverted whole
rather than patched.

**Why, and it is not a flaw in the alias idea.** `operand_repr_for_ir_op` has
TWO consumers with different needs:

- `Analysis.pm::_required_operand_repr` -> **`_insert_str_coercions`**, which
  MATERIALISES a Coerce node at every position with an answer;
- `Transform/BackwardInference.pm`, which only READS the requirement to narrow
  a type.

Today `%_NODE_OPERAND_REPR` holds exactly one entry (`Print => 'Str'`), so the
coercion pass only ever touches Print operands. Teaching the lookup about
arithmetic made it insert coercions on every Add/Subtract/Multiply operand,
which is what produced empty output.

**So the requirement table is fine; the CONSUMER is overloaded.** "What does
this position require?" is one question, and "should a Coerce be materialised
here?" is another — the coercion pass has been getting away with conflating
them only because its table had a single entry.

**CORRECTED, after perigrin asked whether `%_NODE_OPERAND_REPR` is itself a
copy.** It is not, and its comment anticipates the question: *"This hash exists
for genuine node-level contracts only; an entry that merely restates a source
signature belongs in TypeLibrary instead."* Its one member is a case where the
node and the source genuinely DISAGREE — the IR `Print` node lowers one
representation so every argument position is `Str`, while the source builtin
`print` is variadic over `List` because perl flattens into it. Two claims about
two different things, which is also why `%IR_OP_SOURCE_NAME` lists `Print` as
deliberately absent. It is an override table for real conflicts, correctly
scoped, with one member.

That sharpens the diagnosis rather than dissolving it. **The pass is named
`_insert_str_coercions`** — it inserts STRING coercions, and `Print => 'Str'`
being its only requirement is the scope, not an incompleteness. Making `Add`
answer `Num` turned a string-coercion pass into a general one.

So the fix is NOT "give the coercion pass its own table"; it effectively has
one. The mismatch is that it reaches through `_required_operand_repr` into the
GENERAL signature lookup at all, when its own contract is narrower than that
lookup's answers. Either it consults only node-level contracts, or it is
renamed and re-scoped to be the general coercion pass it would then be — and
that second option is a real design change, not a repair.

**What this makes the next step.** Separate the two questions before aliasing:
give `_insert_str_coercions` its own explicit table (it effectively has one
already, `%_NODE_OPERAND_REPR`) and let the type-requirement lookup answer
freely for everyone else. Then the alias lands without touching coercion
behaviour. That is a change to `Analysis.pm`'s coercion pass, which amendment 1
puts on chalk's side of the line, so it is chalk's to make and not a
convergence question.

---

## Should coercions be inserted where `meet` is `None`? — MEASURED: no, not alone

perigrin asked whether the coercion rule should be "insert where `meet()` is
`None`", which is bson's formulation, recorded earlier: *"`meet` returning
`None` is a SITE, not a verdict: no single type satisfies both ends, so a
coercion node goes there."*

It is principled where the current pass is ad hoc — but measured against the
lattice it does NOT fire for the cases that matter:

| operand | required | repr-equality (today) | `meet = None` |
|---|---|---|---|
| `Int` | `Str` | COERCE | **no** |
| `Boolean` | `Str` | COERCE | **no** |
| `Num` | `Str` | COERCE | **no** |
| `Undef` | `Str` | COERCE | COERCE |
| `Array` | `Str` | COERCE | COERCE |

`meet(Int, Str) = Int`, not `None`, because `Int <: Num <: Str` — an `Int`
GENUINELY satisfies a `Str` requirement on the type axis. So a meet-based rule
inserts nothing for `print 42`, and `_lower_print` GAPs on an Int-repr operand
(verified: `Context.pm:8195` handles only `repr eq 'Str'`).

**The two rules answer different questions, and both are needed:**

- **`meet = None`** — *no value can satisfy both ends*. A TYPE error, and the
  right test for whether a conversion is SEMANTICALLY required. This is what
  catches `Array` into a scalar position.
- **repr inequality** — *these have different machine layouts*. An ENCODING
  question, and the right test for whether a stringify or `sitofp` must be
  EMITTED. This is what catches `Int` into a `Str` position, which is sound by
  subtyping and still needs `snprintf`.

So the axis distinction lands here too, and it says the coercion pass has two
jobs that were never separated: refusing impossible pairs (T1's question) and
materialising conversions between encodings (T2's). Today's pass does the
second with a hand-maintained requirement table; the `meet` rule would do the
first properly.

**RULED (perigrin, 2026-08-29): representations are something we deal with at
T2.** Which settles where this pass belongs, and retracts my proposed fix.

`_insert_str_coercions` mints `Coerce` nodes carrying **`from_repr` /
`to_repr`** — representation vocabulary, explicitly — and it runs at
`Analysis.pm:295`, inside the LOADER's pass sequence. It is a T2 pass living in
T1's file, materialising encoding conversions during deserialization.

I had proposed NARROWING it to node-level contracts so the alias could land.
That treats a PLACEMENT error as a SCOPING error: it keeps a T2 pass in T1 and
merely makes it fire less often. The same mistake as `%LOWERABLE_STAMP`
answering the backend's admission question inside the loader, which this
session spent its length unwinding — and I nearly repeated it while writing up
why it was wrong.

**The corrected shape:**

| question | rule | home |
|---|---|---|
| can any value satisfy both ends? | `meet = None` | **T1** — report an impossible pair; do NOT invent a conversion |
| do these have different machine layouts? | repr inequality | **T2** — emit the stringify / `sitofp` |

So the coercion pass does not get narrowed; it gets MOVED, and split on the way
— its refusal half is T1's checker, its materialisation half is T2's.

**Consequence for the alias thread:** the alias is no longer blocked by the
coercion pass's scope, because once the pass leaves `Analysis.pm` the general
requirement lookup has only inference consumers. The blocker was never the
table.

---

## The cross-session collision, 2026-08-29 — resolved, and what it cost

The bson session committed twice to chalk's `phase5-capstone` (`37ccfcb2`,
`d925b589`; 8 files, +374/-173) while I was editing `Analysis.pm`. Both sides
contributed:

- **Mine:** I left an in-progress `lib/` edit uncommitted in a tree another
  session was committing from. **Uncommitted is not private.**
- **Theirs:** `git add lib/Chalk/IR/Analysis.pm` — staging a file BY NAME and
  assuming its contents were their own work.

The result was a broken HEAD: their commit captured my call sites into
`Chalk::IR::Transform::Coercion`, a module I deleted when I reverted the
experiment. Repaired in `bdb74505` by recovering the four passes from
`bb3671bc`.

**Measurement casualty:** my gate reading of **146** was my half-finished move
plus their two commits plus the breakage. Withdrawn — it measured nothing.
Re-run at the repaired HEAD: **207/207/208/215, 0 behavioural mismatches**, so
the 207 baseline was correct all along.

**DECISION: their two commits are KEPT, not reverted.** They offered either.
Reverting would discard a sound change to protect an attribution, and `bdb74505`
already builds on them. All four tests they added pass; the gate holds at 207.
I own them going forward.

**Pin correction:** the producer has moved to `8c15e32` (Subscript is never
`Unknown`), so today's 207 is measured against THAT, not the `337ceab` I had
pinned. The pin is updated rather than the reading.

### The producer-side finding, which is the part worth keeping

`8c15e32` makes a `Subscript` never `Unknown`: `$a[...]` and `$h{...}` read ONE
slot, and one slot of any Perl aggregate holds a scalar (a slice is a different
node kind — `Slice :isa(Aggregate)` vs `Subscript :isa(Access)` — and nothing
builds one yet). So a read nothing could narrow now ships `Scalar`.

perigrin's reasoning, recorded because it generalises: **an AoT compiler has no
runtime to defer to, so an `Unknown` is not a missing annotation — it is a hole
in the emitted program.** `Scalar` lowers to `%Slot`, which every prologue
already emits. Ranking: **narrow type > `%Slot` > nothing.** An unconverged type
costs speed; a missing representation costs the program.

**What it exposes on this side, unfixed:**

1. `_stamp_method_call_reprs` compares wire against graph-derived with `ne`.
   `Scalar` on the wire against `Int` from the graph is NOT a disagreement —
   `Int <: Scalar`, the producer said "a scalar", the loader proved "an Int",
   both true. Corpus `classes.md` #17 is the case; unfixed it takes loadable
   cases 231 -> 230.
2. The same `ne` blindness is in `_is_narrowed` (`Analysis.pm:460`), which
   terminates the fixpoint on the FIRST stamp rather than on the absence of
   narrowing.
3. `t/bootstrap/ir/method-return-type-from-wire.t`'s "genuine DISAGREEMENT"
   case is wire `Str` vs graph `Int` — a SUPERTYPE, not a contradiction.
   perigrin ruled the test premise stale, not the lattice. `Code` vs `Array`
   would be a real one.

Five pre-existing failures bson hit and did not touch (`mop/sub-replay.t`,
`ir/element-repr-joins-stores.t`, `ir/llvm-class-sub-define.t`,
`ir/son-aggregate-repr.t`, `ir/stamp-alias-preconditions.t`) — it verified them
by reverting the producer with chalk held constant, after misreporting once and
retracting on a guess. **Re-check rather than inherit.**

---

## CORRECTION, 2026-08-30: the evidence above compares chalk against chalk

**Found by the bson session (perl5-son-e6), verified independently here. The
RULING is untouched; its stated evidence is not.**

This document's central argument — "five passes share a NAME … that is one
engine written twice" (§ above) — compares `Chalk::IR::Analysis` against
`SoN::IR::Serialize::JSON`. That second module is **a vendored copy of chalk's
own loader**, kept in the producer repo on purpose. So the five matching names
are chalk on both sides of the comparison, and the byte-identical diffs cited
for `_infer_param_field_types` and `_infer_field_types_from_stores` (0 lines
different) are the EXPECTED result for a vendored copy, not a finding.

Provenance, from the producer's own history: `d838da6` "rename: divorce
vendored Chalk::IR:: namespace to SoN::IR::" and `82e97cc` "trim: delete 13
never-loaded vendored Chalk::IR modules" — which deleted 13 sibling vendored
modules and KEPT this one so producer output can be round-tripped through the
real cross-repo boundary in tests.

### Measured here, 2026-08-30

| pass-name set | size | overlap with `Chalk::IR::Analysis` |
|---|---|---|
| live producer engine | — | **0 — disjoint** |
| vendored chalk loader (`SoN::IR::Serialize::JSON`) | 19 | **12 shared names** |

The live engine is in **`lib/B/SoN.pm` itself** — not in either serializer.
`B/SoN.pm:13` loads `SoN::Serialize::JSON` (440 lines, zero inference passes);
`SoN::IR::Serialize::JSON` is absent from `%INC` at produce time. Its twelve
passes (`_floor_subscripts`, `_infer_backward`, `_stamp_calls_from_callees`,
`_rederive_method_return_types`, …) share **no name** with chalk's.

### What this does and does not change

- **The ruling stands on its own merits.** The producer's implementation being
  the source of truth does not depend on this evidence, and `_infer_backward`
  genuinely has no chalk equivalent — the port that shipped as
  `Chalk::IR::Transform::BackwardInference` is real work against a real gap.
- **"Already mid-divergence" is withdrawn.** Two copies of one file diverging
  slightly is vendored-copy drift, not two implementations of one engine
  growing apart.
- **The ~478-line estimate is withdrawn.** It measures chalk-plus-vendored-
  chalk. The live engine is a different, larger, differently-shaped body of
  code in `B/SoN.pm`, and porting from it is not the same task this document
  scoped.
- **What survives is the QUESTION, not the answer:** two repos infer types over
  the same graphs with disjoint pass sets. Whether that is duplication worth
  merging is now genuinely open, and the honest comparison — chalk's
  `Analysis.pm` against `B/SoN.pm`'s twelve passes — has not been done.

### DO NOT delete the vendored loader

`t/from-json-classes-branch.t` in the producer is a regression test against
exactly that move: a previous trim gutted `from_json`'s classes branch believing
it dead. It was not — the branch ran four inference passes, discarded the
results, then died, and no test caught it. Read that test's header before
touching `SoN::IR::Serialize::JSON`.

### The producer's shape, stated correctly (2026-08-30)

"The produce path has zero inference passes" is only half a result, and the
sharper half changes what a port is porting. The passes are not in EITHER
serializer: they are in `lib/B/SoN.pm` itself, and `B/SoN.pm:13` loads a dumb
440-line `SoN::Serialize::JSON` to emit.

So the producer's architecture is **inference in the compiler FRONT END,
emitted by a dumb serializer** — which is what a front end should look like.
Chalk's is **inference inside a LOADER** (`Analysis.pm`, run from `from_json`).
Those are genuinely different shapes, not one engine written twice, and the
difference is architectural rather than incidental.

**Nobody has yet compared `Chalk::IR::Analysis` against `B/SoN.pm`'s twelve
passes.** Every comparison to date — this document's included — was against the
vendored copy. Whatever duplication exists between the two REAL engines is
unmeasured, and it may be small: `_infer_backward` has no chalk equivalent, and
the producer's twelve are mostly floors and re-derivations shaped by walking an
optree-derived graph. If that comparison is done, it should be done ONCE, by
whichever side is doing the port.

### Two rules a port will hit (measured by the bson session, 2026-08-30)

**1. The weakest answer must speak LAST.** Every pass in the chain guards on
only-fill-`Unknown`, so a floor that runs EARLY consumes the hole the precise
passes needed. A `:param`-field floor written at extraction time made
`field $n :param; method inc { $n + 1 }` come out `Scalar` where `Num` is
provable — each later pass saw a filled slot and skipped the node. Three tests
red. Moved after the fixpoint, correct. The rule is already written twice in
`B/SoN.pm`; **a port that lifts passes without lifting their ORDER reproduces
this, and the failure is silent precision loss, not a crash.**

**2. Coverage alone ranks the wrong implementation first.** The broken
extraction-time floor closed **14** wire `Unknown`s; the correct one closes
**10**. A port measured by "how many holes did it fill" would have picked the
version that fills them with worse answers. Pair any coverage number with a
precision check.

### Counting `Unknown` on the wire: count by ROLE, not by grep

`"Unknown"` appears on the wire in at least three distinct roles — a node
stamp, a return-type record, and a `Coerce`'s `from_repr` (written at
`FromOptree.pm:116` as `$stamp->type`, at BUILD time, before the inference
chain runs). Summing them produces a number that means nothing; that error
put a wrong 124 into a producer commit message before it was caught.

The producer session owns a scripted, re-runnable census. **Do not
reimplement it here** — ask for a number rather than building a second
counter, which is the duplication this document exists to think about.

### RETRACTED, same day: the DO-NOT-DELETE above, and what replaced it

**The vendored loader is deleted** (perl5-son `bcdbb4e`). The "DO NOT delete
the vendored loader" section above is withdrawn — I recorded it on the bson
session's reasoning, and perigrin pushed back on that reasoning directly:
*"1300 lines of stale library code for a test? Why not rewrite the test?"*

The argument for keeping it was that `t/from-json-classes-branch.t` covered a
real regression. Measured, it did not cover what it claimed: the three values
that test credited chalk's loader with DERIVING — `field $n = 5` → `Int`,
`Counter::val` → `FieldAccess Int`, `Counter::plus` → `Add Int` — are all
emitted by the producer itself. The test verified that a consumer could
reconstruct information **already on the wire**.

Both tests moved to the wire rather than being dropped:
`t/wire-classes-section-typed.t` asserts those three values on producer output
(the regression restated producer-side: "a classes section reaches the wire
untyped"), and the forward-reference test now scans EVERY node for a forward
`control_in` (measured: 0) rather than confirming one round trip survived —
strictly stronger, and needing no loader, since a forward reference is a
property of the JSON.

Net −1330 lines; wire output byte-identical in every role.

**Consequence for this document.** The producer repo now carries NO loader, so
the seven passes this document inventoried for "the producer's side" are gone
from it entirely — they were never the producer's. **The producer's pass
inventory is exactly the twelve in `B/SoN.pm`**, and the comparison nobody has
done is the only comparison left.

**Round-trip coverage of producer output through chalk's loader belongs HERE**,
against a pinned producer JSON fixture — `t/bootstrap/ir-node-unify-roundtrip.t`
is where that lives.

---

## What the two engines actually are (perigrin, 2026-08-30)

The framing this whole document was reaching for, and did not have:

> The inference exists on *this* front end (B::SoN). It doesn't yet exist on the
> Chalk parser front end … and it may be that `Analysis.pm` is the one for the
> Chalk parser.

**Measured here:**

- `Chalk::IR::Analysis->run` has **exactly one caller**: `Serialize/JSON.pm:721`,
  inside `from_json`. It runs only on the B::SoN path.
- The Chalk parser front end **stamps nothing** — no `set_stamp` or
  `set_representation` anywhere under `lib/Chalk/Grammar/` or
  `lib/Chalk/Bootstrap/`. (`TypeLibrary.pm` matches a grep only because it
  DEFINES the lattice.)

So there is no duplication to merge. **B::SoN has a front end with inference;
the Chalk parser has a front end with none.** `Analysis.pm` is the only
inference engine chalk owns, currently mounted on the loader because that is
the only place it has a typed graph to run on.

This retires the port question as posed. Nothing needs porting FROM B::SoN — it
already has its inference, correctly placed in its front end. The work is
moving `Analysis.pm` OFF `from_json` and onto the Chalk parser's own IR
emission, where it becomes the front-end inference that side lacks.

**Two questions that decide whether this is a move or a wait:**

1. Does the Chalk parser emit IR to run inference over yet, or would
   `Analysis.pm` have nothing to analyse there today?
2. Does `Analysis.pm` keep running on the B::SoN path after the move? If yes it
   is a COPY, not a move, and we are back to two engines. If no, B::SoN graphs
   arrive typed by their own front end and chalk trusts them — which is where
   the "producer is the source of truth" ruling finally becomes load-bearing
   rather than aspirational.

### Both questions answered (2026-08-30) — it is a WAIT, and the move is not the shape

**(1) Does the Chalk parser emit IR to run inference over? Measured: barely.**
`lib/Chalk/Grammar/BNF/Actions.pm` — the parser's semantic layer — constructs
**three `Constant` nodes and nothing else**. No `Add`, `Call`, `FieldAccess`, or
control flow, and zero `set_stamp` / `set_representation`. `Analysis.pm` would
have essentially nothing to analyse there today.

So moving it is a WAIT, gated on the Chalk parser emitting real IR. The
Phase-5 capstone work (`docs/plans/`, parse-perl roadmap Phase 6) is what
unblocks it; nothing here should be restructured in anticipation.

**(2) Does `Analysis.pm` keep running on the JSON path? YES — and the reason
retires the "move" framing entirely (perigrin, 2026-08-30):**

> Yes it does, but because we don't know that the graph coming in *is* from
> B::SoN … we're just handed JSON.

This corrects the premise above. Chalk is not handed *B::SoN's* graphs; it is
handed **JSON of unknown provenance**. "The producer is the source of truth" is
a statement about ONE producer chalk happens to consume, not a property of the
input format. A loader that assumed its input was typed because B::SoN types its
output would be trusting a coincidence of who called it.

So `Analysis.pm` is not a pass that lives in the wrong place and should be
relocated. It is **the loader's defensive inference over untrusted input**, and
it must stay. When the Chalk parser gains a front end, that front end needs
inference too — and whether it SHARES this code or gets its own is the open
question, but it is not served by moving anything off the loader.

**What this means for the two-engine question:** there may end up being three
positions, not two — B::SoN's front end, the Chalk parser's future front end,
and the loader's defensive pass over arbitrary JSON. Only the last exists in
chalk today. The "one engine written twice" framing was wrong in both
directions: not one engine duplicated, and not two engines either.

### The dependency runs the other way (perigrin, 2026-08-30)

The entry above called the parser's three-`Constant` output a WAIT — as though
the parser were simply unfinished and `Analysis.pm` had to wait on it. That has
the causality backwards:

> The parser is unfinished because we didn't have a complete IR.

**Measured:**

| | last changed |
|---|---|
| `lib/Chalk/Grammar/BNF/Actions.pm` (parser semantic layer) | **2026-05-21** |
| `lib/Chalk/IR/Node/` (88 node types) | **2026-08-22** |

The parser stopped in May emitting three `Constant` nodes because that was
close to all the IR could then express. `Call`, `Phi`, `Coerce`, `Parameter`,
`If`, `Loop`, `TryCatch`, `Region`, `Unwind` and most of the 88 landed AFTER it
stopped, and nobody went back to the parser.

So the parser is not waiting on anything. **The gate it stalled against has
been open since August**, and the T1/T2 work is the last of what was missing.
"Analysis.pm waits for the parser" inverts a dependency that has already
resolved — the correct statement is that the parser has three months of
unclaimed IR available to it, and re-opening `Actions.pm` is now unblocked
work rather than blocked work.

This does not change the ruling in the entry above: `Analysis.pm` stays on the
loader, because the loader is handed JSON of unknown provenance and must defend
itself. What changes is the OTHER half — the Chalk parser's front end is
buildable now, and when it exists it needs its own inference, which is where the
genuine "shared or separate" question finally lands.

## `meet() == None` as a coercion trigger: answered NO (2026-08-30)

perigrin asked whether coercions should be inserted where `meet()` is `None`.
The bson session scoped it on the producer and the answer is negative; verified
here against chalk's own `TypeLibrary::meet_types`:

    meet(Int, Str)    = Int      <- non-bottom. The Int ALREADY satisfies a Str
                                    requirement on the TYPE axis.
    meet(Num, Str)    = Num
    meet(Scalar, Str) = Str
    meet(Array, Str)  = None     <- bottom, and NOT a coercion site

**`meet == None` fires on nothing we want to coerce.** Meet is bottom exactly
when two types are INCOMPARABLE, and the cases that need a coercion are the ones
where meet is non-bottom — an Int flowing into a Str position. So the trigger is
inverted: it is silent on all 234 real Coerce nodes and fires only where the
types cannot be reconciled at all.

The producer measured 14 `None` sites over the corpus, **all** `meet(Array, Str)`
on a `Length` node — an array count checked against a signature written for
strings. That was a NODE VOCABULARY defect, not a coercion site: one node served
`length($s)` (perl's length op, characters in a string) and `scalar(@a)` (no
perl op at all, a synthesised count). Splitting `Count` out of `Length`
(producer `93a2d12`) takes the same simulation to **zero**.

**Chalk's `_insert_str_coercions` already does the right thing** and this is why
it survives the finding: it asks `_required_operand_repr($op, $i)` — a DIRECTED,
per-position question, "what does this position require" — never a symmetric
meet. Two independent literature results (Swamy/Hicks/Bierman ICFP 2009) agree
the trigger must be a directed judgment (is there a coercion path from t to t'),
and add that Perl's Int/Num/Str convert in BOTH directions, so the coercion graph
is cyclic and NAC_pi fails: unconditional insertion is not strongly unambiguous
for this lattice, and because Perl coercions warn and are lossy they are
EFFECTFUL, ruling out the usual confluence-based coherence argument.

### Node roster divergence: 88 (chalk) vs 89 (producer)

`Count` is new on the wire wherever `Length` previously appeared over an
aggregate; `Count` carries `operands => ['List']` and the same `Int` stamp
`Length` carried, so wire stamps are byte-identical across the split. Chalk's
lowering will see `"op": "Count"` where it saw `"op": "Length"` over an array or
hash. **Not yet taken here.** When it is: `Count` wants the arm `Length(Array)`
had, and `Length`'s arm can then stop handling aggregates. `ir-value-split.t`
pins the 88/89 divergence explicitly so it stays a red test rather than drift.

### THE POSITIVE HALF, and a correction to the entry above (2026-08-30)

The entry above records only the negative result and then over-reads it. Both
are fixed here. Attribution: **[PERIGRIN]** his ruling, **[FOUND]** measured.

**THE RULE [PERIGRIN]:**

    coerce when  meet(from, to) != from
    the node is  Coerce[from -> to]

**The meet is ONLY THE PREDICATE. The target is ALWAYS `to`** — the position's
requirement, never the meet. Read it as: *does the source already satisfy the
target?* If the meet IS the source, nothing changes and no node is built.

That answers the objection that "every Int reaching a Str position would need a
node": `meet(Int, Str) = Int = from`, so no node. Verified on chalk's lattice:

    Int    -> Str    meet=Int    no node
    Num    -> Str    meet=Num    no node
    Int    -> Num    meet=Int    no node
    Str    -> Num    meet=Num    COERCE[Str -> Num]
    Scalar -> Num    meet=Num    COERCE[Scalar -> Num]
    Scalar -> Str    meet=Str    COERCE[Scalar -> Str]
    Num    -> Int    meet=Int    COERCE[Num -> Int]

**It is DIRECTED even though meet is symmetric**, because it compares the result
against ONE side. Same pair, opposite answers:

    meet(Str, Num) = Num != Str  -> coerce
    meet(Num, Str) = Num == Num  -> do not

One direction of each pair fires, so the relation is **acyclic**.

**CORRECTION: the NAC_pi / cyclic-ambiguity objection recorded above does NOT
apply to this rule.** It was raised against `==None` as a trigger and does not
survive the correction. The entry above should be read as describing the
REJECTED rule only.

**Why `==None` was wrong, precisely:** it is the narrower case of two
INCOMPARABLE types, so it misses every NARROWING. `Str -> Num` and
`Scalar -> Str` both need real conversions and neither meets to `None`.
**[FOUND]** over the 240-block corpus: `==None` finds **0** sites; `!= from`
finds **28** (Scalar→Num 22, Str→Num 6, across Add/NumEq/Multiply/Subtract/
NumLt/NumNe).

**WHERE COERCE BELONGS [PERIGRIN]:** it is a **T1 node** and stays one; the
producer keeps emitting it "where it makes sense *at the Chalk level*". The
error was "a previous design flaw which lead us to believe it should coerce at
the T1 level for T2 issues." Separately and earlier: **Coerce is Type → Type,
nothing to do with representations** — the `_repr` suffix on its fields is the
bad design being fixed. A rename to `from_type`/`to_type` follows but is a
WIRE-CONTRACT change and is **NOT scheduled**.

**THE PRODUCER SHOULD EMIT Coerce — RESOLVED [PERIGRIN].** The "maybe it should
emit none" note is stale; drop it. But the corollary is sharp. **[FOUND]**, all
234 Coerce nodes the producer emits today, classified:

| | count | |
|---|---:|---|
| source already satisfies target (`meet == from`) | 154 | legacy — T2 work done at T1 |
| a real Chalk-level TYPE change | **0** | |
| untyped source (`from = Unknown`) | 80 | |

**Zero are type conversions**, by construction: FromOptree hardcodes only
`to_repr => 'Str'` and `'Num'`, and every source reaching those already
satisfies them. [PERIGRIN] calls the 234 "a legacy artifact that need to be
fixed." The inverse also held: `my $h = "hello"; $h + 1` got NO Coerce and its
Add was stamped `Str` — wrong, not merely imprecise, since perl returns 1.

**MY OVER-READING, RETRACTED.** The entry above says chalk's
`_insert_str_coercions` "already does the right thing" because it asks a
directed per-position question. Being directed is necessary and NOT sufficient:
what is unsettled is whether that pass asks a **repr** question in a position
that wants a **type** question. `_required_operand_repr` is named for the repr
axis. Given [PERIGRIN]'s ruling that Coerce is Type → Type, that naming is the
same one-field-two-axes shape as `_is_narrowed` and `%LOWERABLE_STAMP`. **Not
fixed here** — chalk is red at 205 against a floor of 215 with the gap
unbisected, and a coercion change landing in an unreadable measurement is how
the 207→169 revert happened.

**ORDERING [FOUND].** The 80 `Unknown`-source nodes exist only because insertion
happens at BUILD time, before inference. A rule reading the operand's *settled*
type structurally cannot produce them — it forces insertion to a pass AFTER the
fixpoint. Same lesson as the `:param` floor: the weakest answer speaks last, and
**a question you cannot answer yet must not be asked yet.**

## The producer→consumer coercion handoff (2026-08-30, both sessions)

The producer's 234 Coerce nodes are legacy T2-work-at-T1 ([PERIGRIN]: "a legacy
artifact that need to be fixed"). Removing them means chalk must insert where
the producer stops. Measured from both sides:

**Chalk's pass is DORMANT, not redundant.** `_insert_str_coercions` inserts
**zero** today — because the producer already inserted, so the operand arrives
already `Str` and the pass correctly declines. The machinery exists and has
never been exercised on a raw operand.

**Its predicate is NOT a meet** — four decline paths, none a lattice operation:

    next unless defined $repr;                    # the producer's own refusal
    next if $repr eq $want;                       # STRING EQUALITY
    next if $in->isa('...::Node::Coerce');
    next if accepts_operand_repr($op, $repr);     # position accepts a SET
    next unless _coercion_exists($repr, $want);   # is this PAIR defined?

Deliberately a defined-conversion-pair question, not a subtyping one: requiring
`is_subtype` un-lowered six cases whose Boolean/Slot operands print fine, and
exempting Str wholesale un-lowered eight more.

**Coverage of the producer's nine insertion positions (238 edges):**

| site | edges | chalk covers | uncovered |
|---|---:|---:|---|
| StrEq pos0 | 5 | **5** | **0** — safe with no prerequisite |
| Concat pos1 | 28 | 21 | 7 (Scalar) |
| Print pos0 | 193 | 171 | 22 (Scalar 16, Unknown 6) |
| Divide/Add | 5 | **0** | chalk declares NO requirement for these ops |

**StrEq is the first site**, agreed both sides: the only one where both
declarations already line up. Divide/Add are the worst first choice — chalk has
no operand requirement for them, so deleting there reproduces the
integer-division miscompile (`7/2`) rather than testing the handoff.

**Two symmetric prerequisites, neither urgent, both [OPEN] with perigrin:**
`Print` has no operand requirement in the producer's TypeLibrary (197 edges);
`Divide`/`Add` have none in chalk's (5 edges).

### `Scalar` has NO defined conversion, and the code already says so

Measured here — `Scalar` is the only source type with **zero** outgoing pairs:

    Scalar -> Str/Num/Int/Boolean   ALL undefined
    Int/Num/Boolean/Undef -> Str    all DEFINED

And `Context.pm:2193` refuses it explicitly:

    die "Coerce involving Scalar reached LLVM backend — cannot lower runtime-free."

**[FOUND, bson] the Scalar operands are a DELIBERATE FLOOR, not an inference
gap** — `:param` fields and Call results floored at `Scalar` because a `:param`
field genuinely admits any scalar and that is the honest T1 answer. So the
question is not "fix the inference"; that option does not exist. It is:

> **Does the target have a way to stringify a value known only to be
> scalar-ish?** A T2 capability question about lowering — not a question about
> whether T1 tried hard enough.

Either the pair exists in the target or such a value cannot be printed.
**[OPEN — perigrin's ruling], blocks Concat and Print deletion.**

### Two corrections worth keeping

**The `Unknown → Str` population is 6, not 54.** [FOUND, bson] Of the Print
arguments whose Coerce has `from_repr = Unknown`, only **6** have an operand
still untyped after inference; **48** carry real answers (Call[Int] 8,
Call[Scalar] 9, Subscript[Int] 5, Add[Num] 3, …). So it is mostly the producer
ASKING TOO EARLY, not refusing to guess — the same build-time-before-inference
root cause as everything else today. **Do not build coverage for 54 Unknown
operands; build it for 6.** Chalk's decline is right for exactly those 6.

**"23 Scalar operands" and "0 Scalar coercions" are both correct.** They count
different populations: chalk's 23 is operands that would arrive RAW after
deletion; the producer's 0 is coercions whose `from_repr` IS `Scalar` (all 18
Scalar-sourced nodes are `Scalar → Num`, created by the `:param` floor feeding
arithmetic). Not a contradiction.

### Sequencing (agreed)

    0. chalk's bisect -- gate readable            <- BLOCKING EVERYTHING
    1. DONE -- chalk's predicate verified, it is not a meet
    2. StrEq deletion, both sides pinned          <- safe, no prerequisite
    3. the Scalar ruling (above)                  <- blocks 4
    4. Concat, then Print (after the producer's TypeLibrary prerequisite)
    5. Divide/Add last, after chalk declares their Num requirement

## T2 DIRECTION: `%Slot` should carry its own type tag (perigrin, 2026-08-30)

> "%Slot I think needs to embed its type via an enum or something"

This is the answer to the question the corrected `Coerce[Scalar -> …]` die
leaves open, and it settles it in the direction that keeps chalk runtime-free.

**The problem, restated.** `%Slot = type { i1, i64 }` — a defined bit and 64
payload bits **whose interpretation is not recorded anywhere in the cell**. So
`Coerce[Scalar -> Str]` cannot be emitted: stringifying means choosing whether
those bits are an integer, a double, or a pointer to a string, and the value
does not say. Two ways out: ask a runtime at every use, or **make the value
carry the answer**.

**The direction: a third field, a type tag.**

    %Slot = type { i1, i64 }        ->  { i1 defined, i32 tag, i64 payload }

`Coerce[Scalar -> Str]` then lowers as a switch on the tag into the arms that
already exist — `Int -> Str`, `Num -> Str`, `Boolean -> Str` are all defined
pairs with working lowerings today. **Nothing new needs inventing; the dispatch
just needs an input.** Same for `Scalar -> Num`, which is 18 of the producer's
current Scalar-sourced coercions.

**Why this is the right shape rather than a runtime call:**

- It keeps the RF (runtime-free) property. A tag switch is branches and the
  existing conversion arms; a runtime call is libperl.
- It matches what `%Slot` already is. The comment at `Context.pm:913` records
  that carrying the defined bit ALONE (payload in a side table keyed by SSA
  ref) failed twice — a consumer using a def-bit as a value, and per-graph SSA
  numbering making the key ambiguous — and that the fix was **one aggregate
  carrying every part together**, exactly as `%Str` carries `(ptr, len)`. A
  type tag is the same argument applied once more: the information a consumer
  needs travels IN the value, not beside it.
- It is `Scalar`'s honest encoding. `Scalar` is the top of the scalar spine —
  "any scalar, we did not narrow further". A cell that means that must be able
  to say WHICH scalar it turned out to hold, or the type is unusable at the
  boundary where it matters.

**Scope, measured before proposing anything:** the surface is small — the type
declaration at `Context.pm:580`, two named accessors (`_slot_defined_bit`,
`_slot_payload_of`), `_build_slot`, and **4** raw `insertvalue`/`extractvalue`
sites. `%HashEntry` (`:582`) embeds a `%Slot`-shaped tail and would move with
it.

**NOT SCHEDULED, and deliberately.** This is T2 architecture, and [PERIGRIN]
ruled the same day that **T2 is premature until T1 is complete**. Recorded here
so the design decision is not re-derived from scratch when T2 opens, and so the
`Coerce[Scalar -> …]` GAP has a named destination rather than reading as an
open question. It also retires the framing in the entry above: the question was
never "can the target stringify a scalar-ish value" — it is "the value must
carry its own type", and the answer is a tag.

### Step 1c — chalk declares Divide/Add: SIMULATED, and it is NOT a no-op

The producer's half of the symmetric prerequisite landed as a measured no-op
(`363df04`: declaring `Print` changed 0 wire nodes, because Int/Num/Str/Boolean
all meet to themselves against Str). The bson session flagged that chalk's half
might differ, since Divide operands arrive PRE-COERCED from the producer today
and that is exactly what chalk's rule would newly see. **Measured, and they were
right.**

**Why the requirement is absent:** `%IR_OP_SOURCE_NAME` maps IR ops to source
operators, and `Divide`/`Add`/`Subtract`/`Multiply`/`NumLt`… are simply not in
it. The arithmetic signatures DO exist at source level; the IR ops are unmapped,
so `operand_repr_for_ir_op` returns undef and `_insert_str_coercions` declines
by "no opinion" rather than by judgment. Unlike `BitAnd` (genuinely ambiguous —
numeric `&` vs string-bitwise `&.` share a node) and `Print` (variadic over
List by design), **the arithmetic ops carry no such note: they look simply
missing.**

**Simulated delta** if `Divide/Add/Subtract/Multiply/Modulo/Power/Num*` declared
`Num`, over subs.md and classes.md:

    WOULD INSERT   Int -> Num       many, 1-6 per case
    WOULD DECLINE  Scalar -> Num    several, "no defined pair"

So landing it does two things at once, and only one is wanted:

1. **`Int -> Num` insertions** — these are the coercions the producer emits
   today at its Divide site. Chalk taking them over is the POINT of the handoff.
2. **`Scalar -> Num` declines** — chalk has no defined pair for these, so the
   coercion would be silently dropped rather than inserted. This is the same
   blocker as `Scalar -> Str` on Concat/Print, and it is waiting on the `%Slot`
   type tag.

**NOT LANDED.** Doing it now would move the gate for two reasons at once and
make the result unreadable — the exact shape of the 207→169 revert. The correct
order is:

    1. the %Slot type tag exists (T2)         <- makes Scalar -> Num a defined pair
    2. THEN chalk declares Divide/Add         <- now purely additive
    3. THEN the producer deletes its Divide site

Until then the producer must KEEP its Divide site: deleting it while chalk
declines `Scalar -> Num` and declares nothing for `Divide` drops the coercion
entirely and `7/2` lowers as integer division — the miscompile that site's own
comment already names.

**This reorders the sequence.** Divide/Add was last because it was assumed
small; it is last because it is BLOCKED ON T2, which is blocked on T1. StrEq
remains the only step runnable today.
