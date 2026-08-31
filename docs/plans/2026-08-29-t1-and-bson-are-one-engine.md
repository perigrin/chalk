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

### CORRECTION to step 1c (2026-08-30) — this ground was already covered

perigrin: *"We discussed before if this isn't duplicating the behavior from
TypeLibrary … I think we agreed it was."* Correct, and the entry above ("The
IR-op alias: tried, MEASURED, reverted") records it. **My step-1c writeup
`f63ea974` contradicts that record and is wrong in two ways:**

1. It says the arithmetic IR ops "look simply missing" and carry "no such
   note". **They were tried.** `Add`/`Subtract`/`Multiply` were added to the
   lookup, the gate went **207 → 169 with 102 behavioural mismatches**, and it
   was reverted whole. That is the opposite of missing — it is measured and
   rejected.

2. It frames declaring Divide/Add as a table extension gated on T2. **The
   agreed diagnosis is that the CONSUMER is overloaded, not that the table is
   incomplete.** `operand_repr_for_ir_op` serves two consumers with different
   needs: `_insert_str_coercions`, which MATERIALISES a Coerce at every
   position with an answer, and `BackwardInference`, which only READS the
   requirement. The coercion pass has been getting away with conflating "what
   does this position require?" with "should a Coerce be materialised here?"
   only because its table has a single entry.

**The prescribed next step was already written and I did not follow it:**

> Separate the two questions before aliasing: give `_insert_str_coercions` its
> own explicit table (it effectively has one already, `%_NODE_OPERAND_REPR`)
> and let the type-requirement lookup answer freely for everyone else. Then the
> alias lands without touching coercion behaviour.

**What survives from `f63ea974`:** only the simulation numbers, and they now
read as CONFIRMATION of the 2026-08-29 finding rather than as a new one — the
`Int -> Num` insertions it predicts are precisely the 102-mismatch mechanism,
measured a second time by a different route. The `Scalar -> Num` declines are
real and still want the `%Slot` tag, but they are the smaller half.

**Corrected sequencing for 1c:**

    1. de-conflate the consumer -- _insert_str_coercions consults only
       node-level contracts, not the general signature lookup
    2. THEN the alias lands (IR names as further keys onto the SHARED
       hashrefs -- genuinely not a copy, and the two names cannot disagree)
    3. Scalar -> Num still wants the %Slot tag, but that is now a separate,
       smaller question rather than the blocker

Step 1 is a change to `Analysis.pm`'s coercion pass and is the real work. It is
NOT blocked on T2 — I said it was, and that was a consequence of the wrong
framing, not a measurement.

### A FIFTH coercion site, and the rule does NOT fire there (2026-08-30)

Corpus case `subs.md F22` (`sub id { my $x = shift; return $x }` called with
`1` and with `"hi"`) is the first polymorphic callee the corpus has ever
contained. Measured: **T1's join is correct** — the shared `shift` read is
stamped `Str`, the join of `Int` and `Str` — and the backend emits **invalid
IR**, because the callee is emitted once at the joined type while the `Int`
callsite passes a raw `i64`:

    error: '%tmp_1' defined with type 'i64' but expected '%Str = type { i8*, i64, i32 }'

**This is a coercion site the producer does not emit and chalk does not insert
— a FIFTH, beside Print/Concat/StrEq/Divide/Add.** It is a call-edge site
rather than an operand position.

**And the rule as stated does not fire on it.** Checked:

    callsite id(1):   from=Int to=Str  meet=Int == from  -> NO NODE
    callsite id("hi"): from=Str to=Str  meet=Str == from  -> NO NODE

`Int -> Str` IS a defined conversion pair, so this is not a missing pair. The
rule declines because on the TYPE axis an `Int` already satisfies a `Str`
requirement — which is exactly right for an OPERAND position (`print $x` needs
a value it can stringify, and an Int is one) and exactly wrong for a CALL
BOUNDARY, where the callee has ONE emitted body at ONE machine type and an i64
does not satisfy a `%Str` parameter.

**So the difference is which axis "satisfies" is asked on.** Operand positions
ask a TYPE question, and `meet(from,to) != from` answers it. A call boundary
asks an ENCODING question: does the argument's representation match the
parameter's? Same lattice, different predicate — and the second one is not
derivable from the first, because type satisfaction does not imply encoding
satisfaction.

**Which layer owns it is [OPEN — perigrin].** perigrin's instruction was that
T1 should detect this and insert. The tension to resolve: if T1 inserts here,
T1 is deciding on the basis of a fact (the callee's single emitted body) that
belongs to lowering — the same shape as `%LOWERABLE_STAMP` asking a T2 question
in the loader. Two readings, both defensible:

1. **T1 inserts, and the trigger generalises.** The rule becomes "coerce when
   the value does not satisfy the position", with satisfaction defined per
   position kind — meet-based at operands, equality-based at call edges. T1
   never mentions machine types; it says "this parameter's type is Str and this
   argument's is Int", which is a pure type statement.
2. **T2 inserts, because the site exists only because of a lowering choice.**
   Per-callsite specialisation would make the mismatch disappear entirely
   without any coercion — the mismatch is an artefact of emitting one body, not
   a property of the program.

Reading 1 looks right on the evidence: the argument-vs-parameter type
disagreement is visible in T1 with no encoding knowledge, and specialisation is
an optimisation T2 may or may not take. Recorded rather than acted on.

### The producer's `shift` floor SILENCES chalk's call-argument join (2026-08-30)

Bisected by the bson session and reproduced here. The two of us measured
different wire stamps for corpus F22 and both were right: there is **exactly one
commit** between the pins and it is precisely the one that touches this.

    8c15e32  id=Unknown  id=Unknown  shift=Unknown   <- chalk's pin
    2c75c38  id=Scalar   id=Scalar   shift=Scalar    <- the immediate CHILD

`2c75c38` "fix(shift): bare shift drains @_, and returns one scalar" adds a
producer floor, Unknown-guarded so it only fills a hole. It is a fact about the
OPERATOR, not any callsite — bare `shift` removes one scalar slot from `@_`, so
its result is one scalar whatever the callers pass. Target-independent, and
honestly T1.

**Measured consequence for chalk, and it is a silent one:**

| producer | post-load stamps |
|---|---|
| `8c15e32` (Unknown on the wire) | `Str`, `Str`, `Str` — the join runs |
| `2c75c38` (Scalar on the wire) | **`Scalar`, `Scalar`, `Scalar` — the join does not** |

The join stops happening. Not an error, not a GAP: the answer is simply less
precise, and nothing reports it. F22 lowers no better either way, so the corpus
gate cannot see the difference.

**`Str` does NOT contradict `Scalar`.** `Scalar` is the honest floor from
`shift` alone; `Str` is strictly more precise and comes from information the
producer does not have (the callsites). `meet(Scalar, Str) = Str`, so chalk's
join is a legal NARROWING of the producer's floor. The division of labour holds
— it now starts from `Scalar` rather than `Unknown`.

**Which pass, measured by disabling each in turn** (against `8c15e32`, counting
`repr=Str`):

    without _seed_direct_call_arg_reprs   3 -> 2   <- contributes
    without _stamp_method_call_reprs      3 -> 3
    without _propagate_computed_reprs     3 -> 3

So `_seed_direct_call_arg_reprs` is the pass, and it is CHALK-side
(`Analysis.pm:673`, called from the fixpoint at `:264`) — not a producer pass,
which is why a grep of perl5-son found nothing.

**THE ORDERING RULE, restated as a cross-repo obligation.** The bson session's
own rule — *"a floor must be written AFTER every narrowing pass, or the passes
that only fill Unknown skip it"* — was applied correctly WITHIN the producer.
What this case shows is that it does not stop at the repo boundary: **a
producer-side floor runs before every chalk-side narrowing pass, unavoidably,
because it is on the wire before chalk starts.** So a floor that is correctly
late on one side is unconditionally early on the other.

The remedy is not to remove the floor — it is right, and `Scalar` is better
than `Unknown` for every consumer that cannot narrow. It is that **chalk's
narrowing passes must treat `Scalar` as narrowable**, which is what
`_is_narrowed`'s `Scalar` exemption already does for the fixpoint. The seed
pass needs the same treatment; it currently keys on `Parameter` nodes, and this
wire shape has `ArgsSource` + a `shift` Call instead, so it does not reach these
positions at all.

**[OPEN]** Whether the seed should also fire on the `ArgsSource`/`shift` shape.
Not built: it would change stamps on a shape the corpus exercises once, and the
gate cannot discriminate the result — precisely the situation where a test, not
a gate, has to carry the claim.

## THE WIRE IS INPUT: verify, do not re-derive (perigrin, 2026-08-30)

> "Chalk has to treat the wire as the input level and assume that unless Chalk
> itself has verified that nothing is optimal."
>
> "My premise is based on the idea that verification is cheaper than
> derivation."
>
> Consistency, not soundness.

This corrects the framing in the entry above, which treated the producer's
`Scalar` floor as a collaborator's answer that chalk refines. It is not. **The
wire is INPUT, and an input claim is unverified until chalk checks it.**

The distinction that follows, and which the previous entry collapsed:

| | |
|---|---|
| wire says `Scalar`, chalk **checks** and narrows to `Str` | verified; the better answer is a side effect |
| wire says `Scalar`, chalk **accepts** it | **no verification happened** — the stamp may be right, nothing established that |
| wire says X, chalk derives Y **incomparable** with X | the wire is WRONG — the case worth dying on |

The third is what the premise buys. If chalk only ever fills holes, a wrong
wire stamp is **structurally invisible**: there is no path on which chalk and
the producer disagree, so disagreement cannot be reported. Same shape as the
Pipeline MOP finding — wrong-but-consistent, invisible because nothing
cross-checks.

**CONSISTENCY, NOT SOUNDNESS.** Confirming `meet(wire, derived) == derived` is
cheap and local. Confirming the wire's claim is SOUND is not — for a `Call`
return it means trusting the callee's record, which is another wire claim, and
the regress has no bottom. Consistency is decidable against what chalk already
computes; soundness is not chalk's to establish.

### The pattern is already implemented, at exactly ONE site

`Analysis.pm:1760-1790` (method return types) is this model, and its comment
states the premise almost verbatim: *"Re-deriving what was already sent is the
recovery-by-scanning that the metadata channel exists to retire."* It has all
three arms — the wire is the first source, the graph walk remains because the
producer works method-by-method and cannot see a caller, and:

> **WHERE BOTH COMMIT AND DISAGREE, THAT IS A DEFECT IN ONE OF THEM.** Nothing
> compared them before, so a divergence would have been silent — the backend
> consuming one answer while the metadata channel carried another. Refuse
> loudly instead.

Measured there: **11 of 15 agreed, 4 were Unknown-on-wire and derivable, ZERO
disagreed.**

### And absent at seven others

Seven guards have the shape *"the wire answered something narrow, so skip"* —
`Analysis.pm:645, 1189, 1288, 1724, 1730, 1742, 1880`. Each is deference, not
verification. Under this ruling each should become *"the wire answered, so
CHECK"*: derive anyway where derivation is cheap, `meet` the two, and refuse
where they are incomparable.

The `shift` case is the worked example. The producer floors bare `shift` to
`Scalar` (correct — a fact about the operator). Chalk has the callsites and can
narrow to `Str`. Today it accepts `Scalar` and stops, which is the middle row:
the stamp is right by luck, not by structure.

**NOT BUILT.** Two things to settle first: what chalk does on a genuine
disagreement (die is the GAP-not-miscompile answer, but a merely STALE wire
would then break the build), and whether the 1760 site's die is the template or
whether a narrowable disagreement should narrow silently and only an
INCOMPARABLE one should die.

### CORRECTIONS from perl5-son-2c (2026-08-30) — attribution, and §6 rejects the remedy

Note this arrived from a DIFFERENT producer session (`perl5-son-2c`, not `e6`),
which matters because one of the corrections is itself about provenance.

**1. THE T1/POLICY SPLIT IS PERIGRIN'S, NOT THE BSON SESSION'S.** I recorded it
as theirs and thanked them for it. It is perigrin's ruling and predates this
conversation by four days: **T1 spec §6**, from *"`_build_registry_from_mop` is
a code smell … I don't think we should have a registry, and the MOP is part of
the stamp/IR"*. Re-attributed here; the earlier entry's framing of it as a
teammate's insight is wrong.

**2. THE PRODUCER DOES HAVE CALLSITE INFORMATION.** The `e6` session told me it
does not, and corrected that: `_discover_and_translate` holds every graph at
once, both callsites are on the wire, `_stamp_calls_from_callees` already walks
that structure (it just reads the callee's `return_type` and never the caller's
arguments), and the name→graph lookup exists in `_rederive_sub_return_types`.
**Caller→callee is a direction never written, not one the producer cannot see.**

**3. AND §6 REJECTS THE SHAPE I WAS HEADED FOR.** Verified in the spec at
`docs/specs/2026-08-26-t1-type-inference-requirements.md:165-178`:

> With the MOP on the IR, a `Call` can answer "what does my callee return" from
> the graph it is already in, and T1 needs no set. Without it, the only way to
> reach a callee is a lookup in a hash somebody passed alongside — **which is
> the graph-set shape §2 rejects.**

A caller-index over a graph set is not a smaller version of the right fix; it is
the shape the spec already condemned. So the call-argument seed is **4a/4b work
blocked behind 4d**, and the ordering is fixed: **4c → 4d → 4a → 4b → 4e**.

**Consequence for the call-edge Coerce (F22).** Do NOT build it. It would sit on
a seed that has to move, and the seed's reachability path is exactly what §6
changes. F22 stays a declared GAP until 4d lands.

**What is already right on chalk's side.** `resolved_graph` does not exist here
— `Chalk::IR::Node::Call` carries ONE handle, `target` (`Call.pm:35`), and
`_resolve_direct_calls` now reads it exclusively (`ee9e220a`, today). That is
the single-record shape §6 asks for; the producer-side twin-record smell
(`method_return_types` holding a bare string and reconstructing
`"${cname}::${mname}"`, beside `subs` holding a record with `{graph}`,
producing two twin rederive passes) has no counterpart here.

## `eval` is not a coercion: an effect wearing a pure node's type (2026-08-30)

> "That's a place where eval is different from a pure coercion … it has
> effects." — perigrin

The producer now models `eval "..."` as `Coerce[Str -> Code]` (perl5-son
`8ac7ed3`), replacing an op-table refusal. The wire is verified correct here —
`from_repr=Str to_repr=Code`, control-pinned, with Region/Phi carrying the trap
— and the contract division is right: the producer states the conversion, the
consumer refuses what it cannot emit.

**But `Coerce` is the wrong node TYPE for it, and chalk's own design says so.**

A `Coerce[Int -> Str]` is pure: same input, same output, no observable trace,
deletable when unused. **`eval` violates every part of that** — it can `die`,
define subs, touch globals, set `$@`; the same string twice need not behave the
same way.

**Measured:**

    Coerce->is_fixed = FALSE   (the TYPE declares itself pure)
    Unwind->is_fixed = TRUE

Yet this instance carries `control_in`. So effect-ness has become **a property
of one instance rather than of the type** — and `Node.pm:95` states the opposite
rule, with prior art behind it:

> *"A PROPERTY OF THE TYPE, deliberately … In Graal an effectful node IS a
> FixedNode, which is why its diamond-collapse test degenerates to 'is the arm
> empty?' — the side-effect question is subsumed structurally and never asked.
> Chalk cannot take that shortcut while the answer lives in a name list a
> consumer must remember to consult."*

The producer's own bug proves the cost: with the Coerce left pure, DCE removed
a void-context `eval q{1};` entirely and **the eval vanished** — a miscompile,
not a GAP. They fixed it by pinning that instance. That fix is correct and does
not generalise: every consumer must now ask "is THIS Coerce pinned?" rather than
"is a Coerce pure?", which is exactly the name-list fragility `Node.pm` names.

### The consequence chalk already exhibits

Chalk refuses the eval graph — but with the WRONG message:

    LLVM backend: Phi node encountered in lower_value before its enclosing
    if/loop structure was processed … (region=Region#2, head=undef)

Not `Str -> Code`. The scheduler reaches the Phi before anything reaches the
Coerce, so the refusal names a scheduling invariant instead of the unsupported
conversion — and `head=undef` reads as an internal invariant violation, sending
a reader after a scheduler bug. Same class as the producer's stack underflows:
**it fires before the honest GAP and masks it.**

**[OPEN]** Whether `eval` wants its own node type (effectful by type, the way
`Unwind` is) rather than a control-pinned `Coerce`. That would make DCE-safety
structural rather than per-instance, and would let chalk refuse at the
conversion rather than at the Phi. Not proposed to the producer as a change —
the current shape works and the alternative is a wire-contract question.
Recorded because the pin is load-bearing and easy to lose.

### Why the void-context `eval` deletion IS a miscompile — measured, not assumed

perigrin challenged the claim above: *"Is that a miscompile? What was that eval
doing? … what you've cited genuinely looks like dead code."* Fair — `eval q{1}`
in void context cannot die, defines nothing, and its value is discarded. I had
repeated the producer session's word without testing it.

**Measured, and it is observable — for a reason neither of us stated:**

    $@ = "prior"; eval q{1}; print "[$@]"    ->  []
    $@ = "prior";            print "[$@]"    ->  [prior]

**A successful `eval` CLEARS `$@`.** So the void-context eval performs a write
to a global that a later reader can see. Deleting it changes observable state,
which makes the deletion a miscompile after all — but on the SUCCESS path, not
the failure path.

The realistic shape:

    eval q{die "x"};   # sets $@
    eval q{1};         # CLEARS it -- this is the "dead" statement
    # a reader of $@ here sees "" with the eval, "x at ..." without it

**This sharpens the effect claim rather than merely confirming it.** The earlier
entry argued `eval` is effectful because it *can* die, define subs, or touch
globals — all true, and all reasons a SPECIFIC eval might be effectful. But
`eval q{1}` does none of them and is still not deletable, because **clearing
`$@` is unconditional: it happens on every successful eval, whatever the
string.** There is no eval that is pure.

That is a stronger argument for effect-by-type than the one recorded above: the
effect is not a property of what the string does, so no analysis of the string
can license removal. A `Coerce` whose purity depends on its operand's contents
cannot be a pure node type.

**Also worth noting what this makes `$@`:** the producer session reports `$@` is
not modelled anywhere on their side. So the wire currently carries an eval whose
only unconditional effect is a write to something the IR does not represent.
That is the same absent-vs-Unknown distinction as elsewhere — the effect is not
"unknown", it is unrepresented, and a consumer cannot tell.

### Why `eval` is effectful — the plain reasons, not the clever one

perigrin challenged the claim that deleting a void-context `eval q{1};` is a
miscompile: *"what you've cited genuinely looks like dead code."* Fair — that
eval cannot die, defines nothing, and its value is discarded. I had repeated
the producer session's word without testing it.

**`eval` is effectful for three plain reasons, any one of them sufficient:**

1. **It can die.** A string eval is a control-flow construct, not a value
   computation.
2. **It can mutate the program** — define subs, assign globals, load modules.
3. **It runs the compiler at runtime.** The conversion function IS perl, which
   is why the producer's own GAP is a statement about WHEN (B::SoN runs at
   CHECK time), not about types.

That is enough to disqualify a node type whose contract is purity, and it needs
no footnote. **A `Coerce` whose purity depends on its operand's contents cannot
be a pure node type**, and no analysis of the string can restore that — the
string is not knowable until runtime, which is the whole point of `eval`.

**A measured observation, deliberately NOT the argument.** Testing the specific
`eval q{1};` case, it turns out not to be as dead as it looks: a *successful*
eval clears `$@`.

    $@ = "prior"; eval q{1}; print "[$@]"   ->  []
    $@ = "prior";            print "[$@]"   ->  [prior]

So that statement is observable, and the producer session's "miscompile" was
literally right. **But chalk's DCE contract should NOT rest on this.** Perigrin's
objection stands: it is a corner of perl semantics that surprises people, and a
correctness argument built on it is fragile — the next reader finds the rule
unmotivated and "fixes" it. It is also unusable as a rule here, because `$@` is
not modelled on the wire at all (per the producer session), so an argument
resting on it rests on something the IR does not represent.

Recorded as a fact about why that particular case is not dead code. The RULE is
reasons 1-3.

## `$@` should be modelled in the IR eventually (perigrin, 2026-08-31)

Measured: **chalk models no punctuation global.** `grep` over `lib/Chalk/IR/Node/`
finds no `$@`, `ERRSV`, or equivalent, and the producer session reports the same
absence on their side. So a graph containing an `eval` describes a construct
whose only unconditional effect is a write to something the IR does not
represent.

**Why this is worse than a missing feature.** A program can OBSERVE `$@`. A
graph that omits it is INCOMPLETE, not merely unlowerable — and the difference
matters because an incomplete graph can be lowered *successfully* and still be
wrong, whereas an unlowerable one refuses. This is the absent-vs-`Unknown`
distinction one level up: the effect is not "unknown", it is unrepresented, and
no consumer can tell.

**There is a precedent, and its caveat is the design constraint.**
`Chalk::IR::Node::EnvRead` already models reading external state as a node —
host process state, a `Value`, hash-consed. But its comment says exactly why
that works:

> *"Env writes are not modelled, so the read is constant per process and
> hash-consing two reads of the same key to one node is sound."*

**`$@` is the opposite case in every respect.** It is written constantly — by
every eval, successful or not — so:

- it CANNOT be hash-consed: two reads of `$@` at different program points are
  different values, which is the `staleness_kind` question, not a naming one;
- the READ is ordered against every write, so it is not a free-floating `Value`
  the way an `EnvRead` is;
- the WRITE is implicit — no source construct writes `$@` directly; it is a
  side effect of `eval` and `die`, which is why nothing in the walker has a
  natural place to emit it.

**That third point is the real work.** Modelling the read is the easy half and
resembles `EnvRead`. Modelling the *write* means every effectful construct that
touches `$@` must say so, which is a producer-side question about what an `eval`
node carries — and it connects to the open question above about whether `eval`
wants its own effectful-by-type node rather than a control-pinned `Coerce`. A
node that owns the eval effect is also the natural place to hang its `$@` write.

**NOT SCHEDULED.** Recorded so the connection is not lost: `$@` modelling, the
`eval` node type, and the producer's two stack-underflow crashes (`eval { die }`
then `$@`) are one cluster, not three items. The crashes are the current
symptom of the absence.

### CORRECTION: chalk DOES model globals, and `$@` is not on the self-hosting path

Two corrections to the entry above, both perigrin's.

**1. "Chalk models no punctuation global" was wrong** — I grepped for `$@` and
`ERRSV` and concluded from the absence, the same error as the "missing pins"
earlier. Chalk models `@_` as `ArgsSource`, and `EntryDef` covers stash
variables generally, with the sigil as part of node identity:

> *"`_` alone names THREE different things in perl: the scalar `$_`, the
> argument array `@_`, and the bareword `_` filetest handle … A name-only
> identity hash-consed the first two into ONE node — measured."*

So the machinery for naming a global read EXISTS, and `$@` would be an
`EntryDef`-shaped read rather than a new kind of thing. What `$@` still needs
beyond that is the WRITE side, which remains the real work: `EnvRead`'s
hash-consing is sound only because "env writes are not modelled", and `$@` is
written by every eval.

**2. Measured: `$@` appears ZERO times in `lib/`.** Chalk's own source never
reads or writes it — the project mandates `try`/`catch` over `eval` blocks, and
`try`/`catch` compiles to `entertrycatch` with the error bound to a LEXICAL
(`$e`), not to `$@`. Verified: inside a `catch` block, `$@` is empty.

**So `$@` is NOT on the self-hosting path.** It is a Perl-subset completeness
question, not a blocker for compiling chalk with chalk. That lowers its
priority relative to everything gating Phase 5, and it means the producer's two
stack-underflow crashes (`eval { die }` then `$@`) are also off the
self-hosting path — they matter for `t/base` coverage, which is the producer
session's current target, not for the capstone.

Revised: `$@` modelling stays FILED, and the cluster it belongs to — the eval
node type, the `$@` write side, the underflow crashes — is Perl-subset
breadth. **`try`/`catch` is what chalk itself needs, and `entertrycatch`
already lowers to a Region merge on the producer side.**

## T2 architecture review before building the tag (2026-08-31)

perigrin asked for a review of the T2 architecture and episodic memory before I
start. **Episodic memory is unavailable this session — the MCP server failed to
connect and stayed down through two `/mcp` retries — so this rests on the repo
record only.** Anything that lived solely in conversational recall is not
consulted here, and that limitation is the first finding.

### What the spec actually says T2 IS

`docs/specs/2026-08-26-t1-type-inference-requirements.md`, and it does not match
what I was about to build:

> *"one object owning `Loader > T1 > Optimizers > T2 > Optimizers > Scheduler`"*
>
> *"The test: can the compiler still produce a correct program without this
> stage? … Remove T1 and the backend receives a graph it cannot lower — or
> lowers by guessing. **T2 is the same**: remove it and there is no encoding at
> all."*
>
> *"neither may DECLINE a case it cannot handle: an optimizer passes it
> through, a correctness [pass may not]"*

**T2 is a PASS IN THE PIPELINE, not a change to the backend.** It sits between
optimizer stages and owns the encoding decision as a `Graph -> Graph`
transformation — the same shape as T1, and for the same reason: it is a
correctness stage, not an optimization.

### What I was about to do instead, and why it was wrong

I had scoped "add a tag field to `%Slot`" as a **backend edit** — change the
type declaration in `Target/LLVM/Context.pm`, fix the sites that index into it.
That is T2's *consequence*, not T2. It would put the encoding decision in the
same place `%LOWERABLE_STAMP` put it — inside a consumer, below the layer that
owns it — which is the exact level violation this whole phase exists to undo.

**The tag is what T2 EMITS. T2 is the pass that decides it.**

### The measured surface, which is larger than the plan estimated

Recorded so the next attempt starts from it rather than the old figure:

| | plan said | measured |
|---|---|---|
| raw `insertvalue`/`extractvalue` | 4 | **5** |
| `getelementptr` into a `%Slot` | — | **10** (3 at index 0, 4 at index 1) |
| field-cell GEPs (`obj`, `slot_idx`, 0/1) | — | **9** |
| **hardcoded size** | — | **`$n * 16` at `:5490`** |

**The size is the trap.** `%Str` and `%StrPair` compute their sizes from a field
list (`_struct_size_bytes(@_STR_FIELDS)`); `%Slot` hardcodes 16, and a third
field makes that silently wrong — a buffer under-allocation, not a compile
error. That must become a field list before any field is added, and it is worth
doing on its own regardless of the tag.

`%HashEntry = type { i8*, i64, i32, i1, i64 }` inlines a Slot-shaped tail rather
than embedding `%Slot`, so it does not follow automatically.

**Appending the tag as field 2** (`{i1 defined, i64 payload, i32 tag}`) keeps all
16 literal indices valid, unlike inserting it in the middle. That is the shape
to take when the time comes.

### Sequencing, revised

1. **`%Slot` gets a field list** and `_slot_size_bytes`, replacing `$n * 16`.
   Pure refactor, no behaviour change, removes the silent-corruption trap.
2. **T2 exists as a pass** — `Chalk::IR::Transform::…`, `Graph -> Graph`,
   entered from the Pipeline's transforms slot, mirroring T1's shape.
3. **The tag is what it emits.** Backend sites follow from the pass, not before
   it.

**NOT STARTED.** Step 1 is safe and useful today; steps 2-3 want perigrin's
ruling on whether T2 lands as a full pass now or whether a narrower "enough T2
that the lowerings work" is intended — his phrasing suggests the latter, and
that is a smaller thing than the spec's T2.

### `%StrPair` should fold into `%Str` — and it is the SAME work as the tag

perigrin, 2026-08-31: *"%StrPair should probably be folded into %Str period."*
Measured, and it is a half-finished migration whose remaining half is the Slot
payload path.

    %Str      = { i8* ptr, i64 len, i32 enc }   the VALUE type
    %StrPair  = { i8* ptr, i64 len }            the BOXED HEAP CELL

The code says so itself, in `@_STRPAIR_FIELDS`'s own comment: *"this is the
BOXED HEAP CELL, deliberately still two fields. The THREE-field %Str below is
the VALUE type. **They are being reconciled**; see the %Str block for why the
value type moved first."*

So the value type moved and the boxed cell did not. **52 `StrPair` references
remain against 43 for `%Str`** — the older shape is still the larger one.

**Where it survives is the finding.** All 22 `%StrPair*` uses are the same
pattern: a Str boxed into an i64 payload and recovered from it —

    inttoptr i64 $raw_pay to %StrPair*     ArrayRead :Str
    inttoptr i64 $raw_pay to %StrPair*     HashRead :Str
    bitcast  i8* $pair_raw to %StrPair*    field store
    inttoptr i64 $pay      to %StrPair*    field read

Array elements, hash values, object fields. **That is the `%Slot` payload path**
— exactly the code the type tag has to touch. `%StrPair` exists because a
`%Slot` payload is one i64 and a `%Str` is three fields, so a Str in a slot has
to be boxed behind a pointer.

**Which makes these one piece of work, not two.** A tagged `%Slot` is the thing
that decides how its payload is read; `%StrPair` is a hand-rolled answer to that
same question for one type, predating the tag. Folding it in before the tag
exists would mean rebuilding the boxing twice.

**Recorded, not started.** The `enc` field is the substantive difference — a
boxed Str currently loses its encoding, which is a real gap independent of the
tag, and the fold is where it gets fixed. Sequenced after the T2 pass exists,
alongside the tag rather than before it.
