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

---

# REVISION 2026-08-31 (evening): reviewed, traced, and re-scoped

Two independent reviews (adversarial + ponytail) plus a full trace of one
failing case. The design analysis SURVIVED; the slice built against it did not,
and three of the numbers above were wrong. This section supersedes the
measurements, not the analysis.

## The slice was reverted: the tag broke codegen

Commit 6101b9ef added `tag` at index 1, shifting `payload` from 1 to 2 while
every production read and write still used literal indices. **16 failures in
`t/bootstrap/ir/llvm-array-hash.t`**, bisected and reproduced. Two fault
classes: `insertvalue` became an i64-into-i8 type error `lli` rejects, and
`getelementptr ... i32 1` silently addressed the TAG BYTE instead of the
payload -- which under opaque pointers is heap corruption, not an error.

`_slot_idx` was written to prevent exactly this and had **zero production
callers**. Its test asserted that `_slot_idx` works, never that anything CALLS
it -- AC-green over an untested path. Reverted in 8d4e512c; the sizeof
conversion was kept (it is independent and found the %HashEntry 48-vs-32 bug).

## The numbers were wrong

| claimed above | measured |
|---|---|
| 33 blocked sites | **11 cases** -- each message prints 3x |
| a family of `Coerce[Scalar -> X]` | **one pair**, `Scalar -> Num` |
| 218 is the target | **215 is the CEILING** -- `L: GREEN` count in the corpus |
| 120 behavioural mismatches, feared silent miscompiles | **117 are empty output** from programs that never lowered; 3 are real, all declared B::SoN TODOs |

The corpus holds 247 cases: 215 declared `L: GREEN`, 32 declared `L: GAP`. So
"restore 218" exceeds the number of green-declared cases that exist, and the
gap T2 faces is 157 -> 215, of which most is NOT T2's: 18 inliner-declination
(the F3/define+call gap) and ~114 producer gaps.

## THE TRACE -- what actually produces `Coerce[Scalar -> Num]`

Ran the `field-attrs` case end to end. The chain, each step measured:

1. **The producer emits `Coerce[Unknown -> Str]`** for the `say`. It does NOT
   emit `Scalar -> Num`.
2. **`:reader` calls land `Scalar`.** The wire says `field $left: Scalar` and
   `Pair::left return_type` is ABSENT. A `:param` field with no declared type
   is honestly Scalar on the class record.
3. **`_narrow_unknown_coercions` (`Analysis.pm:994`) mints it.** It rebuilds
   the Coerce with `from_repr => $repr`, the operand's actual representation.
   Operand is Scalar, so the new node is `Coerce[Scalar -> ...]`.
4. **`Add` wants Num**, so the node becomes `Coerce[Scalar -> Num]`.
5. **The backend dies** -- no arm for a Scalar source.

**So the `Scalar` is HONEST and this is genuinely T2's problem**, exactly as
the analysis above says. Two hypotheses were killed by the trace:

- *"It is a mis-stamp upstream; the spec says :Int"* (ponytail). The spec's
  `:Int` is what a CORRECT T2 would produce, not what the wire carries. The
  supporting argument -- `%_COERCIBLE_TO` has no Scalar key, so chalk cannot
  mint this -- breaks at its first link: that table gates `Analysis.pm:920`,
  and the node comes from `:994`, which does not consult it.
- *"It comes from an arm join"* (mine). The die now interpolates `$what`
  (4f4ba467); all 11 report `Coerce`, the node path at `:2165`.

## What T2 must decide, stated concretely

For `Coerce[Scalar -> Num]` where the Scalar is a `:reader` return:

**The type IS knowable, but not from the class record.** `Pair->new(left => 10)`
passes an Int. The field's type is knowable at the CONSTRUCTION SITE, and the
reader returns whatever the field holds. That is a whole-program fact -- the
`_seed_direct_call_arg_reprs` fixpoint already does this shape of reasoning for
sub arguments (`Serialize/JSON.pm`, joins over N callsites).

So the first slice is **compile-time narrowing, not a runtime tag**: propagate
the constructor argument's repr to the field, and the field's repr to the
reader's return. If every construction site of `Pair` passes an Int for `left`,
`Pair::left` returns Int and the Coerce becomes `Int -> Num`, which already
lowers (`sitofp`).

**The runtime tag is the RESIDUAL case**, for a field genuinely written with
two different readings from different sites. Build it when a case proves it
exists -- the ponytail review's charge that it was "a runtime answer to a
compile-time question" is CORRECT for the 11 measured cases.

## Blocker ordering (revised -- the plan above had this wrong)

1. **`_field_store_is_coherent`** (`Context.pm:6449`, landed ebdd6a23) refuses
   `Num` and `Str` into a Scalar-declared field. Measured: `field=Scalar
   value=Int` TRUE, `value=Num` false, `value=Str` false. Those are exactly the
   stores the spine collapse must make. **The plan above never mentions it.**
2. **The tag vocabulary is undersized.** `_box_payload` boxes EIGHT reprs into a
   Slot payload (Int, Num, Str, Boolean, ArrayRef, HashRef, CodeRef, Object);
   a 4-value tag maps five to `Undef`, so a live heap pointer would tag
   identically to a genuinely-undefined cell.
3. **There is no `phi %Slot`.** Merges emit two parallel phis (`Context.pm:5964`
   and `:5965`); a third field is silently dropped at every merge and
   reconstructed from whatever `_build_slot` was passed.
4. **Index migration** -- route every insertvalue/extractvalue/GEP through
   `_slot_idx`, and give `%HashEntry` (a hardcoded literal embedding slot-like
   fields) the same treatment.

Items 2-4 are prerequisites for the TAG. Item 1 gates the compile-time path
too. **The compile-time slice needs only item 1.**

## Acceptance criterion (replacing "restore 218")

215 is not well-formed for T2: it mixes families T2 cannot move, and a
coincidentally-correct encoding scores green on the behaviour leg. Use instead:

- **zero `Coerce[Scalar -> *]` GAPs** (currently 11 cases), AND
- **gate-green does not regress** from its measured value, AND
- the corpus pins the narrowed repr, so a wrong-but-passing encoding is caught
  by shape rather than by stdout.

## Deleted from this plan as YAGNI

- **Interval analysis for width selection.** Nothing blocks on it; keep one
  sentence saying the tag vocabulary extends additively when it arrives.
- **The pluggable target type-system description.** One target exists; the
  boundary is unfalsifiable until a second one does.
- **The `ir-t2` corpus block.** Nothing produces a second vocabulary yet. File
  it when T2 exists.
- **Rewriting `stamp` to hold LLVM types after T2.** The value comes from the
  checker, and the checker does not exist. One field with two vocabularies and
  no verifier is a footgun.

KEPT: the `lib/Chalk/IR/` must-not-mention-LLVM grep gate (cheap, catches
`return_repr` on MethodInfo) -- with an allowlist, since `IR/Target.pm` names
LLVM legitimately as an example.

## Narrowing a producer's widening: `join(Scalar, Int) = Scalar` is the blocker

perigrin, on whether chalk should narrow a widening the producer chose:
*"Yes if we can guarantee it. The producer isn't necessarily reliable ...
currently it's B::SoN but that may not always be true."*

That is a stronger principle than fixing one case: the wire is an INPUT, and
chalk should not inherit its imprecision. Here is exactly what stands in the
way, measured on F8 (`sub f { $_[0] + 1 }`).

**The producer's widening is locally correct.** Inside `main::f`, `$_[0]` reads
an element of `@_` -- an array of Slots -- and nothing local narrows it. So
`Coerce[Scalar -> Num]` is the honest answer THERE. The `Int` is only knowable
whole-program: the caller passes `Constant(10) :Int`.

**The pass that should close this already exists and already handles the
shape.** `_seed_direct_call_arg_reprs` (`Analysis.pm:720`) recognizes both
`shift @_` and `$_[0]` (`Subscript(ArgsSource, Constant(0))`, `:800-814`), and
joins over every callsite rather than taking the first -- its own comment
records the measurement that source order alone otherwise picked between two
different wrong answers.

**The blocker is one line, and it is deliberate.** At `:837`:

    my $joined = _join_repr( grep { defined } $existing, $slot->{reprs}->@* );

The read's EXISTING stamp folds in as another arm. Measured:

    join(Scalar, Int)  = Scalar
    join(Unknown, Int) = Unknown
    join(Num, Int)     = Num

So a read already stamped `Scalar` absorbs every callsite's `Int` and the
fixpoint can never move it DOWN. That is not an oversight -- the comment at
`:830-835` names it as the termination latch: *"the existing stamp is folded
INTO the join, so a stamp only ever moves UP the lattice, and the lattice is
finite with `Unknown` at the top. A node can therefore be re-stamped only
finitely often."* Two tests pin it (`ir/is-narrowed-guards.t`,
`ir/propagate-fixpoint-terminates.t`), and loosening it to "re-stamp whenever
something changed" is recorded as what HANGS the loop.

### CORRECTION: meet already exists, is sound, and is already used

perigrin asked the right question -- *"Why join and not meet?"* -- and it
dissolves most of the section above. Two claims there were wrong.

**Wrong 1: "`meet_types` and `narrow_type` have ZERO callers."** That note is
stale. `BackwardInference.pm` calls `meet_types` twice (`:125`, `:147`).
Measured, it already gives the answer this needs:

    meet(Scalar, Int)  = Int
    meet(Unknown, Int) = Int
    meet(Num, Int)     = Int
    meet(Scalar, Str)  = Str

`Unknown` is documented as TOP for meet -- *"it constrains nothing, so the
other side wins"* -- which is exactly the treatment `Scalar` needs.

**Wrong 2: the two operators are not a special case, they answer different
questions.** The line at `:837` does two jobs with one operator:

| arm | right operator | why |
|---|---|---|
| the callsite reprs | **join** | the read is ONE node shared by every caller, so its stamp must be true of ALL of them -- `join(Int, Str) = Str` |
| the existing stamp | **meet** | that is not a callsite, it is the analysis's PRIOR STATE, and `Scalar` there is the absence of a measurement rather than one |

Join across callsites is soundness. Joining the prior state in was chosen for
TERMINATION, and meet gets termination a different way.

**And the termination pattern is already written down.** `BackwardInference`
runs meet in the descending direction with the discipline this needs, in its
own words: *"Kildall's store discipline, in the descending direction: fold every
source -- the declaration, the requirement, AND the stamp already on the node --
into a single meet. Meeting in the node's own value is what makes the chain
monotone: without it a later round can move the stamp SIDEWAYS between two
incomparable types and the loop need never settle."*

So the oscillation risk named above has a known answer: fold the node's own
stamp into the MEET (not the join), and the descent is monotone over a finite
lattice.

### What actually remains: which nodes may be narrowed

`_is_backward_inferable` admits exactly three operations -- `PadAccess`,
`FieldAccess`, `Parameter`. A `Subscript` is NOT among them, so F8's `$_[0]`
read is ineligible today.

That guard is the recorded lesson **"fill a hole, never preempt a source"**: a
backward requirement may only type a node that READS a value, never one that
COMPUTES one, because a computed node's type is derived from its operands and
overwriting it asserts something never derived from anything. The memory note
records shipping a miscompile (gate 215->199, an i64 read as a double) by
ignoring exactly this.

**So the open question is narrow and specific: is a `Subscript(ArgsSource, 0)`
a READ or a COMPUTATION?** It reads an element of `@_`, which argues read --
the same category as `FieldAccess`. But `Subscript` in general computes over an
arbitrary container, and admitting the operation wholesale would admit those
too. The honest move is a predicate over the SHAPE (`Subscript` whose container
is `ArgsSource` and whose index is a literal) rather than over the operation.

NOT BUILT. The guard exists for a measured reason and widening it needs its own
evidence.

### The design question

Narrowing requires moving DOWN the lattice, which is what the termination
argument forbids. Three ways out, none free:

1. **[SUPERSEDED by the correction above -- the operator is the answer, not a
   special case.]** Don't fold the existing stamp when it is un-narrowed. `Scalar` and
   `Unknown` are not evidence -- they are the ABSENCE of evidence, so folding
   them in gives an un-narrowed answer priority over a real measurement. This is
   the smallest change and preserves termination: the join is still monotone
   over the callsite arms, and an un-narrowed existing stamp simply stops
   poisoning it. RISK: a read stamped `Scalar` for a REASON (a genuine
   multi-type callsite set that already joined to `Scalar`) would be re-narrowed
   on the next pass and oscillate. Needs a way to distinguish "Scalar because
   nothing narrowed it" from "Scalar because the join said so" -- which is the
   same distinction the %Slot tag draws between `Opaque` and `Undef`.

2. **Two-phase: collect all callsite arms, then stamp once, never re-entering.**
   Terminates by construction. Larger change to the fixpoint's shape.

3. **Leave it, and treat the producer's widening as authoritative.** This is the
   status quo, and it is what perigrin's principle rejects.

**DO NOT bolt (1) on without resolving its risk.** A narrowing that oscillates
is worse than one that never happens, and the memory note on the `Length`
narrowing records a chalk-side narrowing that regressed the gate 205->195 and
was reverted, on the grounds that the narrowing was the PRODUCER's. The
difference here is that perigrin has now stated the opposite principle
explicitly -- but the soundness work is still owed.

**F8's status:** its behavioural failure is FIXED (commit 352e2253; lli prints
11, exit 0, matching perl). What remains is the SHAPE leg only: the spec pins
`Call :Int` / `Coerce(Int -> Str)` and we produce `Num`, because the operand
arrives `Num` and `Add => 'join'` yields `join(Num, Int) = Num`. No miscompile,
a spec-vs-output disagreement about precision.

## `Array` is `Array[Scalar]` -- the element type is computed but never stored

perigrin, correcting a claim of mine that `ArgsSource` is Array-stamped and so
"has no scalar meaning": *"Array is really Array[Scalar] baring any other
narrowing ... but if we can prove that all the inputs to a function are Int then
we can assert that ArgSource is Array[Int] instead of Array[Scalar]."*

Measured, and the inference already exists.

**`_element_repr($container)` (`Analysis.pm:1523`) computes exactly this.** It
collects every element's repr -- the literal inputs AND every store's rhs
(`_element_store_values`) -- and joins them. It refuses to answer while any
contributor is untyped, deliberately: *"Answering from the literals alone while
a store is still untyped would commit to a type the store may be about to
widen."* That is `Array[T]` inference with the right soundness discipline.

**But the answer is thrown away almost everywhere.** Three call sites:

| site | what it does with the answer |
|---|---|
| `:1381` | uses it inline to stamp one Subscript, discards it |
| `:1781` | stores it -- in `%field_elem_type`, keyed by class+fieldix |
| (that map) | read back at `:1815` to stamp a Subscript over a FieldAccess |

So the ONLY persistent carrier for an element type is a side table for object
FIELDS. There is no `Array[T]` on the node, and no carrier at all for a
container that is not a field.

**And `_element_repr` cannot even see `ArgsSource`.** It answers for `ArrayRef`
and `HashRef` and returns undef for everything else (`:1529-1534`). `@_` is an
`ArgsSource` node, so the one function that could compute `Array[Int]` for a
parameter list declines to look at it.

### Why this matters for the F8 question

The chain perigrin describes -- prove every callsite passes Int, therefore
`ArgsSource` is `Array[Int]`, therefore `$_[0]` is `Int` -- has every piece
already built EXCEPT the carrier:

- the per-callsite argument reprs: `_seed_direct_call_arg_reprs` collects them
- the join over callsites: same pass, `_join_repr`
- the element-type computation: `_element_repr`
- **the place to WRITE `Array[Int]`: does not exist**

`representation` is a single scalar string per node. `Array` and `Array[Int]`
are not distinguishable in it, which is why the answer has to be recomputed at
each use or stashed in a side table keyed by something else.

### The design question this raises

A parameterized repr (`Array[T]`, `Hash[T]`) is a bigger change than the T2
spine collapse and should NOT be folded into it. But it is the same shape as the
`%Slot` tag: a container whose element reading is not recorded forces every
consumer to either guess or refuse.

Two observations, neither built:

1. **The side table already proves the pattern works.** `%field_elem_type` is
   `Array[T]` for one kind of container, spelled as an out-of-band map. Generalizing
   the carrier is a refactor of something that exists, not a new invention.
2. **`ArgsSource` is the highest-value container to parameterize**, because a
   sub's parameter list is where the whole-program join is most likely to
   succeed -- callsites are enumerable, unlike arbitrary array stores.

NOT BUILT. Recorded because the F8 shape-leg failure traces here, and because
the "Array has no scalar meaning" reading was wrong.

### The container inventory: `_element_repr` sees 2 of 10

perigrin: *"There are a bunch more types than that we care about too, Array and
Hash being the most obvious."* Correct, and the gap is wider than the
`ArgsSource` case above.

**Array and Hash are REPRS with no literal node class.** `%_REPR_LLVM_TYPE` has
`Array => '%Array*'` and `Hash => '%Hash*'` (`Context.pm:4167-4168`), distinct
from `ArrayRef`/`HashRef` (boxed `i8*`). So a value can BE an Array without ever
passing through an `ArrayRef` node -- and `_element_repr` only pattern-matches
the two literal-constructor node types.

Container-ish node classes that exist, against what `_element_repr` answers for:

| node | what it holds | `_element_repr`? | stamped in Analysis.pm? |
|---|---|---|---|
| `ArrayRef` | literal `[...]` | YES | — |
| `HashRef` | literal `{...}` | YES | — |
| `ArgsSource` | `@_` | no | 2 mentions |
| `Slice` | container + index list -> slice | no | **0** |
| `PostfixDeref` | `->@*`, `->%*` | no | **0** |
| `ExpressionList` | comma lists / call args | no | **0** |
| `ListAssign` | `my ($a,$b) = (...)` | no | — |
| `StructRef` | promoted hash-to-struct | no | **0** |
| `Ref` | `\` constructor | no | — |
| `RefType` | `ref()` -> Str | n/a (not a container) | — |

**Four of these have ZERO mentions in `Analysis.pm`** -- `Slice`,
`PostfixDeref`, `ExpressionList`, `StructRef`. Nothing in the type layer has an
opinion about them at all, so an element read through any of them starts
un-narrowed and stays that way.

`Slice` and `PostfixDeref` are the notable pair: both are element-producing
reads whose result type is exactly the container's element type. They are the
same question as `Subscript`, and `Subscript` at least gets stamped from
`%field_elem_type` when its container is a FieldAccess.

**This strengthens the carrier argument rather than changing it.** A parameterized
repr would answer for every row at once, where the current design needs a
bespoke rule per node kind -- and has one for two of ten.

**Sequencing unchanged**: still not folded into the T2 spine collapse. But the
inventory says the eventual carrier work is broader than "teach `_element_repr`
about `ArgsSource`", which is how the previous section framed it.

## T2 is a FUNCTOR, and that is the correctness criterion this plan lacked

perigrin: *"T2 operates as a kind of endofunctor between the category of Chalk
Types and the category of LLVM types."*

The functor part is exactly right and it is load-bearing. (Pedantically not
ENDO -- an endofunctor returns to the same category, `F: C -> C`; Chalk and
LLVM types are different categories, so `T2: Chalk -> LLVM`. An optimizer pass
would be the endofunctor.)

**Why it matters: a functor maps ARROWS, not just objects.**

| | Chalk | LLVM |
|---|---|---|
| objects | `Int`, `Num`, `Str`, `Scalar`, `Array` | `i64`, `double`, `%Str`, `%Slot`, `%Array*` |
| arrows | `Int <: Num` (subsumption), plus Perl's coercions | `sitofp`, a format call, box-with-tag |

Every framing in this document before now mapped OBJECTS and ignored ARROWS --
"a stamp names a candidate set, narrow it to one". That is why the object
mapping looked finished while `Coerce[Scalar -> Num]` died: `Scalar |-> %Slot`
was never the problem. The missing thing was an IMAGE FOR AN ARROW, and the tag
is what makes that arrow constructible.

### The two obligations, and one of them FAILS TODAY

**Identity: `T2(id_A) = id_{T2(A)}`.** Satisfied. `_emit_coercion` returns the
input untouched when `$from eq $to` (`Context.pm:2445`, *"nothing to bridge"*).
That early return is usually read as an optimization; it is actually the
identity law.

**Composition: `T2(g . f) = T2(g) . T2(f)`.** **VIOLATED.** Measured under
lli 15:

    Int -> Str  directly        : 123456789012345
    Int -> Num -> Str  composed : 1.23457e+14
    perl                        : 123456789012345

`_emit_coercion` enumerates arms per PAIR (`:2449` onward: Int->Num, Num->Int,
Str->Num, Str->Int, ...), so each arrow's image is written independently and
nothing checks that composites agree. `Int -> Str` formats with `%ld`;
`Int -> Num -> Str` goes through `sitofp` and formats with `%g`, which is lossy
above 2^53. Perl agrees with the DIRECT path, so **the composed route is a
miscompile**, not merely a different spelling.

This is not hypothetical: `Add => 'join'` yields Num from an Int operand
(measured on F8), so a value can acquire `Num` and reach a Str position by
exactly this route.

### What this gives the plan

A correctness criterion it did not have. "Every corpus case is green" is a
sample; the functor laws are a PROPERTY, checkable per arrow pair:

1. **identity** -- `T2(A -> A)` emits no instruction. Holds.
2. **composition** -- for every path `A -> B -> C` in the source category,
   the composed emission must agree with the direct one. FAILS for
   `Int -> Num -> Str`.

That second law is a test that can be written now, over the arm table, without
building anything else. It is a stronger check than the corpus because it is
exhaustive over pairs rather than over sampled programs.

### Where the categories genuinely differ

LLVM's types are UNORDERED and structural -- no `i32 <: i64`, no join or meet,
and `%Array*` vs `%Slot*` are simply different. perigrin: *"it's not even
Latticed types ... more akin to HM Types."* Right, in that LLVM types are
structural and equality-based: two types unify or they do not.

A functor does not require the target to share the source's shape -- it only
has to send each source arrow somewhere, preserving composition. So "LLVM is
not a lattice" is not an obstacle; it is a category with different arrows. What
it DOES mean is that Chalk's subsumption is not free in the target: `Int <: Num`
costs a `sitofp`. The lattice says a conversion is PERMITTED; LLVM says what it
COSTS.

Caution on the HM reading: it describes the SHAPE of the target types, not that
inference comes free. HM's power is unification solving for unknowns; chalk's
stamps arrive from a producer and from lattice reasoning, and there is no
unifier. Reading "HM-like" as "we get HM inference" would repeat the error of
treating the lattice as if it were LLVM's type system.

### The source category is bigger than the lattice

One correction to an earlier framing in this session. `Coerce[Str -> Num]`
(`"abc" + 1`) is NOT a subsumption arrow -- a Str is not a Num, and this is not
the inverse of `Num <: Str`. It is a lossy conversion Perl defines. So the
source category is **the subtype lattice PLUS Perl's coercion arrows**, and
`%_COERCIBLE_TO` (`Analysis.pm:174`) is a hand-maintained fragment of exactly
that arrow set -- which is precisely why it reads as debt.

UNVERIFIED: that `Coerce[Str -> Num]` yields 0 for a non-numeric string in
chalk's emitted code. Asserted from Perl semantics, not measured.

## `Num` is not `double` either -- and the backend assumes it is, ~284 times

perigrin: *"Remember how we said Int wasn't always going to map exactly to i64?
Same thing for Num:double."* And on whether anything downstream depends on it
structurally: *"That's a bug if true."*

It is true, and it is not incidental.

### The candidate set, corrected

Since **Z is a subset of R**, a `Num` whose values are all integral can be
represented by an INTEGER type. Nothing about the TYPE `Num` requires a float
REPRESENTATION. So:

    Num -> { i8..u64, float, double, Rat (num/den pair), bignum }

which is the same shape as `Int -> {i8..u64}`, and the sets OVERLAP. `i64`
serves an `Int`, and it serves a `Num` that happens to be integral. The type
says what is PERMITTED; the value set says what is ADEQUATE.

**This closes the composition failure properly.** `Int -> Num -> Str` lost
digits because `Num |-> double` forced a `sitofp`. With `Num` represented as
`i64` on that path, `Int -> Num` is a no-op and `Num -> Str` formats with
`%ld` -- identical to the direct arm, so composition HOLDS. That is a real fix,
where the `%g -> %.15g` change considered earlier only moves the cliff from ~6
digits to ~15 and leaves 2^53 intact.

### Measured: the assumption is baked into the emitter

| | count |
|---|---|
| `_repr_to_llvm_type` calls (the table) | **12** |
| literal `double` inside an `_emit` string | **23** |
| literal `i64` inside an `_emit` string | **261** |
| `double` mentions in `Context.pm` overall | 95 |

Roughly twenty sites hardcode `double` specifically for a `Num` -- constants
(`:1705`), arithmetic (`:1824`), division (`:1883`), truthiness (`:2683`),
uninitialised VarDecl (`:2727`), package-scalar globals (`:654`, `:2949`), the
Slot payload read (`:2377`, `:6273`), and most of the coercion arms.

**`Int` is worse, not better.** 261 literal `i64` emissions against 12 table
lookups. So neither axis is representation-independent today; `Num` is simply
where it became visible first.

This is the layering violation this plan already names in the abstract -- a
consumer deciding an encoding -- found concretely. `%_REPR_LLVM_TYPE` is the
declared authority for the type-to-machine mapping, and the emitter goes around
it roughly 284 times.

### Why this is not a quick fix

An emitter site does not merely name a type; it selects an INSTRUCTION.
`fadd double` vs `add i64` is not a substitution -- float and integer
arithmetic are different opcodes. So representation-independence here means
each arithmetic site dispatches on the chosen representation, not that a string
gets interpolated. That is a real refactor of the emitter, and it is the work
that makes `Num -> i64` expressible at all.

### Consequence for merges and boundaries (NOT YET MEASURED)

If `Num` may lower as `i64` at one site and `double` at another, then two
`Num`-stamped values can have DIFFERENT machine types, and every phi, call
boundary, field store and ABI return between them needs a conversion inserted.
That is the monomorphize-vs-box question arriving in a new place, and it is the
half that would fail silently rather than loudly.

**COULD NOT CONFIRM** how many merge/boundary sites would be affected -- not
measured. It must be, before anything widens `Num`'s representation.

### Sequencing

Not now. This is a larger change than the T2 spine collapse, and it depends on
knowing whether a value set is integral -- which is the interval/integrality
analysis deferred as YAGNI. That deferral now has THREE independent reasons to
be revisited: width selection for `Int`, precision adequacy for `Num`, and the
composition law above. Still deferred; the reasons are recorded so the next
person does not have to re-derive them.
