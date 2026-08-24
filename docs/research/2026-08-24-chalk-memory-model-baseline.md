# Chalk's memory model, measured — the baseline a typed-memory design must beat

**Date:** 2026-08-24
**Status:** MEASURED. Local facts only. Prior-art comparison is a separate
in-flight research pass; this document deliberately states what CHALK does so
that research can be evaluated against something concrete rather than against
recollection.
**Prompted by:** perigrin — *"Slot is I think a hack around the fact we haven't
dealt with SSA and memory lookup values (references, array index values, hash
key values)"*, and then *"let's verify how Graal and TurboFan handle this, we
need to design a real implementation."*

## 1. `Slot` is a representation, not a type — and it is type ERASURE

`%_REPR_LLVM_TYPE` (`Target/LLVM/Context.pm:3045`):

    Slot     => '%Slot',      # { i1, i64 }: the uniform field/element cell

`{ i1 defined, i64 payload }`. **No field records what the payload IS.**
`%Array` is `{ i64, i64, %Slot* }` — an array is literally an array of Slots.

`Slot` does not appear in `TypeLibrary` at all (measured: zero occurrences). It
is not a lattice member and cannot be one. Its closest analogue in the type
vocabulary is `Undef`, which IS a lattice member — the two overlap in meaning
for the not-present case but sit on different axes.

`_box_payload` (`Context.pm:5506`) takes the source `$repr` as a PARAMETER and
boxes accordingly (a `Str` is malloc'd into a `%StrPair` and the pointer
stored). Nothing about which repr was boxed survives into the cell. So the type
must be RECOVERED on the read side, externally.

## 2. The recovery mechanism is static analysis of the INITIALIZER

`_element_repr` (`IR/Serialize/JSON.pm:1673`) walks back to the container node
and reads the reprs of its INPUTS — the literal initializers — taking the
widest. For a `HashRef` it takes the odd positions (the values).

That works exactly as long as the container is a compile-time literal whose
initializers are visible in the graph. It models no stores.

## 3. Which is why a type-changing store is a GAP — verified end to end

    my @a = (1,2,3);
    $a[1] = "x";
    print $a[1], "\n";

perl prints `x`. Chalk REFUSES, and the message states the mechanism exactly
(`Context.pm:1996`):

> GAP: Assign(Array-lvalue) rhs repr=Str cannot be stored in an i64 Slot
> payload — the container's element repr is inferred from its literal
> initializers only, so a type-changing store would read back at the old repr.

**This is a GAP, not a miscompile** — the guard is present and correct. But the
refusal is the price of the missing mechanism: the compiler cannot compile an
ordinary Perl program because a value's type is not carried through memory.

Measured for contrast, the loader's `Subscript` typing DOES work on every
literal-container shape, including the subtle one:

    array elem const idx   Unknown -> Int
    array elem OOB         Unknown -> Slot     (via _static_miss)
    hash elem              Unknown -> Int
    arrayref elem          Unknown -> Int

## 4. There is ONE global memory value — no alias classes at all

Measured: zero occurrences of `alias`, `LocationIdentity` or memory `slice` in
`lib/Chalk/IR/` or the LLVM target. There is a single `MemStart` and one
undifferentiated chain.

The consequence, measured on `my @a=(1,2); my %h=(k=>1); $a[0]=9; $h{k}`:

    Assign#4                                  <- the store to @a
    Subscript(HashRef#3, key, Assign#4)       <- the read of %h

**A read of `%h` takes the store to `@a` as its memory input.** Those two
cannot alias — different containers, different kinds — yet the read is ordered
behind the store. Same shape across two independent arrays.

This is precisely the position Click and Paleczny described in 1995 and flagged
as too coarse, naming memory slicing as future work (see
`docs/research/2026-08-02-effect-ordering-prior-art.md` §2, `[DIRECT]`). Chalk
is at the 1995 position with the 1995 caveat unaddressed.

## 4a. THE TYPE LAYER CANNOT EXPRESS THE RELATION — measured

perigrin, reframing: *"We're operating up a layer from representation, but we
need to provide the lowering system a chance to know 'hey this value is gonna
be looked up as part of that value over there'."*

That is a TYPE-layer statement, and a containment relation: an element's type
IS the element type of its container's type. Not "this loads from that memory",
which is the ordering edge that already exists.

Measured — container stamps, against the element stamps of their inputs:

    CASE             CONTAINER  stamp        element stamps
    array of Int     ArrayRef   ArrayRef     Int,Int,Int
    array of Str     ArrayRef   ArrayRef     Str,Str
    array mixed      ArrayRef   ArrayRef     Int,Str
    hash of Int      HashRef    HashRef      Str,Int
    hash of Str      HashRef    HashRef      Str,Str

**An array of Ints and an array of Strs have the IDENTICAL type.** Every
container stamps as bare `ArrayRef`/`HashRef` regardless of contents.

So the relation perigrin describes has nowhere to live. The element types exist
in the graph only as INPUTS TO THE CONSTRUCTOR NODE, which is exactly why
`_element_repr` must walk back to them — there is no type to ask.

**The lattice has no parameterised types.** `ArrayRef` is a leaf, not
`ArrayRef[T]`.

### CORRECTION — the bare stamp is RIGHT, and `ArrayRef[Int]` is an OPTIMIZATION

perigrin, on the above: *"Perl doesn't optimize Array of Ints — everything is
an Array of Scalars. Lowering to Array of Ints then is an OPTIMIZATION pass
once we can guarantee that a given array only ever has Ints in it."*

That inverts the framing, and it is correct. Perl has ONE array kind and it
holds SVs. **The honest type of every Perl array is `ArrayRef[Scalar]`.** So
the bare `ArrayRef` stamp is not missing a parameter — it is already correct at
the honest width, and "an array of Ints and an array of Strs have the identical
type" is a true statement about Perl rather than a defect.

`ArrayRef[Int]` is therefore not a type the frontend DERIVES. It is a **proof
obligation an optimization DISCHARGES**: valid exactly when the array
provably only ever holds Ints, over its whole lifetime.

**Which reveals what `_element_repr` actually is.** It ends in
`_join_repr(@reprs)` over the container's initializers
(`Serialize/JSON.pm:1701`) — a MONOMORPHISM CHECK wearing type inference's
clothes. It answers "are all the initializers the same width?", which is the
right question, over the wrong domain: initializers are not the whole lifetime,
because stores are invisible to it.

So the type-changing-store GAP is not a missing feature. It is the guard
correctly refusing where the optimization's premise is unproven — the
soundness condition is doing its job, and the message says exactly this:
*"the container's element repr is inferred from its literal initializers only"*.

**This relocates the design question.** It is not "how do we express
`ArrayRef[Int]` in the lattice". It is:

1. What is the ANALYSIS that proves an array is monomorphic over its whole
   lifetime — all stores, all aliases, all calls that receive it?
2. Where does the RESULT live? Not in the honest type (`ArrayRef[Scalar]` is
   what the type says). Candidates: a refinement on the node, a separate
   analysis result keyed by allocation site, or exactly the "stamp" idea from
   C2/Graal — an abstract-interpretation fact ABOUT a value, distinct from its
   type. See `2026-08-23-goto-silently-dropped.md` and
   `SoN::IR::Value`'s comment on why `Stamp` is named as it is.
3. What happens when the proof FAILS? The array stays `ArrayRef[Scalar]` and
   its elements are boxed Slots — which is what `%Slot` already is. **`Slot` is
   then not a hack but the CORRECT unoptimized representation**, and the
   current defect is narrower than it appeared: not that `Slot` exists, but
   that the unoptimized path GAPs instead of falling back to it.

That last point is the most actionable thing measured today: `$a[1] = "x"`
should lower to a boxed heterogeneous array, not refuse. **The fallback
representation already exists and is nearly complete** — verified:

- `_box_payload` (`Context.pm:955-1041`) has working arms for `Int`, `Num`,
  `Str` (malloc'd into a `%StrPair`, pointer stored), `Boolean`, `Undef` and
  `Scalar`. A `%Slot` can already hold any scalar type.
- The refusal is in the STORE path (`Context.pm:1991-1999`), which calls
  `_box_payload` for `Int|ArrayRef|HashRef|CodeRef|Object` and dies for
  everything else — including the `Str` and `Num` that `_box_payload` handles
  three functions away.

So the store is not blocked by an inability to box. It is blocked because the
READ side would misinterpret the cell: reads still type from initializers, so a
`Str` stored into an `Int`-inferred array reads back as an `Int`. The GAP is
guarding the read, from the write.

The comment immediately above the refusal names the fix precisely
(`Context.pm:1988`): *"inference joins stores as well as literals, this must
stay a GAP."* — i.e. once the monomorphism analysis considers stores, the guard
can lift. That is the same analysis §1 above asks for, seen from the other end.

**Sequencing this suggests:** the analysis (does this array stay monomorphic
over all stores?) is the single prerequisite. With it, the store path stops
refusing AND the read path stops guessing — one fact serves both, and the
heterogeneous case falls back to boxed `Slot`s that already work.

Whether the monomorphism fact is carried as a Graal-style `Stamp` refinement or
a TurboFan-style access descriptor is what the prior-art pass should
discriminate — but both are now understood as ways to record an OPTIMIZATION's
proof, not as ways to state a type.

## 5. What a design has to answer

Stated as questions rather than answers, because the prior-art pass is still
running and these should be judged against it:

1. **Where does a loaded value's type come from?** Chalk: static analysis of
   the container's initializer. The alternatives are a type carried in the
   access descriptor, a type carried by the memory state itself, or a runtime
   check. Only the first two are available to an ahead-of-time, runtime-free
   compiler.
2. **Can memory be split by location?** Without it, every store orders against
   every read, and the type question is unanswerable per-location because there
   is no per-location anything.
3. **Does `Slot` survive?** If a cell records its own type, `Slot` becomes a
   tagged union with a discriminant rather than a bare `{i1,i64}` — a different
   thing with the same name. If the type lives in the access descriptor
   instead, `Slot` stays as-is and the descriptor does the work.
4. **What about references?** `$r->[1]` where `$r` came from elsewhere has no
   visible initializer at all. Measured: `sub f { $_[0]->[1] }` produces no
   `Subscript` node in the callee graph at all — the shape is not built. This
   is the case where an initializer analysis has nothing to analyse.

## Provenance

Everything in §§1-4 is measured on committed HEAD (chalk `da45c764`, producer
`10f9e2e`) by running the code, not by reading it. The line citations were
checked individually. §5 asserts nothing.
