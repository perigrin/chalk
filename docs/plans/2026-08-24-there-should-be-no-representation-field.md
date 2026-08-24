# There should be no representation field — measured

**Date:** 2026-08-24
**Status:** MEASURED, not acted on. This document makes the case empirical; it
does not propose a migration.
**Origin:** perigrin — *"This brings me back to there should be no
representation field. Representation is just the type of the lowering target."*

This is the same claim recorded on 2026-08-21
(`2026-08-21-type-vs-representation-seams.md`, "THE ARCHITECTURAL FINDING"):

> Representation is really just changing the type from a Chalk type to a
> Backend (LLVM) type ... so Node(Int) becomes Node(i64) or Node(u64).

It was measured and agreed then. The code still has two fields. This document
records what the two-field design is COSTING, which is the argument for acting
rather than re-agreeing.

## 1. There are not two fields in practice — one is inert

`Chalk::IR::Node` declares both (`:20` and `:56`). Their usage:

| field | writes | reads |
|---|---|---|
| `stamp` | **0** | **1** (inside a comment) |
| `representation` | 21 | 69 |

`set_stamp` is defined at `Node.pm:212` and called from nowhere in `lib/`. So
the "type axis" on the chalk side is a declared field, a setter, a reader, and
a 54-line rationale class (`Chalk::IR::Value`) over storage nothing writes.

## 2. The representation vocabulary IS the type vocabulary, plus one name

Parsed from the two authoritative tables — `%_REPR_LLVM_TYPE`
(`Target/LLVM/Context.pm:3036`) and `%PARENT`
(`Grammar/Perl/TypeLibrary.pm:17`):

    type lattice members:   27
    representation members: 12

    IN BOTH (11):
      Array, ArrayRef, Boolean, CodeRef, Hash, HashRef,
      Int, Num, Object, Str, Undef

    REPRESENTATION ONLY (1):
      Slot -> %Slot

**Eleven of twelve representation members are lattice type names.** There is no
separate representation vocabulary — there is the type vocabulary, plus `Slot`,
stored in a duplicate field.

That is the measured form of the claim. Not "two axes that happen to overlap",
which is how the seams document hedged it, but one vocabulary with a
target-specific extension of size one.

`Slot` being the sole exception is itself consistent: it is the machine layout
of a memory cell (`{ i1 defined, i64 payload }`), the one thing with no
type-level meaning. Everything a TYPE can say has a name in both tables.

### The 16 type-only members are the lowering pass's job

    Code, DualVar, Format, Glob, GlobRef, IO, LValueRef, List, None,
    Ref, Regex, Scalar, ScalarRef, Unknown, VString, Void

These have no machine encoding because they are the WIDE and ABSTRACT end of
the lattice. Eliminating them is precisely what a lowering pass does. Today
that work shows up instead as **14 scattered `repr eq 'Scalar'` refusals** and
**30 `_require_repr` assertions** in the target — the audit's phrase for this
was "the signature of a missing prior pass".

## 3. The loader does not load the types — it CONSUMES them

`Serialize/JSON.pm:548-549`, the whole of the type axis's treatment:

    if (defined $nd->{stamp} && $LOWERABLE_STAMP{ $nd->{stamp} }) {
        $node->set_representation($nd->{stamp});
    }

A wire TYPE is assigned into the REPRESENTATION field. Measured over 8
programs, 71 wire nodes:

    carrying a stamp:    45 (63%)
      -> kept as a repr: 39
      -> DROPPED:         6   (ArrayRef x2, HashRef x1, Unknown x3)
      -> kept as a type:  0

The 6 dropped are the stamps whose names are NOT in the six-member
`%LOWERABLE_STAMP` (`Boolean Int Num Object Str Undef`). That gate is exactly
the overlap from §2 — **the loader can only accept a type whose name also
happens to be a valid representation.** Anything else falls on the floor.

`ArrayRef`/`HashRef` being among the dropped is the thread back to the memory
work: those are the container types whose element types `_element_repr` then
reconstructs by walking back to literal initializers
(`2026-08-24-chalk-memory-model-baseline.md`). The producer knew; the loader
dropped it; a later pass re-derives it structurally.

## 4. What this explains

The alignment audit (`2026-08-24-two-ir-architecture-alignment.md`) found 19
`set_representation` sites split **18 loader : 1 target**, and described the
loader's as "an iterate-to-fixpoint dataflow analysis smeared across a
deserializer".

That is the direct consequence of having a second field. Because
`representation` exists separately from `stamp`, the conversion between
vocabularies has no natural home — so it happens at DESERIALIZATION TIME,
node by node, in the one place that touches every node. With a single field
whose vocabulary is rewritten by a pass, the loader's job would be to load,
and the rewrite would be the pass.

## 5. What this document does NOT claim

- **Not** that the fix is a mechanical rename. `Slot` has no type-level
  meaning, and the 16 type-only members have no encoding — a unified field
  must still answer what those become, which is the lowering pass's actual
  content.
- **Not** that `Chalk::IR::Value` was wasted. Its argument (value-ness is
  structural, the predicate is `isa` not `can`) is independent of which field
  it guards, and the producer side USES it — `SoN::IR::Value` requires a stamp
  and defaults it to `Unknown` (perl5-son `54bcb9e`). The asymmetry is that
  chalk never writes the field it was built for.
- **Not** a migration plan. Sequencing is the owner's call. The measurements
  above are offered as the case that this is a real cost rather than a
  stylistic preference.

## Reproduction

All figures are from committed HEAD (chalk `7e84ea75`, producer `10f9e2e`),
produced by parsing `%_REPR_LLVM_TYPE` and `%PARENT` out of the sources and by
running the producer over 8 programs and diffing wire stamps against loaded
fields. Field usage counts are `grep -rn` over `lib/` excluding the declaring
file.
