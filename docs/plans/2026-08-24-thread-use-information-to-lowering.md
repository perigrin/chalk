# Thread use-information to lowering, instead of deciding types at the load

**Date:** 2026-08-24
**Status:** SCOPED, not built. Both prerequisites measured PRESENT.
**Origin:** perigrin, after reading the prior-art comparison —
*"Actually this is sounding like it's opening a number of cans of worms …
rather than knowing we're lowering we need to thread through the information on
how a slot is being used so that the lowering pass can make an intelligent
decision."*

## Why this is the smaller design

The prior-art pass (`2026-08-24-typed-memory-prior-art.md`) surfaced several
mechanisms. Most of them ARE cans of worms for an AOT runtime-free compiler:

| mechanism | why it is expensive here |
|---|---|
| access descriptors carrying a type | needs a type source; Perl has no declared element types |
| speculate-and-guard | V8 buys it with DEOPT; Chalk has no interpreter to bail to |
| memory slices / alias classes | a whole subsystem; nothing exists today (one global `MemStart`) |
| parameterised container types | rejected — `ArrayRef[Scalar]` is the honest Perl type |

**Backward use-propagation is the one that is cheap here**, because it needs no
runtime feedback, no deopt, no lattice change, and no new memory model. It is
TurboFan's PROPAGATE phase in isolation:

> PROPAGATE — "Traverse the graph from the end, pushing usage information
> backwards from uses to definitions ... this phase must iterate to a fixpoint
> before the next phase can begin." — `simplified-lowering.cc`

In TurboFan this is `Truncation`: what precision do consumers actually NEED.
Representation is then chosen from the type AND the backward-propagated demand
(`GetOutputInfoForPhi(Type type, Truncation use)`), which is why a `Number`
becomes `Word32` when every consumer truncates.

## Both prerequisites already exist — MEASURED

### 1. The graph is already bidirectional, and consumers name the use

Every node maintains `consumers`. Measured on real graphs:

    CASE                 NODE       stamp     consumers
    elem used in arith   Subscript  Unknown   [Add]
    elem printed         Subscript  Unknown   [Coerce]
    elem concatenated    Subscript  Unknown   [Coerce]
    elem compared        Subscript  Unknown   [NumLt]
    elem stored back     Subscript  Unknown   [Assign]

The consumer identifies the demand precisely: `Add`/`NumLt` want a number,
`Coerce` wants whatever it coerces to, `Assign` wants what the target holds.
**A backward pass has everything it needs to run.** Nothing structural is
missing.

### 2. The per-op operand demand table already exists

`Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op($ir_op, $position)`
(`TypeLibrary.pm:562`) answers exactly "what representation does this consumer
require of its operand at this position", and is already consulted by
`_operand_repr_for` (`Serialize/JSON.pm:991-993`) to insert coercions.

So the two halves are present. **What is missing is only the pass that walks
`consumers` and asks `operand_repr_for_ir_op` at each use, accumulating the
demand back to the definition.**

## What this buys, concretely

The measured defect it addresses (`2026-08-24-chalk-memory-model-baseline.md`):
a `Subscript` reaches the loader typed `Unknown`, and `_element_repr` decides
its representation by walking BACK TO THE CONTAINER'S INITIALIZERS — a
monomorphism check over the wrong domain, which is why a type-changing store
must GAP.

With use-information threaded, the lowering decision has a second, independent
input. A `Subscript` whose only consumer is an `Add` is being used as a number
whatever the initializers said. That does not by itself make a heterogeneous
array compile, but it changes WHO decides and on WHAT basis — from "guess from
the initializer" to "the use says".

## What it does NOT do, stated plainly

- It does not make `$a[1] = "x"` compile. That needs the store path to fall
  back to a boxed `%Slot` (measured: `_box_payload` already handles every
  scalar repr; only the store path refuses — baseline §4a).
- It does not add alias classes. A read of `%h` will still be ordered behind a
  store to `@a`.
- It does not establish monomorphism. It threads a DEMAND, not a PROOF.

Those remain open and are deliberately out of scope.

## Sequencing constraint, inherited from the prior art

TurboFan's phase comment is explicit that the backward pass **must reach a
fixpoint before forward retyping begins**. Chalk's existing repr-seeding passes
run forward. If a backward demand pass is added, its position relative to those
is load-bearing, not incidental — and the corpus gate is the instrument that
would catch getting it wrong.

## Open questions before building

1. **What is the demand lattice?** TurboFan's `Truncation` is a small
   semi-lattice (None / Word32 / Word64 / Float64 / Bool / Any), NOT the type
   lattice. Chalk would need its own, and reusing `TypeLibrary`'s lattice for
   it is probably a category error — the same conflation
   `2026-08-14-representation-is-the-targets-type-system.md` warns about.
2. **What happens on conflicting demands?** Two consumers wanting different
   representations is the normal case, not the exception. TurboFan's answer is
   that the producer picks one and `LOWER` inserts conversions at the
   disagreeing edges. Chalk already inserts `Coerce` nodes on edges, so the
   machinery is analogous — but the policy is undesigned.
3. **Does it subsume or complement `_element_repr`?** If the use-demand is
   authoritative, the initializer walk could be deleted. If it is only a hint,
   both run and their disagreement needs a rule.
