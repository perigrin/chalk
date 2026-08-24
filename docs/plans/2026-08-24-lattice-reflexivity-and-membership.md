# Two lattice defects: reflexivity diverges, and only one side checks membership

**Date:** 2026-08-24
**Status:** FILED, COORDINATOR-VERIFIED. Not fixed. Both are LATENT — no
current caller reaches either — but both are traps for the next one.
**Found by:** perigrin asking whether chalk omits the top and bottom types,
during the IR/type review. It does not (see below); measuring that question
exhaustively turned up these two.

## The question that started it, answered

Chalk's `%PARENT` has no row for `Unknown` or `None`. That is not an omission:
the table maps each type to its DIRECT PARENT, and the extremal elements have
none. Both are fully present in the OPERATIONS — `is_subtype` (:223), `join`
(:282-283), `meet` (:312) each special-case them by name.

Verified operationally, 15 checks across both repos: bottom is a subtype of
everything, top is a supertype of everything, neither reverses, and `join` /
`meet` agree on every extremal pair. The encoding differs; the semantics do not.

## Defect 1 — `is_subtype` is REFLEXIVE in chalk and STRICT in the producer

Exhaustive over all 27 members, 729 ordered pairs:

    pairwise is_subtype: 729 pairs, 27 disagreements

**All 27 are the diagonal.** `t <: t` is `true` in chalk and `false` in the
producer, for every member.

`lib/SoN/IR/Stamp.pm:81`:

    return false if $type eq $other_type;

That makes it a STRICT (proper) subtype relation. Chalk's is reflexive —
`TypeLibrary.pm:78` documents the exact-match path deliberately: *"is_subtype
(Num, Num) and is_subtype(Str, Str) work via exact match"*.

Both are coherent relations. They are not the SAME relation, and they share a
name across a wire boundary that is supposed to carry one IR.

**Why it is latent.** Both sides guard `join`/`meet` with `is_subtype` in both
directions, and both handle the equal case BEFORE those calls — producer
`Stamp.pm:97` (join) and `:124` (meet), chalk `TypeLibrary.pm:279`
(`return $left if $left eq $right`) — so the diagonal never reaches the
predicate. The exhaustive sweep above is what surfaced it; a caller-driven
audit would not have.

**Why it is a trap.** `TypeLibrary::type_satisfies` (:200) is written against
the reflexive reading — `return true if is_subtype($actual, $required)` is how
`Int` satisfies a required `Int`. The same line against the producer's
predicate answers `false`. Any logic moved or mirrored across the boundary
inherits the wrong law silently, and the failure is a REFUSAL of a correct
program rather than an obvious crash.

**Fix, when taken:** pick one. Reflexive is the standard reading of `<:` and is
what the paper's mechanical check verifies over its 729 pairs, so the producer
should drop line 80 — but that changes a predicate three call sites depend on
and needs its own measurement pass. The alternative (rename one of them, e.g.
`is_proper_subtype_of`) is smaller and arguably clearer about intent.

## Defect 2 — chalk answers about types it does not have

The producer validates membership at construction
(`SoN::IR::Stamp` ADJUST, :76):

    die "Unknown stamp type: $type" unless exists $PARENTS{$type};

So a non-member cannot be built, and a Value node cannot be stamped with one —
verified: `make('Constant', stamp => Stamp->new(type => 'Bogus'))` REFUSES.

Chalk has no membership predicate at all (no `is_known_type`), and answers
anyway:

| query | chalk | producer |
|---|---|---|
| `Bogus <: Int` | `0` | dies |
| `Bogus <: Bogus` | **`1`** | dies |
| `Bogus <: None` | **`0`** | dies |
| `join(Bogus, Int)` | `Unknown` | dies |
| `meet(Bogus, Unknown)` | **`Bogus`** | dies |

Three of those are wrong rather than merely permissive:

- `Bogus <: Bogus` is `1` by the reflexive exact-match path, which never checks
  membership — so an arbitrary string is a subtype of itself.
- `Bogus <: None` is `0`, **breaking the bottom law**: `None` is bottom, so
  `None <: t` must hold for every `t`, and the relation cannot be asked
  coherently about a `t` outside the lattice at all.
- `meet(Bogus, Unknown)` returns `Bogus` — a non-member ADMITTED into the
  lattice as an operation's result.

This is the same defect class as `Unknown` before it became a real member: a
non-answer wearing an answer's clothes. The lattice should refuse the question,
not invent a relation for a type it has never heard of.

**Fix, when taken:** give `TypeLibrary` a membership predicate and make
`is_subtype` / `join_types` / `meet_types` die on a non-member, mirroring the
producer's ADJUST. That is the same "make the unanswerable question unaskable"
move as `Chalk::IR::Value` and the required stamp field.

## Why neither is urgent

No current caller passes a non-member (the producer's ADJUST guarantees it for
anything that arrives over the wire) and no current caller reaches the
diagonal. Filed because both are the kind of latent disagreement that surfaces
as a wrong REFUSAL, not a crash — and because the reflexivity split is exactly
the sort of thing "one IR, one lattice" is supposed to have eliminated.

Related: `2026-08-22-two-lattices-one-ir.md` (RESOLVED — the member/parent
tables agree; these are the OPERATIONS diverging, which that audit did not
cover).
