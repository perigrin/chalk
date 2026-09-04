# T2 is a functor: it must map ARROWS, not just objects

**Date:** 2026-09-04
**Status:** MEASURED. The object half is built; the arrow half is designed here.
**Source:** conversation with perigrin, 2026-09-04
**Supersedes the scope of:** `2026-08-31-t2-is-a-narrowing-analysis.md`, which is
correct about narrowing and silent about morphisms.
**The code:** `docs/plans/wip/2026-09-04-t2-backend-migration.patch` — the
181-site backend migration, reverted because it is the consumer half of a pass
that cannot go live yet. It applies to `d38f7f15`.

## The claim

perigrin, on why wiring T2 in took the gate from 224 to 0:

> This is why T2 is a functor rather than a simple translator … the Category of
> LLVM types isn't identical to the Chalk type Category

A functor maps objects **and arrows**. T2 as built maps objects only —
`Int ↦ i64`, `Scalar ↦ %Slot` — and silently drops every morphism.

## Measured: all five source arrows land nowhere

The source category's arrows are the subtype edges in `%PARENT`
(`TypeLibrary.pm:44-46, 81`). Under the current object map:

| source arrow | image | defined? |
|---|---|---|
| `Int <: Num` | `i64` → `double` | **no** |
| `Num <: Str` | `double` → `%Str` | **no** |
| `Str <: Scalar` | `%Str` → `%Slot` | **no** |
| `Undef <: Scalar` | `%Undef` → `%Slot` | **no** |
| `Boolean <: Scalar` | `%Boolean` → `%Slot` | **no** |

Five arrows in, zero images out. That is not a functor; it is a function on
objects with the structure discarded.

## Why the categories differ, precisely

In **Chalk**, `Int <: Num` is a SUBTYPE relation: free, no operation, an `Int`
*is* a `Num`.

In **LLVM** there is no such relation. `i64` and `double` are unrelated types
and getting from one to the other costs a `sitofp`.

**The arrow survives the mapping but CHANGES KIND: subtyping becomes
conversion.** That is the whole content of "the categories aren't identical",
and it is why a translator is the wrong shape — a translator assumes the target
has the same structure and only the names differ.

## The arrow images already exist, scattered

They are the 19 `_emit_coercion` call sites:

| source arrow | LLVM realisation |
|---|---|
| `Int <: Num` | `sitofp i64 → double` |
| `Num <: Str` | a formatting call |
| `Str <: Scalar` | box: `insertvalue` into `%Slot` |
| `Undef <: Scalar` | box |
| `Boolean <: Scalar` | box |

Those 19 sites were recorded on 2026-09-03 as T2 debt — "consumers deciding
encoding one site at a time". That reading was half right. They are not
arbitrary decisions; they are **the functor's action on morphisms, written by
hand and scattered**. The debt is not that they exist, it is that they are not
recognised as one structure.

## Two failures, one cause

**The vtable ABI check.** Refusing a method call with

    node repr=i64 disagrees with class 'C' vtable ABI return_repr=%Slot
    — neither refines the other

It asks `is_subtype(i64, %Slot)` — a SOURCE-category question, in the target.
The target has no subtyping, so the answer is always no. The right question is
*"is there an arrow, and what does it cost?"*, and the answer here is yes: a box.

**The corpus.** Gate 224 → 0, with the SHAPE leg at 0 in every section. The `ir`
blocks assert source-category facts (`:Int`, `:Scalar`), and rewriting stamps in
place destroys the domain they are written against. `F` was applied with no way
to state anything about its source.

Both are the same defect: the object map was applied where the arrow map was
needed, and the domain was thrown away.

## The design

### 1. `%CANDIDATES` is `F` on objects. Add `F` on arrows.

A second table mapping each source subtype edge to the operation that realises
it in the target:

    Int    <: Num      -> sitofp
    Num    <: Str      -> format call
    Str    <: Scalar   -> box into %Slot
    Undef  <: Scalar   -> box into %Slot
    Boolean<: Scalar   -> box into %Slot

`_emit_coercion` then becomes a LOOKUP in that table rather than 19 hand-written
branches, and the 19 sites become one.

### 2. The composition law is ALREADY TESTED, and its findings are the map

I wrote here that "nothing checks it today". **That was wrong**, and checking
before committing is the only reason it is not in this document as fact.
`ir/coercion-composition-law.t` already frames T2 exactly this way — *"T2 is a
functor from Chalk types to LLVM types: it maps objects ... AND arrows"* — and
enumerates every triple `A→B→C` against the direct `A→C`, running both under
`lli`. It is green today, on the recorded truth rather than on an aspiration.

Its design is worth copying rather than repeating: it is a CHARACTERIZATION, so
a pair that newly breaks fails AND a pair that is newly fixed also fails,
forcing the fixer to come and move the row. *"A test asserting 'all pairs
compose' would be red on 38 rows from birth and would be disabled within a
week. This one is green on the truth."*

**And it has already sorted the composition failures into three kinds**, which
is the real content and which this design should build on:

1. **Lossy by design.** Routing through `Boolean` discards everything but
   truthiness, so `Int(42)→Boolean→Str` is `"1"`. Perl agrees (`!!42 . ""` is
   `"1"`). Composition genuinely fails and SHOULD — the intermediate object is
   smaller than the source. Not a bug, and not something the arrow map can fix.
2. **The precision miscompile.** `Int→Num→Str` disagrees above 2^53, because
   `Num ↦ double` forces a `sitofp` and the mantissa cannot hold the value.
   The test's own note: *"nothing about the TYPE Num requires a float
   REPRESENTATION"* — this is a defect in the OBJECT map, reachable in real
   code because `Add` uses a repr join, so an Int operand can yield a Num
   result. This is the same round trip the 2026-09-03 define+call work hit.
3. **An outright inversion.** Every `Undef→Boolean` row differs, and there the
   COMPOSED route is right while the DIRECT arm is wrong.

Only (2) and (3) are bugs. A functor design that tried to make all three
compose would be wrong about (1).

### 3. Identity must be preserved

`F(id_T) = id_F(T)`. A coercion from a type to itself must emit nothing. The
current `_emit_coercion` has `return $input_ref if $from eq $to`, which is this
law holding by accident rather than by construction.

### 4. The refinement check moves to the source category

The vtable ABI test asks about refinement, which is a source-category notion.
Either it runs before T2, or it asks the arrow map "is there an arrow from the
node's type to the ABI's?" rather than asking `is_subtype` in the target.

### 5. The corpus needs both vocabularies

Already named in the 2026-08-31 doc and now measured as load-bearing: `ir` for
the source graph, `ir-t2` for the image. Without it the spec cannot state a fact
about either side, and the pass cannot go live.

## What is built, and what it cost to learn this

**Built and committed** (`d38f7f15` plus the brands): the pass, the object map,
the two refusal kinds (`Unknown` = inference unfinished; `List`/`None`/`Void` =
never a value type), and nominal brands making the object map INJECTIVE.

**The brands are perigrin's and they matter beyond tidiness.** Without them
`Boolean` and `Undef` both map to `i1` and the four reference types all map to
`i8*` — so `F` was not injective and a consumer holding `i1` could not tell
which object it had. LLVM named struct types are NOMINAL, verified against
lli-15:

    %Bool  = type { i1 }
    %Undef = type { i1 }
    ... extractvalue %Undef %b
    -> error: '%b' defined with type '%Bool = type { i1 }'
              but expected '%Undef = type { i1 }'

so the distinction is enforced by the toolchain rather than by convention. The
cost — an `insertvalue`/`extractvalue` pair — has a trivial inverse: perigrin,
*"even if LLVM's optimizer didn't we could trivially write a post-T2 optimizer
that did unwind them"*. The brand is a compile-time fact that has done its job
once the graph is checked.

**Reverted:** the 181-site backend migration and the loader wiring. Both are the
consumer half of a pass that cannot go live until the arrows exist.

## What is NOT established

- That the arrow table is complete. Five subtype edges are measured; whether
  every `_emit_coercion` pair reduces to a composition of them is not.
- Whether kind (2) — the `Num ↦ double` precision failure — is fixed by the
  arrow map or by the OBJECT map. The composition test argues it is the object
  map ("nothing about the TYPE Num requires a float REPRESENTATION"), which
  would make it an interval/narrowing question rather than a morphism one.
- That `Str → Scalar` and `Undef → Scalar` really are the same arrow. They both
  box, but into different tag slots, so they may be distinct morphisms sharing
  an implementation.
- Any number for what the arrow half unblocks. The 2026-09-03 doc's three
  blocked directions are the candidates, unmeasured.
