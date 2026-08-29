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
