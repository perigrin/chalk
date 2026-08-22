# One IR, one type lattice — the producer and Chalk currently have two

**Date:** 2026-08-22
**Status:** MEASURED, not fixed. perigrin: *the producer lattice should be the
same as the Chalk lattice — they're talking about the same IR.*
**Blocks:** slice 4 of `2026-08-22-parameter-node-design.md` (a slurpy
`Parameter` needs an `Array`/`Hash` type the producer cannot express).

---

## The two lattices, verbatim

`lib/Chalk/Grammar/Perl/TypeLibrary.pm` (%PARENT — single parent):

    Scalar=>Any   Undef=>Scalar  Bool=>Scalar   Regex=>Scalar
    Str=>Scalar   Num=>Str       Int=>Num       DualVar=>Scalar
    Ref=>Scalar   ScalarRef=>Ref ArrayRef=>Ref  HashRef=>Ref
    CodeRef=>Ref  GlobRef=>Ref   Object=>Ref
    List=>Any     Array=>List    Hash=>List     Code=>Any      Glob=>Any

`~/dev/perl5-son/lib/SoN/IR/Stamp.pm` (%PARENTS — a DAG, multiple parents):

    None=>[Int Boolean Undef ScalarRef ArrayRef HashRef CodeRef Object DualVar Regex Glob]
    Int=>[Num]    Num=>[Str]     Str=>[Scalar]  Boolean=>[Scalar]
    Undef=>[Scalar] DualVar=>[Scalar] Ref=>[Scalar]
    ScalarRef=>[Ref] ArrayRef=>[Ref] HashRef=>[Ref] CodeRef=>[Ref]
    Object=>[Ref]  Regex=>[Ref]   Glob=>[Ref]
    Scalar=>[Unknown] Void=>[Unknown] List=>[Unknown] Unknown=>[]

## Four kinds of divergence, in increasing order of difficulty

### 1. Pure renames — one consumer, mechanical

`Bool` (chalk) is `Boolean` (producer). Measured: `Boolean` appears in chalk
exactly ONCE, in the rename table itself (`Serialize/JSON.pm:26-30`,
`%STAMP_TO_REPR`), read at :518, :520 and :555. Its own comment at :514 admits
the situation: *"says 'Boolean' where a representation says 'Bool'. Map them"*.

That table IS the defect perigrin is naming: a translation layer standing in
for an agreement.

### 2. Members present on one side only

    chalk only:     Array  Hash  Code  GlobRef  (root: Any)
    producer only:  Void   None  Unknown

Both sides need the other's. Chalk's `Array`/`Hash` are real aggregate types
the backend lowers (`%Array*`, `%Hash*`); the producer has only REFERENCES to
them, which is a different type. The producer's `Unknown`/`None` are the
epistemic points this session made load-bearing — `Unknown` as sound top for
undetermined inference, `None` as the bottom that makes joins work
(`join(Int, None) = Int`). Chalk has neither, which is exactly why `Unknown` is
never produced chalk-side: there is nowhere for it to live.

Those two findings are the same defect from opposite ends.

### 3. DIFFERENT PARENTS — this changes subtype answers

    Regex:  chalk Scalar   producer Ref
    Glob:   chalk Any      producer Ref
    List:   chalk Any (with Array/Hash beneath)   producer Unknown (childless)

This is not naming. `is_subtype(Regex, Ref)` answers differently on each side,
so any code that migrated across would silently change behavior.

### 4. DIFFERENT ROOTS, and they are not synonyms

Chalk's root is `Any`; the producer's is `Unknown`. This session established
those are DIFFERENT (TypeLibrary.pm:86-106): `Any` opts OUT of checking — a
legitimate static answer; `Unknown` is SOUND TOP — inference has not
determined the type and nothing may be done until it is narrowed. An `Any`
reaching the backend is a design fact; an `Unknown` reaching it is an inference
failure.

Chalk's lattice has `Any` as root and `Unknown` bolted on beside it with equal
bits. The producer has `Unknown` as the root and no `Any` at all. Merging the
roots is the hard part and needs a decision, not a mapping.

Also structural: chalk's is a TREE (one parent per member); the producer's is a
DAG (`None` lists eleven parents). A merge has to pick one shape.

## How it bit, concretely

Stamping a slurpy `Parameter` as `Array` in the producer dies "Unknown stamp
type: Array" — and `B::SoN` MASKS that as a silent skip, so the entire sub
vanishes from the wire with only a stderr line. Measured during slice 2.

I worked around it by not stamping and letting the loader type from the sigil.
That workaround is recorded as a workaround: it routes around a mismatch that
should not exist.

## Sequencing

Unifying is NOT a prerequisite for finishing the `Parameter` work, and should
not be smuggled into it:

- **Slice 4** needs a slurpy parameter to carry `Array`/`Hash`. The loader can
  type it from the SIGIL (which the node already carries) without the producer
  stamping anything. That is a legitimate split — the producer declares what it
  knows, the loader types what it can — and it unblocks slice 4 today.
- **The merge** is its own piece of work. Difficulty ladder above: (1) is
  mechanical with one consumer, (2) is additive, (3) changes subtype answers
  and needs per-member justification, (4) is a design decision about `Any` vs
  `Unknown` and tree-vs-DAG.

Doing (1) and (2) first would already delete the rename table and let the
producer express aggregates, which is most of the practical benefit.

## Not established

- Whether `List` (producer) and `Array` (chalk) are meant to be the same
  thing, or genuinely differ (perl's list CONTEXT vs an array VALUE).
- Whether anything depends on `Regex`/`Glob` sitting under `Scalar` rather than
  `Ref` on the chalk side.
- Whether the producer's DAG shape (multi-parent `None`) is load-bearing or an
  artifact of expressing a bottom type.
