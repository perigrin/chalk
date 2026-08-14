# Representation is the lowering target's type system, not a second lattice

**Date:** 2026-08-14
**Status:** DESIGN. Nothing built. The measurement below was run on a scratch
branch (`measure-always-coerce`, deleted) and is reproducible in ~15 minutes.
**Predecessor:** `docs/plans/2026-08-13-node-type-and-typelibrary-as-authority.md`
(this supersedes its steps 2-4; step 1 `is_fixed` is landed and unaffected)
**Landed on the way here:** `075e5f9c` (`print @array` corpus case, floor 194->195),
`005ee5e6` (signature-driven coercion, `%_STR_CONTEXT_OPS` deleted, floor 195->196)

## The thesis

Chalk has TWO type systems that share a namespace, and conflating them has now
produced three separate wrong designs in a single session -- two of them mine,
each caught only by measurement.

| | type lattice | representation |
|---|---|---|
| question | what Perl value is this? | what machine layout holds it? |
| authority | `TypeLibrary::%PARENT` | the LOWERING TARGET |
| ordered? | YES -- `Int <: Num <: Str <: Scalar` | NO |
| `is_subtype` meaningful? | yes | **no** |
| `Slot` | does not exist | `{i1, i64}` |
| `Scalar` | polymorphic supertype | 14 backend branches |

They overlap in SPELLING -- `Int`, `Str`, `Num`, `Bool` name members of both --
so `is_subtype` answers questions about representations without complaint, and
answers them WRONG.

### Representation is not a lattice. It has no order at all.

Measured against LLVM 15 (`lli`, `llvm-as`/`llvm-dis`), three probes:

1. `fadd double %a` where `%a` is `i64` -> REJECTED: "defined with type 'i64'
   but expected 'double'".
2. `%Derived*` passed where `%Base*` is expected (C-style inheritance, the
   classic structural-subtyping case) -> REJECTED; needs an explicit `bitcast`.
3. `double*` passed where `ptr` is expected -> ACCEPTED. This LOOKS like
   subtyping and is not: `llvm-as` + `llvm-dis` normalises BOTH `i8*` and
   `double*` to `ptr`. They are the SAME type under opaque pointers, with
   pointee information erased. Equality, not subsumption.

**LLVM's type relation is equality.** There is no `<:`. So asking whether one
representation is a subtype of another is not merely false -- it is a
meaningless question, and any code shaped that way is wrong by construction.

I earlier called this a "representation lattice". Wrong word, and the wrong
word is what invited `is_subtype` in. It is a SET of machine types plus a
partial conversion relation.

## The rule

    Coerce(A -> B)  unless  type_for(A) == type_for(B)

`type_for` is the map from representation to the target's machine type. It
already exists: `_repr_to_llvm_type`, `Target/LLVM/Context.pm:2606`.

Checked against every case that broke the two failed attempts:

| from -> to | type_for | coerce? | case |
|---|---|---|---|
| Int -> Str | `i64` != `i8*` | YES | S13 `length($n)` |
| Int -> Num | `i64` != `double` | YES | `3/2` is 1.5 (the `sitofp`) |
| Bool -> Str | `i1` != `i8*` | YES | `print $bool` |
| Str -> Str | `i8*` == `i8*` | no | |
| Bool -> Undef | `i1` == `i1` | **no** | both are `i1` |

The rule gets all of them right, including the two that killed the earlier
designs. `Bool -> Undef` is the interesting row: two DISTINCT types needing NO
conversion because they share a representation. Subtyping could never derive
that -- they are siblings under `Scalar` -- and only `type_for` sees it.

### Three questions, three authorities

The current code answers all three with one overloaded vocabulary:

| question | correct authority | current state |
|---|---|---|
| what widens to what? | type lattice (`is_subtype`) | CORRECT -- `_join_repr` |
| does this layout fit? | `type_for` + equality | `_conforms` uses repr-name `eq`; correct by coincidence |
| can I convert A to B? | the target's instruction set | `%_COERCIBLE_TO`, hand-copied -- WRONG LAYER |

`_conforms` (`TypedInvariant.pm:57`) using `eq` is not a shortcut to be
replaced by `is_subtype` -- and this doc exists partly to stop that change
being made a third time. Measured: every disagreement between `eq` and
`is_subtype` on `%OP_REQUIRED_REPR` has subtyping ACCEPTING what `eq` rejects,
and each acceptance is a miscompile:

    Concat Int/Num  -- would stop requiring the Stringify an (i8*,len) pair needs
    Divide Int      -- would stop requiring the Coerce(Int->Num) that makes 3/2 be 1.5
    Length Int/Num  -- would un-lower the S13 coercion just landed

`son-corpus-wide.t`'s own floor message already says this: "Concat stays exact
... and Divide stays exact". The branch had rejected the change, with reasons,
before I proposed it.

## The design

    PRODUCER / LOADER      insert Coerce(A -> B) whenever A != B,
                           unconditionally. A GENERIC target whose type_for is
                           the IDENTITY: every repr is its own machine type, so
                           nothing is ever equal and every difference coerces.

    TARGET                 an optimization pass REMOVES each Coerce(A -> B)
                           where that target's type_for(A) == type_for(B).

The IR becomes maximally explicit and target-INDEPENDENT; each target
subtracts. This inverts what `005ee5e6` built, where the IR asked the backend's
permission before minting a node -- `%_COERCIBLE_TO`'s own comment says "this
pass must not mint a Coerce the backend cannot lower", which is an IR pass
reasoning about an instruction set.

### Why the asymmetry matters

Repr mentions per target, measured:

    Target/LLVM/Context.pm        463
    Bootstrap/Perl/Target/C.pm      2
    Bootstrap/Perl/Target/Perl.pm   1

The Perl target would delete essentially EVERY coercion -- an SV is
polymorphic, so its `type_for` is very nearly constant. LLVM keeps nearly all
of them. Same IR, different removal pass. A fixed coercion set in the loader
cannot serve both, which is exactly why the loader ended up with a hand-copy of
LLVM's instruction set.

## MEASUREMENT: unconditional insertion, run on the corpus

Scratch branch, both guards commented out (`_coercion_exists` and
`accepts_operand_repr`), nothing else changed:

    gate-green=183  behavior=183  shape=196  invariant=196  worklist=13

Three results, all of which bear on whether this is safe:

**1. The corpus did NOT need rewriting.** `shape=196` and `invariant=196`, both
unchanged and still perfect. All 196 `ir` blocks absorbed the extra `Coerce`
nodes with no edits. The rooted-walk matcher already sees through them. The
anticipated "rewrite 196 corpus cases" cost is ZERO on that axis.

**2. Zero silent miscompiles.** Every one of the 13 failures is a named GAP at
the lowering boundary. The single non-GAP failure is the floor assertion itself
(196 > 183). So the target removal pass is an OPTIMIZATION, not a correctness
requirement -- `_lower_coerce` already returns its input unchanged when
`$from eq $to` (`Context.pm:1172`), so over-insertion is already correct in the
LLVM target today, merely unoptimised.

**3. All 13 failures are ONE shape:** `Coerce[ArrayRef->Str]` /
`Coerce[HashRef->Str]`, every one from `scalar @a` / `scalar %h` reaching a
`Length` node.

That third result is not a cost of the design. It is the design SURFACING a bug
the current code hides.

## The bug it surfaces: `Length` is two operators

Measured against perl:

    length(@a)  on a 3-element array  ->  1, NOT 3
                (@a goes to scalar context yielding 3, then length("3") is 1)

    scalar(@a)  ->  not an operator at all; its optree is a bare
                    `<0> padav[@a] s`, the array in scalar context

So perl's `length` is STRICTLY Str, and `scalar @a` is a different construct
entirely. Chalk's producer nonetheless mints a `Length` node for BOTH
(`FromOptree.pm:1362`: "scalar context and yields the element count (a
Length)"). One IR node standing for two unrelated source constructs is why its
operand set LOOKS polymorphic (`[Array ArrayRef Hash HashRef Str]`, which is
what `TypedInvariant.pm:31` records).

TypeLibrary is RIGHT that `length => arg_types => ['Str']`. The NODE is
overloaded.

`%IR_OP_ACCEPTED_REPRS` (landed in `005ee5e6`) is a bridge over exactly this,
and it is the thing suppressing all 13 failures. Under generic insertion the IR
correctly says "this position wants Str, you gave an ArrayRef, here is the
conversion" and the backend correctly refuses, because that conversion is
meaningless.

**The honest fix is to split the node** -- `Length`(Str, byte length) from
`Count`(aggregate, element count) -- the same split `$#a` already received for
being Length-1 rather than Length. That is a producer change.

Contrast `reverse`, which IS genuinely one generic operator: measured, `<@>
reverse` returns "321" in scalar context and (3,2,1) in list context, one op
dispatching on its own calling context. `length` is not that.

## Sequencing

1. **Split `Length` / `Count` in the producer.** Blocks everything else; the 13
   GAPs are all this. Corpus cases exist already and will flip GREEN.
2. **Make `type_for` TOTAL.** Measured coverage TODAY is 5 of 14 reprs:

       MAPPED  Int Num Bool Str Undef
       DIES    Slot Scalar Array Hash ArrayRef HashRef CodeRef Object Regex

   `Object` is on the producer's own wire format (`%STAMP_TO_REPR`), so a
   stamped `Object` reaching machine-type selection CRASHES rather than GAPping.
   The machine types already exist as emitted text in `Target/LLVM.pm:1210-1213`
   (`%Slot = type { i1, i64 }`, `%Array`, `%Hash`, `%StrPair`) -- they are simply
   not reachable from the function that is supposed to return them. This step is
   mostly CONNECTING, not inventing.

   It will also surface that `Str -> i8*` is a lie by omission: a Str value is
   an (i8*, len) PAIR (`%StrPair`), with the length carried in the
   `_str_len_table` side table exactly as Bool/Undef ride in
   `_undef_defined_bit`. `type_for` being non-injective (`Bool` and `Undef` both
   -> `i1`) is load-bearing, not a wart.
3. **Make `type_for` a target METHOD**, not a private sub in one backend's
   Context. Three targets exist and answer differently.
4. **Generic unconditional insertion**; delete `%_COERCIBLE_TO`,
   `_coercion_exists`, and `%IR_OP_ACCEPTED_REPRS`.
5. **Target-specific removal pass** as pure optimization, gated on step 4 being
   green WITHOUT it.

## Filed separately: checking for `Constant` by identity is a bug

8 sites test `operation eq 'Constant'`:

    Target/LLVM/Context.pm:5045, :5047
    IR/Serialize/JSON.pm:650, :652, :1224, :1428, :1490, :1519

These ask a VALUE-DEFINITION question ("is this literally a Constant node?")
where they should ask a TYPE-FLOW question ("what does this position carry?").
A `Coerce` wrapping a `Constant` still carries a constant; the check cannot see
through it.

Measured: NONE of them broke under unconditional insertion -- the coercions
landed on operands these sites do not inspect. So this is LATENT, not blocking,
and it is a pre-existing bug independent of this design. The corpus shape
matcher already implements the see-through-transparent-wrappers rule that these
sites lack.

## What this supersedes

The predecessor plan's steps 2-4 assumed the registries were duplicates of
TypeLibrary to be deleted. Measured, that is true of SOME (`%_STR_CONTEXT_OPS`
was a degenerate, position-blind re-derivation of `arg_types`, and is now
deleted) and FALSE of others: `%OP_REQUIRED_REPR` is a
representation-conformance table with a genuinely different job, and
`%MUTABLE_READ_OPS` / `%PURE_DESCEND_OPS` are neither -- they encode EDGE KIND
(control vs data), a third question again, and they are what block
`docs/plans/2026-08-13-post-merge-statement-ownership.md`.

## Error log (the pattern, not the incidents)

Recorded because the same mistake recurred three times in one session in three
disguises:

1. Proposed tightening `print`'s `arg_types` to Str. Would have rejected
   `print @a` / `print undef` / `print $ref` at parse time; no corpus case
   covered it. Caught by writing the case.
2. Gated coercion on `is_subtype($repr, $want)`. Un-lowered SIX cases whose
   Bool/Slot operands print fine. Caught by the gate.
3. Exempted `Str` wholesale instead. Un-lowered EIGHT more by stringifying the
   ArrayRef operand of `scalar @a`. Caught by the gate.

Each time the error was reaching for the TYPE lattice to answer a
REPRESENTATION question, and each time it was caught by measurement rather than
by review. The design in this doc exists to make that class unrepresentable:
if representation questions can only be asked of `type_for`, `is_subtype`
cannot be reached for.
