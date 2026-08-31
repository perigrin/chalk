# T2 is a narrowing analysis, not a type mapping

**Date:** 2026-08-31
**Status:** design, nothing built
**Source:** conversation with perigrin, 2026-08-31

## The claim

perigrin, opening: *"T2 needs to do a type mapping from a Chalk type to an LLVM
type but the types aren't 1:1 ... Num for example is the parent type of Int so a
Num maps to double|i64 and then T2 does narrowing passes to get a single
representation type."*

That is the design. This doc records it, and records what it corrects.

## What it corrects: nothing on the spine is concrete

The lattice is `Int <: Num <: Str <: Scalar`. A stamp names a type and everything
BELOW it, so a stamp is a SET of candidate machine types, not one:

| T1 stamp | candidate LLVM types | chosen by |
|---|---|---|
| `Scalar` | all of the below, or `%Slot` | narrowing, else box |
| `Str`    | `{%Str, double, i64...}` | is it ever rendered to characters? |
| `Num`    | `{double, i64...}`       | is it ever fractional? |
| `Int`    | `{i8,u8,i16,u16,i32,u32,i64,u64}` | sign and range |

**`Str` is NOT a leaf.** It is second-widest on the spine — `Str :> Num` — so a
`Str` stamp admits Num and Int. An early draft of this analysis bucketed
`Int`/`Str` as "already decided" and `Num`/`Scalar` as "needs narrowing"; that
bucketing is wrong and would have made T2 look like a lookup table with a
rounding error.

**`Int` is not a leaf either** (perigrin): *"if we know its positive we can use
u64 ... if we know its small enough we can use i/u 32 or 16 or 8"*. Width and
sign are neither the type nor the encoding — they are abstract-interpretation
state about VALUES, and T1 does not carry them today.

So there is no "already concrete" case anywhere on the spine. T2 is a real
dataflow pass.

## The narrowing is a representation CHANGE, not a reinterpretation

This is what makes it a pass rather than a lookup. Moving down the spine costs
an instruction and can be observable:

    i64 -> double     sitofp
    double -> %Str    a formatting call

A `Str`-stamped value that is really an Int either stores as `i64` and formats
at each use, or formats once and stores as `%Str`. Those differ in cost AND in
observable behavior — float formatting is not round-trip-free. A real choice.

## T2's output is a graph annotated with LLVM types

perigrin, correcting an earlier version of this doc: *"Wouldn't it be easier if
T2's output were just a better annotated IR graph with LLVM types instead of
Chalk types?"*

Yes, and it is the better contract. **T2 rewrites the graph; every node comes
out carrying an LLVM type.** The backend then READS a type off the node instead
of computing one.

**Why this beats handing the backend a narrowed Chalk type.** An LLVM-annotated
graph is CHECKABLE on its own — every operand of an `add i64` is `i64`, every
Phi's arms agree — before a byte of text is emitted. The alternative leaves the
final step scattered across 8 backend call sites and unverifiable, which is
exactly the shape that produced `bc943e3b` and `ebdd6a23`: consumers deciding
encoding one site at a time. It also matches what T1 already does — a pass whose
output is a graph, with an invariant checker over it.

**It costs no new field.** Measured: `Node.pm:34` declares ONE field, `$stamp`,
and `Node.pm:295` is `method representation() { return $stamp }` — a read alias,
not a second slot. So this is not "add an LLVM type field"; it is **change what
the one existing field HOLDS, at the point T2 rewrites the node.** Before T2 the
stamp is a Chalk type; after T2 it is an LLVM type. One field, two phases, the
pass as the boundary.

(An earlier draft worried about a third type-ish field joining the `body`
dual-write mess. That worry was wrong — the alias already unified them.)

**And it gives the invariant checker a sharp question:** not "is this stamp
sound?" but *"which vocabulary is this graph in?"* A graph past T2 holding
`Scalar` in a stamp is a T2 bug, detectable without reasoning about types at all.

### The mapping is a decision procedure, not a table

`%_REPR_LLVM_TYPE` (`Context.pm:3730`) maps each representation to exactly one
machine type. It looks like the design and is not (perigrin): *"This was built
before we had as solid an understanding of the problem as we do now"*, and
*"I'm not currently convinced that the mapping between Chalk and LLVM types
makes sense as a table but you are correct that something needs to perform that
mapping."*

It is 1:1 precisely BECAUSE it was built assuming its input was already
narrowed. `_repr_to_llvm_type` (`:3812`) dies on undef with a message blaming
TypeInference — the pre-split model showing through, treating a missing
narrowing as a T1 bug when the narrowing is T2's job.

Once T2 owns the mapping it is a DECISION PROCEDURE: it can consult the
interval, the uses, the sign. A hash literal expresses none of that. `Int ->
i64` is a table entry only while nothing narrows; the moment intervals exist it
is a computation. **Building it as a table now would bake in the very
pre-narrowed assumption this split removes.**

The die moves with it. Under a backend-side table, `_repr_to_llvm_type` failing
on `Unknown` is a backend-time error blaming an earlier pass. Under this
contract it is **T2 reporting its own failure to narrow**, at the point the
decision was made, with the graph still in hand.

### The test migration is a slice, not a chain

Measured 2026-08-31: **29 sites across 14 files** assert a specific lattice
value through `stamp`/`representation`. Concentrated —
`mdtest-constructive-builder.t` (8), `son-aggregate-repr.t` (4),
`element-store-repr.t` (3); the remaining 11 files hold 1-2 each.

The other ~230 `representation` references in `lib/` and the rest of the 120
touching test files READ through the alias, so they follow the field
automatically. Only these 29 name a value, and a named value is
Chalk-vocabulary — after T2 those nodes hold LLVM types.

perigrin on the fix: *"The tests will need to be re-written to either check
before T2 or to take into account the T2 transformation ... or both."* The
"both" case is the valuable one: **a test asserting the Chalk stamp before T2
and the LLVM type after is a contract test for the pass itself**, and those are
the tests that would have caught the encoding decisions leaking into consumers.

## `%Slot` is what T2 emits when narrowing FAILS

Not the goal. `Scalar => '%Slot'` is the fallback — the boxed cell you are
forced into when nothing was proven. A `Scalar` that T2 proves is only ever Int
should lower as `i64`, not as a box.

This is a better reason to build the tag than the one recorded on 2026-08-29,
and a better reason not to build it first.

## SSA does most of the work for intervals

perigrin: *"we are using SSA so I think we're not as exposed to that as you
think"* — correct, and it settles where intervals live.

Each value is defined once, so an interval attaches to a DEFINITION and cannot
be invalidated by a later mutation. No "this variable's range as of program
point P" tracking; the range is a property of the node. That kills the hard part
of classical range analysis. Loop-carried values still need a widening operator
at the Phi — one known place, not a store-tracking problem.

Since "this value is in `0..255`" is target-independent, the interval belongs in
**T1's lattice as a product**, by T1's own criterion.

### Overflow is an ACCEPTED DIVERGENCE (parked)

Measured 2026-08-31: perl promotes IV to NV on overflow —
`9223372036854775807 + 1` yields `9223372036854775808`, above `IV_MAX`, so it
came from the NV (double) slot. Chalk lowers `Add` as plain `add i64` — no
`nsw`/`nuw`/`*.with.overflow` anywhere in the target — which WRAPS to negative.
The `i64` path already diverges from perl at the boundary, today, independent of
any narrowing.

perigrin: *"We can diverge ... by having an alternate implementation that keeps
us within integer math ... but that's a future discussion."* Parked as a
deliberate divergence, not a bug to fix under T2.

With that parked, the caveat dissolves: **narrowing to `u8` is sound exactly
when the interval is bounded, and a bounded interval is precisely the proof that
overflow cannot occur.** The analysis that licenses the narrowing discharges the
overflow concern. Unbounded interval gives `i64` by default — where we already
are.

## Scope: spine collapse now, width later

Agreed with perigrin. Build the spine collapse; design the lattice so intervals
can be added as a product later.

**In scope now** — collapse `Scalar`/`Str`/`Num` to one of
`%Slot`/`%Str`/`double`/`i64`. This is what is actually blocking: the ~30
`Coerce[Scalar->Num]` sites and ~20 shape failures in the measured 205->157 gap.

**Designed toward, not built** — width and sign selection. A strictly larger
analysis (interval lattice, widening operator, sign tracking) that nothing
currently blocks on. Until intervals exist, `Int` answers `i64` unconditionally.

The seam: T2 asks the stamp for its candidate set. Adding intervals later
shrinks `Int`'s candidate set without changing the pass's shape.

## Open, not settled here

- Where the pass runs. The spec has `Loader > T1 > Optimizers > T2 > Optimizers
  > Scheduler`; nothing verifies that is still the intended order.
- Whether a `Num` that is Int at one site and double at another gets two
  specializations or one boxed representation — the monomorphize-vs-box
  question, which is the same question `%Slot` answers.
- Whether `enc` on `%Str` should record "has this been rendered to characters
  yet", given a `Str` may hold a Num. Named from a field name, NOT verified —
  check what `enc` is actually set to before relying on this.

## The corpus is T2's contract-test home — and it needs a second block

perigrin: *"The 'both' case I am pretty sure should be added to the corpus
tests."* Right, for the reason the corpus already exists: the `ir` blocks are
spec AND optimizer contract, the one place "what the graph should look like" is
written down and gate-enforced. Putting a T2 contract in unit tests would
fragment the spec across two mechanisms — and the 29 assertion sites measured
above are exactly that fragmentation.

**What it needs.** The `ir` block pins ONE graph in ONE vocabulary
(`MdtestCorpus.pm:66`, *"constructive self-consistency — build the graph FROM
the ir block"*). A T2 contract pins TWO: the Chalk-typed graph and the
LLVM-typed one. Either a second fence (`ir` and `ir-t2`) or a phase marker
inside the existing block. A real addition to the corpus format, not a free ride
on it.

**Why it is worth it.** A second block is the shape leg run twice at different
phases, which makes stamp-vocabulary drift detectable — the failure mode this
whole design circles.

## Absence must not read as success: SKIP -> TODO

perigrin: *"A missing T2 should show up as a TODO test ... not a SKIP. Same with
the IR block actually."* And then: *"Pure GAP should become TODO too."*

A SKIP claims the check does not apply. A missing `ir` block, a missing `ir-t2`
block, and a declared GAP are all **work we intend to do**. TODO says that,
keeps them counted, and turns "how many cases lack a spec?" from an unasked
question into a number that trends to zero.

This is the fourth member of a recorded family. The other three: the shape leg
does not check operands of control-reachable nodes; there is no exit-code
oracle; GAP-declared cases pass without executing. All four are absence rendered
as success.

**The file already contradicts itself on pure-GAP.** `:1002` returns **PASS**
(*"structural check passes trivially"*) while `:1075` returns **SKIP** for the
same block. One leg calls it green, another calls it inapplicable, neither calls
it outstanding. The `PASS` is the worse half: a case with no spec content
scoring a green shape leg. **Both must move together** — fixing only the SKIP
leaves the shape leg green-lighting the same 15 cases.

### Census (measured 2026-08-31, 247 cases with source)

| bucket | count | verdict |
|---|---|---|
| no `ir` block | 7 | -> **TODO** |
| pure-GAP block | 15 | -> **TODO** |
| unbuildable spec | 1 | -> **FAIL** |
| invariant PASS | 224 | unchanged |
| invariant FAIL | 0 | unchanged |
| unwalkable | 0 | — |

**22 TODOs and 1 FAIL.** With pure-GAP moved, the honest-SKIP bucket EMPTIES:
every remaining SKIP was absence dressed as success or inapplicability.

The 7 missing-`ir` cases are all from the 2026-08-29/31 T1 sessions — F17-F22 in
`subs.md` plus the signature-method case in `classes.md`. So the TODO change
surfaces THIS session's own unfinished work, which is what a TODO is for.

**Neither change depends on T2 existing.** Both are the absence-as-success
family, fixable now.

## T1 is generic; T2's FRAMEWORK is generic, its IMPLEMENTATION is the target's

perigrin: *"T1 is generic to Chalk, T2 architecturally is generic but the
implementation is specific to the LLVM target ... we need to keep a robust
separation between them as we look at alternative targets in the future."*

The split falls where the design already landed. **The decision PROCEDURE is
generic** — walk the graph, consult intervals and uses, narrow to a fixpoint.
**The CANDIDATES are the target's** — `Int -> {i8..u64}` is LLVM's vocabulary; a
JVM target says `{byte, short, int, long}`, a C target something else. Same pass,
different alphabet.

| layer | generic? | belongs in |
|---|---|---|
| T1 — types | fully | `lib/Chalk/IR/` |
| T2 — narrowing framework | architecturally | `lib/Chalk/IR/Transform/` |
| T2 — candidate sets + selection | **no, per-target** | `lib/Chalk/Target/<T>/` |

So the target supplies a TYPE SYSTEM DESCRIPTION — what machine types exist,
each Chalk type's candidate set, what a narrowing costs — and the generic pass
consults it. An interface, not a table.

### With one target the boundary is unfalsifiable — and it has already leaked

Measured 2026-08-31: **26 LLVM references inside `lib/Chalk/IR/`**, the
supposedly target-independent layer. Not merely comments:

- `IR/MethodInfo.pm:19` — a field named **`return_repr`**, documented as *"the
  LLVM representation of the method's return value"*. An LLVM-specific value on
  a target-independent IR struct.
- `IR/Schedule/Elaborate.pm:1` — its ABOUTME reads *"the Chalk **LLVM** back-half
  scheduler"*. A scheduling pass named after one backend.

`ls lib/Chalk/Target/` returns exactly one entry. With a single target nothing
FAILS when the boundary leaks, so the leak stays invisible until a second target
arrives and it all has to be untangled at once.

**The enforceable test:** `lib/Chalk/IR/` must not mention LLVM. That is a grep,
it can be a gate leg, and it currently fails at 26 sites. It would have caught
`return_repr` landing on `MethodInfo`.

### Sequencing: build the BOUNDARY, not the abstraction

Do not build a pluggable target-description interface for a second target that
does not exist. The honest version now: **put T2's LLVM-specific half under
`Target/LLVM/`, keep the framework in `IR/Transform/`, add the grep as a gate
leg.** The interface is designed toward and built when a second target asks.

The 26 existing leaks are NOT in scope for the T2 build. `return_repr` on
`MethodInfo` looks load-bearing — likely a chain, not a slice — and should be
filed separately rather than folded in.

## Measured 2026-08-31: the producer got MORE correct and the gate FELL

perigrin predicted the producer work had eliminated `Unknown`. Measured against
two pinned producers on the identical chalk tree:

| producer | gate-green | behavior | shape | invariant | worklist |
|---|---|---|---|---|---|
| `8c15e32` (36 commits back) | 205 | 205 | 207 | 219 | 17 |
| `4d57f70` (HEAD) | **157** | 157 | 161 | 219 | 65 |

**48 cases lost, and that is the design being confirmed rather than a
regression.** The dominant failure family, 33 occurrences:

    GAP: Coerce[Scalar -> Num] needs a T2 decision about how to read a %Slot payload

That message NAMES T2. It is a blocker chalk declared for exactly this
situation. The producer converted `Unknown` stamps into `Scalar`; chalk now
receives an honest type where it previously got a failure value. `Scalar` is the
top of the spine — the un-narrowed type that REQUIRES T2 to pick an encoding.

**So 205 -> 157 is the size of the T2-shaped hole**, visible now that the
producer has stopped hiding it behind `Unknown`. The recorded pattern firing at
scale: T1 improving makes T2's job LARGER.

`invariant=219` is UNCHANGED across both producers. The graphs are legal; only
their lowering is blocked. That is the definition of a T2 problem, and it is
the leg that proves the fall is not a correctness regression in the IR.

### Other families (not T2's, do not scope them in)

- 18 x `direct call to '...': callee has effect(s) on its control chain` — the
  inliner declination sites, the known F3/define+call gap.
- 3 x `field 'name' declared repr=Scalar but constructor argument repr=Str`
- 3 x `Call(method) reached LLVM backend with NO representation (undef)`
- 3 x `Call(method) 'first' node repr=Int disagrees with class 'Bag' vtable ABI
  return_repr=Scalar`

### UNRESOLVED, and it outranks the gate number

Behavioural mismatches (`lli` output != perl) went **21 -> 120**. Those are not
declared GAPs. If they are the `Coerce` fallback at `Context.pm:1938` silently
emitting `""` — the path whose own comment calls it *"a FALLBACK, not a
stringification ... the honest fix is upstream"* — then the producer improvement
WIDENED A SILENT-MISCOMPILE CLASS, not merely an honest-blocker class.

Silent wrong output outranks a declared GAP. **Not yet confirmed which these
are.** Establish before trusting any gate number from this producer.

### The floor

215 is now far out of reach by producer drift alone (157 against HEAD, 205
against the old pin). The floor's own text — *"Restoring 218 is T2 acceptance
criteria; T2 is not done while this reads 215"* — still holds, but the gap it
must close is ~60 cases, not ~10.
