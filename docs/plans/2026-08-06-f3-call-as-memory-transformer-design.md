# Design: F3 — `Call` as a memory transformer (true `define` + `call`)

**Status:** design, awaiting review. Not a plan; no implementation.
**Supersedes the framing in:** `docs/plans/2026-07-19-bare-file-protocol-toplevel-entry.md`
§"REAL SUBS AND CALLS", which prices F3 but describes it as call *emission*.
**Type-library work belongs to:** `docs/plans/2026-07-19-runtime-mop-coerce-multimethod.md`
(milestone `runtime-mop-pilot`, 4 issues pending). This design does NOT build it.

## The spine

**An assignment is a call minus uncertainty.**

An assignment is a state transition `(Memory, Location, Value) → Memory`. A call is
`(Memory, Args…) → (Memory, Value)`. The general case is the call; assignment is the
degenerate case where the callee is a known primitive and the memory effect is
precisely known.

That gives a **lattice on effect precision**, ordered by how much we know:

```
kills nothing         pure node — no memory edge, floats freely
kills one location    a store (Assign)
kills what X kills    a call to an analyzed callee
kills everything      a call to an unknown callee        <- the honest default
```

It is the structural twin of the value lattice Chalk already has
(`Int <: Num <: Str <: Scalar`, precision decreasing upward). **`kills everything` is
the `Scalar` of memory.**

Two consequences that shape everything below:

1. **Inlining is a precision-increasing move on this lattice** — replace *kills
   everything* with the specific set the body kills. That makes the inliner an
   optimization in the strict sense: it can improve precision, never change meaning.
2. **The eight GAP sites exist because the only available precision was total.**
   Each is "callee has an effect I cannot represent at the callsite." The callsite
   never needed the callee's *specific* effects — it needed one conservative
   statement, with refinement optional.

## Why Graal's contract, not C2's

Both are Sea of Nodes; their calling contracts differ, and the difference is
load-bearing for cost.

| | C2 | Graal |
|---|---|---|
| call outputs | tuple + `Proj(Control/I_O/Memory/Value)` | one node |
| return value | a projection | the node itself (carries a `Stamp`) |
| memory effect | a projection | declared by interface + killed-location |
| control | a projection | node class (fixed) |

Verified directly at source (`InvokeNode.java`), because the research doc's Graal
claims were in the `[UNVERIFIED]` set:

```java
public final class InvokeNode extends AbstractMemoryCheckpoint
    implements Invoke, LIRLowerable, SingleMemoryKill, UncheckedInterfaceProvider

@Override
public LocationIdentity getKilledLocationIdentity() {
    return identity;   // defaults to LocationIdentity.any()
}
```

**Chalk is already shaped like Graal.** Its `Call` is a single node that is its own
value, with `control_in`. And Chalk's memory-SSA already uses Graal's exact
convention — the store node *is* the memory version, and readers take it as their
memory input (measured):

```
13 Assign    ctrl=12 inputs=[6,1]      <- the store
14 Subscript inputs=[4,5,13]           <- post-store read: memory input IS the store
```

Chalk even does this for calls *already*, once: `FromOptree.pm:2170` calls
`$sim->set_memory($call)` for `shift`/`pop`. The general rule exists, instantiated
for the two builtins where the effect was obvious, never named.

**Cost difference (measured):** C2's shape needs `Proj(Value)`, which changes what a
`Return`'s value input is, which invalidates **57 ir-block references** across four
corpus files (41 in `classes.md`). Graal's shape needs none of that.

**Honest trade-off:** C2's `Proj(Value)` would make the return type a property of a
separate node, dissolving the recursion repr-cycle described below. Graal's shape
keeps the value on the `Call`, so that cycle must still be solved. We accept the
cycle to avoid the ir-block churn.

## The design

**`Call` gains the memory contract `Assign` already has, defaulting to
kills-everything.**

- A `Call` takes a **memory input** and **is** the new memory version — identical to
  how `Assign` behaves today.
- Default kill set is *everything*. Narrowing is a later optimization, not part of
  this work.
- No new node type, no projections, no change to `control_in`, no change to `Proj`.
- `define` + `call` emission in the backend, with symbol mangling for `main::f`.
- The inliner is **disabled** for this slice (decision: perigrin, 2026-08-06);
  re-enabled later as an optimization that must prove it preserves semantics.

### Why the memory contract must ship *with* the call mechanism

`fib` has no memory effects, so `fib` alone would not exercise it. But the moment
calls stop being inlined, a callee that stores has nothing forcing a later load to
observe its writes — today that is masked because inlining threads the callee's
stores into the caller. **Shipping call emission without the memory contract is a
silent miscompile for any storing callee.**

This is the effect-chain postmortem's lesson applied in advance: *a guard on one side
of a boundary does not close a class.* The slice therefore requires a corpus case
with a **storing callee**, not just `fib`.

### The recursion repr cycle

`fib` GAPs today at `Context.pm:687` — `GAP: Add node has no representation at
lowering time` — for `fib($n-1) + fib($n-2)`. The `Add` has no repr because the
recursive `Call` has no repr, which depends on the `Add`. A cycle.

Resolution: seed a recursive call's return repr at the lattice **bottom** and widen
to fixpoint. `%_REPR_RANK` has height 3 and join is monotone, so it converges in ≤3
rounds; for `fib` (`$n` Int, `Add(Int,Int)` Int) it converges in one. The existing
`_seed_direct_call_arg_reprs` (`Serialize/JSON.pm:606`) already runs to a fixpoint at
`:727` — this extends that machinery rather than adding a new pass.

**Scope discipline:** this is *not* the operation type library. The library is
designed in `2026-07-19-runtime-mop-coerce-multimethod.md` (types reified in the MOP;
`coerce` as a vtable on `(From,To)`); its fragments today are `%OP_REQUIRED_REPR`,
`%OP_PER_POSITION_REPR`, `%_SEED_REPR`, `%STAMP_TO_REPR`, `%_REPR_RANK` and the
join/same rules, scattered across two files. F3 needs *one* narrow capability from
that future library and must not build the library.

## Slice 1 — acceptance

**`fib(10)` compiles and prints `55`, matching perl on stdout and exit status**, plus
a storing-callee case proving the memory contract.

Measured starting state:
- perl: `fib(10)` = **55**
- the producer **already emits a `main::fib` graph** — recursion is supported
  producer-side; the ceiling is entirely in chalk
- chalk today: `GAP: Add node has no representation at lowering time`

Note: `docs/plans/2026-07-19-bare-file-protocol-toplevel-entry.md` cites *"subval.t's
`sub fib`"* as the proof case. **`t/base/subval.t` does not exist in the tree.** The
claim is true — reproduced with a local `fib` — but the citation is stale and should
be corrected there.

## Verification

- **Corpus gate**, floor 157, three legs, coordinator-self-verified on committed
  HEAD. Never a subagent report.
- **ir-block churn is expected to be ZERO, for two independently-verified reasons.**
  (a) The shape leg reads the loaded IR graph (`son-corpus-wide.t:154` passes
  `$g->returns->[0]`), not the emitted LLVM — so *disabling the inliner*, a backend
  decision, cannot move it. (b) ir-blocks spell a `Call` by **attributes, not
  operands** — `%call = Call(dispatch_kind: "direct", name: "main::foo") :Int` — so
  *adding a memory input* does not invalidate them either. This matters because the
  shape leg's subset semantics tolerate extra **nodes** but NOT extra **operands on a
  matched node**; `Call` is immune only because its ir-block form is attribute-shaped.
  **Verify this empirically at implementation time rather than trusting it** — it is
  the assumption that makes this design cheap, and if it is wrong the cost returns.
- **15 of 160 corpus cases declare a sub** — the behavioral blast radius of turning
  off inlining.
- Real calls become the **default** path, so the gate exercises them everywhere. The
  alternative (calls only where the inliner declines) would ship F3 unexercised,
  which is how F2 nearly shipped silently.

## Out of scope

- **The operation type library / MOP type reification** — `runtime-mop-pilot` owns
  it, and its own pilot has a known blocker (the `ByteBuf` byte-write Level-0
  primitive).
- **Narrowing the kill set** below "everything" — a later optimization.
- **Re-enabling the inliner** — a later slice, with its own proof that it preserves
  semantics.
- **Bool / aggregate / `Scalar` argument joins.** Their join exists (`Scalar`) but is
  not *representable* — the backend explicitly refuses `repr=Scalar`. GAP, and the
  reason is representational, not lattice-theoretic.
- **A separate `I_O` chain.** C2 separates I/O from memory because I/O totally
  serializes while memory can be sliced. Chalk does not reorder effects at all;
  `control_in` already totally orders them. Splitting `I_O` out is additive if GCM
  ever needs it.

## Risks

1. **Cross-repo, no producer version pin.** `son-corpus-wide.t:17` resolves the
   producer as a live filesystem path. Execution must be serialized — one agent at a
   time — and every commit records its paired SHA in prose.
2. **The memory contract must land with, not after, call emission** (see above).
3. **60 `Call` references in `Target/LLVM/Context.pm`** are the migration surface.
   Construction is cheap (8 sites across both repos); consumption is not.
4. **The repr fixpoint is the least-proven part.** Seed-at-bottom is standard, but no
   Chalk pass does it today.
