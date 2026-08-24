# Typed memory access in TurboFan and Graal — prior art

**Date:** 2026-08-24
**Status:** RESEARCHED from primary sources (upstream HEAD, fetched 2026-08-24).
One central claim independently re-verified by the coordinator; see Provenance.
**Prompted by:** perigrin — *"let's verify how Graal and TurboFan handle this,
we need to design a real implementation"*, after establishing that Chalk
recovers a memory-resident value's type by walking back to its container's
literal initializers.
**Companion:** `2026-08-24-chalk-memory-model-baseline.md` states what Chalk
does today. Read that first; this document is the comparison.

## Provenance

The research pass marked every claim [DIRECT] / [SECONDARY] / [UNVERIFIED].
Everything below is [DIRECT] from upstream source unless marked otherwise.

**Coordinator re-verification:** I independently re-fetched
`src/compiler/turbofan-typer.cc` and confirmed the single most load-bearing
claim — that a load's typing rule is verbatim the descriptor's type field:

```cpp
Type Typer::Visitor::TypeLoadField(Node* node) {
  return FieldAccessOf(node->op()).type;
}
Type Typer::Visitor::TypeLoadElement(Node* node) {
  return ElementAccessOf(node->op()).type;
}
```

No additional logic. This is the fact the design conclusion rests on, so it was
checked rather than trusted.

Explicit gaps the researcher recorded, preserved here: V8's
`RepresentationChanger` internals, Graal's `FloatStamp` field list, and how
Graal's profiling narrows stamps in practice were all COULD NOT CONFIRM. No
[SECONDARY] corroboration of design *intent* was gathered — everything is
behavior read from code.

## THE HEADLINE — neither system does what Chalk does

> **Neither TurboFan nor Graal recovers a loaded value's type by analysing what
> was stored.** Rank 4 — "a separate analysis over stores" — is EMPTY in both.

| rank | source of a load's type | TurboFan | Graal |
|---|---|---|---|
| 1 | **access descriptor / declared type** | sole typing rule | sole typing rule |
| 2 | runtime feedback | *populates* rank 1 | secondary |
| 3 | the memory-state value | not for typing | not for typing |
| 4 | **analysis over stores** | **absent** | **absent** |

And it is not merely unused — it is **structurally avoided**. Both establish an
invariant AT THE STORE so the load may assume:

- **Graal** — `StoreIndexedNode` carries `@OptionalInput(InputType.Guard)
  GuardingNode storeCheck`. Array covariance is handled by guarding the WRITE
  and leaving the load's stamp narrow.
- **V8** — the store path emits `CheckSmi` / `CheckNumber` on the stored value
  (`js-native-context-specialization.cc`). Storing a string into a Smi-kind
  array does not widen the load; the check FAILS and deoptimizes.

**Chalk currently tries to RECOVER at the load what these compilers ENFORCE at
the store.** Enforcing is a local, composable obligation. Recovering is a
whole-program dataflow problem — and, as measured in the baseline document, it
silently breaks the moment a store disagrees (Chalk GAPs rather than
miscompiling, but only because a guard catches it).

## TurboFan: the descriptor carries BOTH axes, as separate fields

`ElementAccess` (`src/compiler/simplified-operator.h`), verbatim:

```cpp
struct ElementAccess {
  BaseTaggedness base_is_tagged;
  int header_size;
  Type type;                            // type of the element.
  MachineType machine_type;             // machine type of the element.
  WriteBarrierKind write_barrier_kind;
};
```

`FieldAccess` has 15 fields including `Type type`, `MachineType machine_type`,
`OptionalMapRef map`, `bool is_immutable`, `ConstFieldInfo const_field_info`.

**The two axes sit side by side and move independently.** From
`AccessBuilder::ForFixedArrayElement` — the type is a pure function of
`ElementsKind`:

| ElementsKind | `type` | `machine_type` |
|---|---|---|
| `PACKED_SMI_ELEMENTS` | `SignedSmall` | `TaggedSigned` |
| `PACKED_ELEMENTS` | `NonInternal` | `AnyTagged` — **type narrowed, repr not** |
| `HOLEY_ELEMENTS` | `Any` | `AnyTagged` — neither |
| `PACKED_DOUBLE_ELEMENTS` | `Number` | `Float64` |

`PACKED_ELEMENTS` is the row that matters: **a narrow type over a wide
representation**. A single conflated field cannot express it.

### Load type is deliberately WIDER than store type

Load-side only: `element_access.type = Type::Union(element_type, Type::Hole(),
...)` for holey kinds. Reads admit a hole that writes never produce.

**Chalk has independently discovered this axis** — it is the `i1 defined` bit in
`%Slot`. V8 makes it a lattice element rather than a bare bit.

## TurboFan: representation selection runs in TWO DIRECTIONS

`simplified-lowering.cc`, verbatim from the phase enum:

    PROPAGATE  — "Traverse the graph from the end, pushing usage information
                  backwards from uses to definitions ... this phase must
                  iterate to a fixpoint before the next phase can begin."
    RETYPE     — "Propagate types from type feedback forwards."
    LOWER      — perform lowering.

- **Types flow FORWARD** (def→use): what a value *can* be.
- **Truncations flow BACKWARD** (use→def): what consumers actually *need*.
- **Representation is chosen from BOTH**: `GetOutputInfoForPhi(Type type,
  Truncation use)`.

So representation is not a function of type alone. A `Number` becomes `Float64`
normally but `Word32` if every consumer truncates. **The type bounds what is
possible; the backward truncation selects what is sufficient.** Escaping
`Tagged` is exactly this mechanism.

**`Tagged` is a REPRESENTATION, not a type** — spelled `MachineType`, in a
different struct field from `Type`. (Noted because the session hypothesis paired
`Tagged` with Chalk's `Stamp`; the correct pairing is `Tagged`↔`Slot`.)

## Graal: stamps are types, and a load's stamp comes from the CONTAINER's stamp

`IntegerStamp`: `bits` + `[lowerBound, upperBound]` + `mustBeSet`/`mayBeSet`
bitmasks + **`canBeZero`** — the last exists because a range cannot express "any
int except 0". A warning that a useful lattice needs non-convex elements sooner
than expected.

`ObjectStamp`: `type` + `exactType` + `nonNull` + `alwaysNull` + `alwaysArray`.

A Graal `Stamp` is purely a TYPE. Representation is `JavaKind`, carried
separately — Graal never puts both in one object the way `FieldAccess` does.

**The mechanism closest to what Chalk needs** — `LoadIndexedNode.createStamp`:

```java
ResolvedJavaType type = StampTool.typeOrNull(array);
if (kind == JavaKind.Object && type != null && type.isArray()) {
    return StampFactory.object(TypeReference.createTrusted(assumptions,
                                                          type.getComponentType()));
}
```

**The element's type is a PROJECTION of the container's type** — not a walk over
initializers, not a walk over stores. `LoadFieldNode` is the degenerate case:
`StampFactory.forDeclaredType(field.getType())`.

There is **no "stamp of what is in memory"**. The memory graph governs ordering
and elimination, never typing.

## Graal: memory slices are COARSE, and that is affordable

`NamedLocationIdentity.getArrayLocation(JavaKind)` — **one LocationIdentity per
element KIND, not per array.** Every `int[]` in the program shares one slice.
Nine total. Fields are finer (per resolved field), and immutability is a
property of the identity itself.

> **Graal can afford coarse array slices precisely because slices carry NO type
> information.** They answer only "may this store clobber this load?" Typing is
> answered independently by the declared type.

That decoupling is the transferable idea: alias analysis and typing are
different mechanisms, each allowed to be sloppy in a different direction. The
baseline document measures Chalk's slices as coarser still — ONE global memory
value, so a read of `%h` is ordered behind a store to `@a`.

## What this means for Chalk — and it CONFIRMS the reframing

perigrin's correction (baseline §4a) was that `ArrayRef[Int]` is not a type but
an **optimization discharging a proof obligation**, since every Perl array is
honestly `ArrayRef[Scalar]`. The prior art supports this directly:

- V8 speculates a NARROW type (`SignedSmall`) for a genuinely dynamic element,
  then **guards the speculation at every write**. The compiler never reasons
  about a heterogeneous array — it compiles a homogeneous one and bails if
  reality disagrees.
- Graal's narrow stamps are underwritten by Java's static typing; where
  covariance breaks that, a **store guard** restores it.

Both are "assume narrow, enforce at the store". Neither is "infer from what was
stored", which is what Chalk does.

### Directly adoptable (AOT-safe, no runtime feedback needed)

1. **Give the access site a descriptor carrying BOTH a type and a
   representation**, and make the load's typing rule return the descriptor's
   type. This deletes the initializer walk-back entirely. The intelligence
   moves to whoever BUILDS the descriptor.
2. **Derive the element type from the CONTAINER'S type** (Graal's
   `getComponentType()`), not from the container's initializers. Walking
   initializers is a proxy for the container type; make the container type
   first-class and the proxy disappears.
3. **Enforce at the store, not recover at the load.** If an array is optimized
   to `Int`, `$a[1]="x"` must be rejected or coerced AT THE STORE — a local
   obligation dischargeable during lowering.
4. **Bidirectional representation selection.** PROPAGATE→RETYPE→LOWER needs no
   runtime feedback and is how you escape a boxed representation. Note the
   sequencing constraint: backward propagation must reach a fixpoint BEFORE
   forward retyping.
5. **Keep alias disambiguation separate from typing**, and let it be coarse.
6. **Let the load type be wider than the store type** — Chalk's `i1 defined` is
   already this; formalize it as a lattice element (`Undef`) rather than a bare
   bit.
7. **Immutability as a property of the location.** For `my @a = (1,2,3)` never
   subsequently stored to, Chalk's current initializer-walk IS sound. Mark that
   case explicitly rather than relying on it universally — this makes today's
   mechanism a legitimate special case instead of a general rule that breaks.

### NOT adoptable — depends on what Chalk lacks

- **Type feedback / maps as the source of descriptor types.** A runtime
  artifact. Chalk must get them from inference.
- **Deoptimization as the soundness backstop.** Every V8 narrowing is
  underwritten by bailing to the interpreter. **Chalk has no interpreter to bail
  to, so every narrowing must be either PROVEN or guarded by an emitted runtime
  branch.** This is the biggest constraint transfer: V8's aggressiveness is
  purchased with deopt, at a price Chalk cannot pay.
- **Graal's `forDeclaredType` as a complete answer.** Works because Java field
  types are invariant. Perl has no declared element types.

### The modified form: speculate-and-guard WITHOUT deopt

Where Chalk can prove homogeneity, emit the narrow path. Where it cannot, emit
a **runtime branch** — narrow fast path, boxed slow path, both in the emitted
code — rather than a bailout. Code size instead of a deopt mechanism. The store
is still the right place for the check.

This also resolves the baseline document's most actionable finding: `$a[1]="x"`
should fall back to a boxed `%Slot` rather than GAP. `_box_payload` already
handles every scalar repr; only the store path refuses.
