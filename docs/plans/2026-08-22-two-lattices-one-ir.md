# One IR, one type lattice — the producer and Chalk currently have two

**Date:** 2026-08-22
**Status:** **RESOLVED 2026-08-23.** The two lattices are now one, verified by
re-measurement (see "Outcome" immediately below). perigrin's framing — *the
producer lattice should be the same as the Chalk lattice, they're talking about
the same IR* — is what landed.
**Blocks:** nothing. Slice 4 of `2026-08-22-parameter-node-design.md` is
unblocked: the producer can now express `Array`/`Hash`.

---

## Outcome — re-measured 2026-08-23, on committed HEAD

Parsing `%PARENT` (chalk `TypeLibrary.pm`) and `%PARENTS` (producer
`SoN/IR/Stamp.pm`) directly out of the source and diffing them:

    members: chalk=25  son=27  union=27
    AGREE:      25
    chalk only:  0
    son only:    2   -- None, Unknown
    DIFFER:      0

**Zero divergence.** Every shared member has an identical parent.

The two "son only" entries are the two extremal elements, and both sides agree
on their MEANING while encoding it differently:

- `Unknown` (top) — the producer lists it with an empty parent list; chalk
  omits the key and uses `'Unknown'` as a parent VALUE throughout
  (`TypeLibrary.pm:39,52-55`), documenting it at :8-16 as the sole root.
- `None` (bottom) — the producer lists `None => []`; chalk has no key at all
  and instead special-cases it in the three operations that need it:
  `is_subtype` (`:223`, bottom is a subtype of everything), `join` (`:282-283`,
  bottom is the identity) and `meet` (`:312`, bottom is absorbing).

Encoding difference, not a semantic one. Worth noting only because a naive
key-set diff reports it as a divergence — this one did, until the extremal
elements were checked by hand.

All four divergence classes catalogued below are closed:

1. **Renames** — `Bool` → `Boolean` throughout; the stamp translation table is
   deleted (chalk `c38fed6e`).
2. **One-side-only members** — `VString`, `LValueRef`, `Array`, `Hash`, `Code`,
   `Glob`, `IO`, `Format` added to chalk (`f6378e36`).
3. **Different parents** — settled per member against the paper. `Boolean`
   moved under `Str` on measurement (`!!0`/`!!1` are PVNVs with POK already
   set, unlike a plain IOK-only integer); `Regex` under `Object`; `Scalar` and
   `Void` under `List`.
4. **Different roots** — `Any` DELETED rather than reconciled. `List` covers
   the signature positions that wanted a permissive top, and `Unknown` is the
   pessimistic top for a non-answer. `Any` had been disabling type checking
   wherever it appeared, TypeScript-style.

`TypeLibrary` is now the canonical copy and carries working `join_types` /
`meet_types`; the producer's `Stamp.pm` mirrors it, with `None` as a derived
bottom rather than an enumerated 11-parent list (a real GLB defect: it gave the
wrong answer for 66 of 361 pairs).

**The three "Not established" questions at the foot of this document are
answered by that work** — see the annotations there.

---

## ORIGINAL FINDING (2026-08-22), retained for the record

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

## Sequencing (as planned — superseded by the outcome above)

**What actually happened differs from this plan, and the difference is worth
keeping.** The plan proposed doing (1) and (2) and deferring (3) and (4) as
"its own piece of work". All four were done together instead, because (4) —
the `Any`-vs-`Unknown` root question — turned out not to be a design decision
needing deliberation: `Any` was deletable outright, which collapsed the hardest
class into the easiest. Deferring it would have kept a permissive top alive
through two more slices for no benefit.

The original reasoning:

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

## Not established — ANSWERED 2026-08-23

- ~~Whether `List` (producer) and `Array` (chalk) are meant to be the same
  thing, or genuinely differ (perl's list CONTEXT vs an array VALUE).~~
  **They are DIFFERENT and both exist.** `List` is the arity-as-subset top
  (`Void`={0}, `Scalar`={1}, `List`={0,1,2,…}); `Array` is an aggregate VALUE
  and sits under it, beside `Hash`. Both are now present on both sides.

- ~~Whether anything depends on `Regex`/`Glob` sitting under `Scalar` rather
  than `Ref` on the chalk side.~~ **Nothing did.** `Regex` now sits under
  `Object` (itself under `Ref`) and `Glob` under `Unknown` — a glob is not a
  reference, and `GlobRef` is the separate member for the referenced form. No
  consumer broke.

- ~~Whether the producer's DAG shape (multi-parent `None`) is load-bearing or
  an artifact of expressing a bottom type.~~ **An artifact, and a DEFECT.**
  Enumerating `None`'s 11 parents made it a bottom only for the types listed,
  so `meet` returned the wrong answer for 66 of 361 pairs. It is now derived
  (`None => []`, handled as the bottom by `is_subtype_of`), which is both
  correct and shorter.

## Still open, and NOT closed by this work

- The `stamp` field is required on every `Value` node and defaults to
  `Unknown`, but nothing yet NARROWS an `Unknown` — there are no refinement
  passes. See `2026-08-23-goto-silently-dropped.md` for the value/control split
  that made the field honest, and `_is_narrowed` in the producer's
  `FromOptree.pm` for the predicate that will have to widen when refinement
  lands.
- `%OP_REQUIRED_REPR` and the REPRESENTATION vocabulary are a separate,
  UNORDERED namespace that merely shares member names with this lattice. That
  is by design — see `2026-08-14-representation-is-the-targets-type-system.md`
  — and unifying the two would be a mistake, not a follow-up.
