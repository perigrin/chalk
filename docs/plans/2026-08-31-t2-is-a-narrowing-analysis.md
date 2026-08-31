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

## `%_REPR_LLVM_TYPE` is T2's OUTPUT format, not the type mapping

`Context.pm:3730` maps each representation to exactly one machine type. It looks
like the design and is not (perigrin): *"This was built before we had as solid
an understanding of the problem as we do now."*

It is 1:1 precisely BECAUSE it was built assuming its input was already
narrowed. `_repr_to_llvm_type` (`:3812`) dies on undef with a message blaming
TypeInference — that die is the pre-split model showing through, assuming
something upstream already collapsed the choice and treating failure as a T1
bug. Under the split the collapse is T2's job.

The table survives as the final lookup AFTER narrowing. What does not exist
anywhere is the front half: the `Chalk type -> candidate LLVM types` relation,
and the pass that shrinks each set to one.

Two recent commits are the same discovery arriving one site at a time:
`bc943e3b` *"'type X is N bytes' over-decides -- that is why the store guard is
T2's"* and `ebdd6a23` *"a field store is coherent by encoding, not by type
equality"*. Consumers asking a question no pass exists to answer.

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
