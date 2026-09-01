# Lattice unification audit: producer vs. chalk type systems

Date: 2026-08-22
Status: research / findings only. No `lib/` or `t/` file was modified.

Scope: `~/dev/perl5-son` (`lib/SoN/IR/Stamp.pm`, `%PARENTS`) vs. this worktree
(`lib/Chalk/Grammar/Perl/TypeLibrary.pm`, `%PARENT`), measured against
`https://pvm.tools/papers/perl-types-formal.html`.

Everything below is either quoted from a file I read, or output of a command I
ran. Where I could not establish something, it says COULD NOT CONFIRM.

---

## A. The paper

**Reachable.** `curl` returned `HTTP 200 bytes=97129`. A de-tagged text
rendering is what I quote from.

**Crucial correction to the framing of this task: the paper is already vendored
in this repo.** `docs/architecture/perl-type-system-formal.md` is the same
document. Its `## Complete Type Hierarchy` block (lines 584-608) is character
-identical to the web page's hierarchy block. The web fetch was not strictly
necessary — but it confirms the vendored copy is faithful.

### The two rules

The owner's "two rules" are **not** the lattice laws. The paper names them in
its own summary (formal.txt:97-99):

> Claim: A value belongs to a type if: 1. It survives coercion without losing
> information (**syntactic preservation**) 2. It behaves correctly under the
> type's operations (**semantic fulfillment**)

Formalized as `[Type-Membership]` (formal.txt:379-380):

```
v ∈ T iff (∃S: S ≢ T ∧ C(v) ≡ id_S(v) where C: T→S)
        ∧ (∀op ∈ Operations(T): Contract_op(v))
```

These are **membership** rules — they decide which values are in a type. They
are the paper's actual load-bearing content, and they say nothing about join or
meet.

### The paper does NOT define join or meet

I searched the full text for `lattice|join|meet|least upper|greatest lower`.
Five hits, all prose. The word "lattice" is used informally (formal.txt:444-448):

> The term "lattice" comes from the structure having a top element (containing
> all values), a bottom element (containing no values), and well-defined ways
> that types can be combined and related. For our purposes, you can think of it
> as an organized hierarchy showing how Perl's types fit together.

The only algebraic laws stated are `[Subtyping-Reflexive]` (`T <: T`) and
`[Subtyping-Transitive]` (formal.txt:435-438). **There is no ∨/∧ operator, no
LUB/GLB definition, and no totality claim anywhere in the paper.**

> **Consequence for task D and F(1):** "does every pair have a join and a meet"
> cannot be checked *against the paper*, because the paper does not require it.
> It is a property we may *choose* to impose. I still measured it below, but the
> authority for it is engineering need, not the paper.

### Members, ordering, top, bottom, shape

Verbatim, formal.txt:653-673 (identical to `perl-type-system-formal.md:587-607`):

```
Unknown / Any (⊤ = V)
├── Scalar
│   ├── Undef
│   ├── Boolean
│   ├── Str
│   │   └── Num
│   │       └── Int
│   ├── DualVar (in Scalar but not in Str or Num)
│   └── Ref
│       ├── Object
│       ├── ScalarRef
│       ├── ArrayRef
│       ├── HashRef
│       ├── CodeRef
│       └── GlobRef
├── List
│   ├── Array
│   └── Hash
├── Code
├── Glob
└── None (⊥ = ∅)
```

- **Top:** `Unknown := V` and `Any := V`. Both are top; they are co-located.
  "These are **pragma types with identical value sets but different tooling
  semantics**" (formal.txt:466-467). `Unknown` = "Default state for unanalyzed
  expressions; signals a type checker to attempt inference"; `Any` = "Explicit
  polymorphic type; signals a type checker to accept without inference"
  (formal.txt:461-464).
- **Bottom:** `None := ∅`, with `∀T: None <: T` (formal.txt:646-651).
- **Chain:** "The complete subtyping chain is Int <: Num <: Str <: Scalar"
  (formal.txt:516-517).
- **Shape:** the *drawn* hierarchy is a tree. The paper says the wider system is
  not, via intersection types: `BlessedHashRef ∈ Object` **and** `∈ HashRef`
  (formal.txt:606-608). So: **tree as drawn, DAG in principle**, and the DAG-ness
  it argues for is blessed-ref intersection — *not* any of the multi-parent edges
  the producer actually encodes.
- **`Regex` does not appear in the paper at all.** `grep -c -i regex` on both the
  web text and `perl-type-system-formal.md` returns **0**.
- **`Void` does not appear as a type.** It appears only as an *evaluation
  context* — "Context (Scalar, List, Void) propagates through expressions"
  (formal.txt:1348) — and the paper explicitly defers context-indexed types:
  "This extension is left for future work" (formal.txt:1359).

---

## B. The "missing" practical doc — FOUND, and the premise is wrong

**`docs/perl-types-practical.md` was never deleted. It was renamed, and the
citation is a stale path.**

`git log --all --pretty=format: --name-only --diff-filter=A | grep -i perl-type`
lists all three names that have ever existed:

```
docs/architecture/perl-type-system-formal.md
docs/architecture/perl-type-system-practical.md
docs/perl-types-practical.md
t/semiring/perl-type-rules.t
```

`git log --all --diff-filter=D -- '*perl-types-practical*'` returns **empty** —
no deletion commit. The current file is present in the working tree at
`docs/architecture/perl-type-system-practical.md` (1055 lines).

So `TypeLibrary.pm:8` ("Type hierarchy from docs/perl-types-practical.md") is a
**stale path in a comment**, not a dangling reference to a lost document. One
other stale citation exists: `docs/chalk-parse-perl-plan.md:117` still points at
`pu:docs/perl-types-practical.md`.

### What the practical doc specifies

`perl-type-system-practical.md:83-108`:

```
Any/Unknown (everything)
├── Scalar (single values)
│   ├── Undef
│   ├── Bool (true/false) *
│   ├── Str (strings)
│   │   └── Num (numbers)
│   │       └── Int (integers)
│   ├── DualVar (values with independent string/numeric aspects)
│   ├── Regex (compiled regular expressions)
│   └── Ref (references)
│       ├── ScalarRef
│       ├── ArrayRef
│       ├── HashRef
│       ├── CodeRef
│       ├── GlobRef
│       └── Object
├── List (sequences)
│   ├── Array
│   └── Hash
├── Code (subroutines)
└── Glob (symbol table entries)

None (never returns) is the BOTTOM type: a subtype of every type above,
sitting below all of them. It is not a branch of Any.
```

**This is chalk's `%PARENT` exactly**, including `Bool` spelling, `Regex` under
`Scalar`, `Glob` at top level, `Array`/`Hash` under `List`, and `None` as
bottom. **Chalk's code has not drifted from its doc.** The doc and the code
agree; the drift is between *this pair* and the producer.

The doc is also self-aware about one past error — lines 111-125 record that an
earlier revision drew `None` as a child of `Any` and that this was corrected to
bottom, citing the implementation as correct. Commit `88b833bc` is
"docs(types): None is the bottom type -- correct the lattice tree, not the code".

### Are the two docs "two views of one system"? Mostly — with two real seams

| | formal | practical |
|---|---|---|
| Bool spelling | `Boolean` | `Bool` |
| Regex | **absent** | `Scalar` child |
| Void | absent (context only) | absent |
| Everything else | — | identical |

The owner's claim holds for ~90% of the members. The two exceptions matter:
`Boolean`/`Bool` is a pure spelling seam between the two papers themselves, and
`Regex` is a practical-only addition. Neither is chalk inventing something.

---

## C. Verification of the five claimed divergences

Members were enumerated by *probing the implementations*, not by reading:
chalk via `type_bitset($t)` being defined, producer via `Stamp->new(type=>$t)`
not dying.

```
CHALK MEMBERS (23): Any Unknown None Scalar Undef Bool Regex Str Num Int DualVar
                    Ref ScalarRef ArrayRef HashRef CodeRef GlobRef Object
                    List Array Hash Code Glob
SON MEMBERS   (19): Unknown None Scalar Undef Boolean Regex Str Num Int DualVar
                    Ref ScalarRef ArrayRef HashRef CodeRef Object List Glob Void
CHALK-ONLY: Any Bool GlobRef Array Hash Code
SON-ONLY:   Boolean Void
```

### 1. Renames — **CONFIRMED**

`Bool` (`TypeLibrary.pm:15`) vs `Boolean` (`Stamp.pm:16`): confirmed by the
member lists above.

`Glob`/`GlobRef`: **REFUTED as stated.** This is not a rename. **Both** names
exist in chalk (`TypeLibrary.pm:26` `GlobRef => 'Ref'`, `:38` `Glob => 'Any'`)
and the paper defines them as *genuinely different types* — "making the Glob the
primary form and GlobRef the derived reference form" (formal.txt:640-642). The
real defect is that **the producer dropped `GlobRef` entirely** (absent from
`%PARENTS`) while keeping `Glob` and misparenting it under `Ref`. That is a lost
member plus a wrong edge, not a rename.

Translation table **CONFIRMED** at `lib/Chalk/IR/Serialize/JSON.pm:26-33`, with
`Boolean => 'Bool'` at `:30`. Four live consumers (`grep -rn`):

```
lib/Chalk/IR/Serialize/JSON.pm:518   $args{from_repr} = $STAMP_TO_REPR{...}
lib/Chalk/IR/Serialize/JSON.pm:520   $args{to_repr}   = $STAMP_TO_REPR{...}
lib/Chalk/IR/Serialize/JSON.pm:555   if (... exists $STAMP_TO_REPR{ $nd->{stamp} })
lib/Chalk/IR/Serialize/JSON.pm:556   $node->set_representation($STAMP_TO_REPR{...})
```

Line numbers :26-30/:518/:520/:555 in the task brief are all accurate.

> Note: the table is not *only* a rename table. Its comment (`:21-25`) says it
> also acts as a filter — "Only the concrete, lowerable types map; anything else
> is left unset (the backend's `_require_repr` then reports an honest GAP rather
> than mislowering)." Deleting it therefore removes a **filter** as well as a
> rename. See F(3).

### 2. Members on one side only — **CONFIRMED with a correction**

chalk-only: `Any Bool GlobRef Array Hash Code` — brief said "Array, Hash, Code,
GlobRef, and root Any", i.e. it omitted `Bool` (which it counted under renames).
Accurate.

producer-only: `Boolean Void` — brief said "Void, None, Unknown". **`None` and
`Unknown` are in BOTH.** Both appear in chalk's member list above; `Unknown` is
`TypeLibrary.pm:105`, `None` is `:109`. So that part is **REFUTED**: the only
true producer-only members are `Boolean` (a spelling of chalk's `Bool`) and
`Void`.

### 3. Different parents — **CONFIRMED, and it does change answers**

Measured `is_subtype` on both:

```
Regex <: Ref     chalk=0 son=1   DISAGREE
Glob  <: Ref     chalk=0 son=1   DISAGREE
Glob  <: Scalar  chalk=0 son=1   DISAGREE
None  <: List    chalk=1 son=0   DISAGREE
```

Over all 17 shared members, **4 disagreements out of 289 ordered pairs.**

- `Regex`: chalk `Scalar` (`:16`), producer `Ref` (`Stamp.pm:25`). CONFIRMED.
- `Glob`: chalk `Any` (`:38`), producer `Ref` (`Stamp.pm:26`). CONFIRMED.
- `List`: chalk `Any` with `Array`/`Hash` beneath (`:30-32`); producer `Unknown`
  and childless (`Stamp.pm:29`). CONFIRMED — `Array`/`Hash` are simply not
  producer members, so those queries are member-gaps rather than disagreements.

### 4. Different roots — **REFUTED as stated**

The brief says "chalk `Any`, producer `Unknown`", implying chalk lacks
`Unknown`. It does not. **Chalk has both**, and the paper has both, and the
paper says they are the same value set with different tooling semantics.
Measured:

```
Str <: Any      chalk=1
Str <: Unknown  chalk=1
Any <: Unknown  chalk=1   Unknown <: Any  chalk=1
```

Chalk's `Unknown` is mutually-assignable-with-`Any`, exactly as
`TypeLibrary.pm:86-106` describes and exactly as the paper's "identical value
sets, different purposes" requires. The producer has only `Unknown`, i.e. **the
producer is the side missing a member.** Chalk's comment at `:86-106` is
consistent with the paper, not a divergence from it.

### 5. Shape — **CONFIRMED, with the important part being *why***

chalk `%PARENT` maps each type to a single scalar parent — a tree. Producer
`%PARENTS` maps to arrayrefs — a DAG. But only one entry actually uses
multi-parent: `Stamp.pm:12`,

```perl
None => [qw(Int Boolean Undef ScalarRef ArrayRef HashRef CodeRef Object DualVar Regex Glob)],
```

Eleven parents — **CONFIRMED**. Every other producer entry has exactly one
parent. So the producer is not really a DAG; it is a tree plus a hand-enumerated
bottom. And that enumeration is **incomplete** — see D.

---

## D. Both implementations vs. the rules

### Is either actually a lattice?

**Chalk: no join, no meet — the operations do not exist.**

```
TypeLibrary::join ABSENT
TypeLibrary::meet ABSENT
TypeLibrary::lub  ABSENT
TypeLibrary::glb  ABSENT
```

Chalk implements only `is_subtype` (`:214`). It is a partial order with a top
and a bottom; whether it *would* be a lattice is a structural question about
`%PARENT`. As a single-rooted tree with `None` as a universal bottom by
special-case, joins exist (nearest common ancestor) and meets exist trivially
(`None` for incomparable pairs). But nothing computes them today.

**Producer: join and meet exist and are total, but `meet` is unsound.**

```
join undefined for 0 pairs; meet undefined for 0 pairs
join NOT an upper bound in 0 cases
meet NOT a lower bound in 66 cases
```

`join` is well-behaved on all 361 pairs. `meet` returns a value for every pair
but that value is **not a lower bound** in 66 of them:

```
None ^ List = None (not lower bound)
None ^ Void = None (not lower bound)
Scalar ^ List = None (not lower bound)
Scalar ^ Void = None (not lower bound)
Undef ^ List = None (not lower bound)
...
```

**Root cause, and it is a single one.** `Stamp.pm:100` falls back to `None` when
no common subtype is found — but `None`'s parent list (`:12`) omits `Void`,
`List`, `Num`, `Str`, `Ref`, `Scalar`, `Unknown`, `CodeRef`... it enumerates 11
leaves only. Since `is_subtype_of` is ancestor-reachability, `None` is **not**
below `List` or `Void`:

```
None <: List son=0
None <: Void son=0
None <: Num  son=1     (reachable via Int -> Num)
None <: Scalar son=1
```

So the producer's declared bottom is not bottom. This directly violates the
paper's stated property `∀T: None <: T` (formal.txt:650-651). It is the same
defect that surfaces as `None <: List chalk=1 son=0` in the agreement table.

**Chalk gets this right** by not enumerating at all — `is_subtype` special-cases
it (`TypeLibrary.pm:216`, `return true if $child eq 'None';`) and the bitset
encodes it as `0` (`:109`). The brief asked me to check `:213-216`; the guard is
at **`:216`**, inside the sub starting at `:214`. Both mechanisms agree, and
`perl-type-system-practical.md:123-125` explains why both directions come out
right.

### Members the paper does not have / paper members neither implements

Paper members absent from **both**: none — every paper member is implemented by
at least one side.

Implementation members **not in the paper**:

- `Regex` — in both implementations, absent from the formal paper (`grep -c -i
  regex` = 0), present in the practical doc.
- `Void` — producer only; the paper has `Void` as an evaluation *context*, not a
  type, and defers context-typing to future work.

Paper members missing from the **producer**: `Any`, `GlobRef`, `Array`, `Hash`,
`Code`. Missing from **chalk**: none.

> Chalk implements the paper's membership completely. The producer is missing
> five paper members and adds one non-paper member.

### Does `is_subtype` agree with the paper?

Checked against the paper's explicit chain and edges:

```
Int <: Num     chalk=1 son=1  (both agree with paper)
Int <: Str     chalk=1 son=1
Num <: Str     chalk=1 son=1
Int <: Scalar  chalk=1 son=1
Object <: Ref  chalk=1 son=1
Array <: List  chalk=1 son=n/a  (producer lacks Array)
Hash  <: List  chalk=1 son=n/a
```

Chalk agrees with the paper on every relation the paper states. The producer
agrees wherever it has the members, and disagrees on `Glob <: Ref` (paper puts
`Glob` at top level, not under `Ref`) and on `None <: T` totality.

---

## E. Proposed unified lattice

**Direction: the producer converges on chalk.** Not because chalk is
privileged, but because on every divergent member chalk matches the paper and
the producer does not. Chalk's `%PARENT` is already the paper's tree.

| Member | chalk | producer | Unified | Why |
|---|---|---|---|---|
| `Bool` / `Boolean` | `Bool` | `Boolean` | **`Bool`** | Judgment call, see below — decided by measured backend cost. |
| `Any` | ✔ top | absent | **keep** | Paper defines `Any := V` as a first-class pragma type distinct in *purpose* from `Unknown`. Producer must gain it. |
| `Unknown` | ✔ top | ✔ top | **keep both** | Paper: identical value sets, different tooling semantics. Chalk's `:86-106` rationale is paper-faithful. |
| `None` | bottom (special-case) | 11 enumerated parents | **chalk's** | Paper `∀T: None <: T`. Producer's enumeration is measurably incomplete (66 broken meets). |
| `Regex` | `Scalar` | `Ref` | **`Scalar`** | Paper is silent. Practical doc says `Scalar`. Judgment call — see below. |
| `Glob` | `Any` | `Ref` | **`Any`** (top level) | Paper draws `Glob` at top level and argues `Glob` is primary, `GlobRef` derived (formal.txt:640-642). Producer is wrong. |
| `GlobRef` | `Ref` | **absent** | **`Ref`** | Paper: `GlobRef := {v ∈ Ref | reftype(v) eq 'GLOB'}` (formal.txt:563). Producer lost a paper member. |
| `List` | `Any`, has children | `Unknown`, childless | **`Any`/top, with children** | Paper: `Array <: List`, `Hash <: List`. |
| `Array` | `List` | absent | **`List`** | Paper member (formal.txt:617, 624). |
| `Hash` | `List` | absent | **`List`** | Paper member (formal.txt:618, 625). |
| `Code` | `Any` | absent | **`Any`** | Paper member, top-level branch (formal.txt:628). |
| `Void` | absent | ✔ | **drop from the lattice** | Paper has `Void` only as an evaluation context and defers context-typing. Judgment call — see below. |

Everything else (`Scalar`, `Undef`, `Str`, `Num`, `Int`, `DualVar`, `Ref`,
`ScalarRef`, `ArrayRef`, `HashRef`, `CodeRef`, `Object`) already agrees on both
sides and matches the paper. No change.

### The judgment calls (paper is silent or ambiguous)

**1. `Bool` vs `Boolean` — pick `Bool`; rename the producer.** The *formal* paper
says `Boolean` (formal.txt:656, `Boolean := { true, false }` at :482); the
*practical* doc says `Bool`. Both are "the paper" under the owner's framing, so
the paper does not decide it — it is decided by cost.

I originally leaned `Boolean` (formal spelling, producer already uses it), then
measured, and the measurement reverses it. `Bool` is not merely chalk's lattice
spelling — it is the **LLVM backend's representation vocabulary**, load-bearing
across `lib/Chalk/Target/LLVM/Context.pm`:

```
:45    return 'i1 (i8*)'   if $result_repr eq 'Bool';
:970   elsif ($repr eq 'Bool') {
:1336  if ($from eq 'Bool') {
:1521  elsif ($to eq 'Bool' && $from eq 'Int') {
:1675  return $ref if $repr eq 'Bool';
:3397  my $cond_repr = $cond_input->representation // 'Bool';
```

plus `lib/Chalk/Bootstrap/Semiring/TypeInference.pm:221`. Renaming chalk to
`Boolean` means touching the repr coercion matrix — the highest-risk surface in
the backend — to win a spelling. Renaming the producer's one `%PARENTS` entry
costs one line. **Take `Bool`.** The producer's `Stamp.pm:16` changes, and
`%STAMP_TO_REPR`'s rename half dies either way.

**2. `Regex` parent — `Scalar`, not `Ref`.** The formal paper never mentions
`Regex`, so this is genuinely undecided by it. Two arguments for `Scalar`: the
practical doc says `Scalar` (`:91`), and `TypeLibrary.pm:308` already types `=~`
as `{ left => 'Str', right => 'Regex', result => 'Bool' }` — a `Regex` operand
in a position adjacent to `Str`. The argument for `Ref` is that `ref(qr//)`
is `Regexp` and a compiled regex *is* blessed, which would make it an `Object`
under `Ref` by the paper's own `Object` definition (`blessed(v) is defined`,
formal.txt:564). **That argument is not weak.** I propose `Scalar` because it
matches the doc pair and preserves existing chalk behavior, but flag it as the
one place where the producer's choice has a principled defense. Worth a decision
from the owner rather than a silent convergence.

**3. `Void` — drop it. It is dead code.** The paper deliberately does not make
context a type. `Void` in the producer is a *context* marker that leaked into
the value lattice — and it is not even used as one. Grepping the producer for
`Void`:

```
lib/SoN/FromOptree.pm:2596   # Void statement position (the only shape wired): ...
lib/SoN/FromOptree.pm:4193   # Void context: the value is discarded; ...
lib/SoN/IR/Stamp.pm:28       Void      => [qw(Unknown)],
```

**Both `FromOptree.pm` hits are comments.** No code constructs a `Void` stamp;
the lattice entry has zero consumers. Deleting it needs no replacement
mechanism. Chalk already handles void-ness at the right layer anyway —
`TypeLibrary.pm:255-257`, `narrow_type($type,'Void')` returns `undef`, "discard
type info". Note that dropping `Void` also removes 2 of the producer's 66 broken
meets for free.

**4. `DualVar` stays under `Scalar` with no `Str`/`Num` edge.** Both sides
already do this and the paper is emphatic (formal.txt:660, 675-677). Listed only
because it is the one place where the tree shape is load-bearing rather than
incidental.

### On DAG vs tree

Unify as a **tree**. The producer's DAG-ness is entirely the `None` row, which
is exactly the row that is broken. The paper's genuine DAG argument is
blessed-ref intersection (`BlessedHashRef ∈ Object ∧ ∈ HashRef`), which **neither
implementation encodes** and which nothing currently needs. Adopting a tree plus
a special-cased bottom — chalk's existing design — is both simpler and the only
one of the two that is currently correct. If intersection types are needed later,
that is a real DAG change and should be its own piece of work with the
`BlessedHashRef` case as its motivating test.

---

## F. Test suite design

Not written to `t/`. Specified only.

### F(1) — Lattice laws, property tests over ALL pairs

**Important caveat established in A: the paper does not require join/meet
totality.** So this suite tests a property *we choose to impose*, and the doc
should say so rather than claiming paper authority.

Over all N² ordered pairs (N≈23, so 529 — exhaustive is cheap, no sampling):

- **Partial-order laws** (these *are* paper-backed, `[Subtyping-Reflexive]` /
  `[Subtyping-Transitive]`): `is_subtype(T,T)` for all T; transitivity for all
  triples (N³ ≈ 12k, still cheap); antisymmetry — `is_subtype(A,B) ∧
  is_subtype(B,A) ⟹ A eq B`, **with a documented exemption for the `Any`/`Unknown`
  pair**, which is mutually assignable by design.
- **Bottom:** `is_subtype('None', T)` is true for every T. This is the test that
  fails on the producer today in 4+ cases and is the highest-value single test in
  the suite.
- **Top:** `is_subtype(T,'Any')` and `is_subtype(T,'Unknown')` true for every T.
- **Join totality + correctness:** for every pair, `join(A,B)` is defined; is an
  upper bound (`A <: J ∧ B <: J`); and is *least* — no other member `K` with
  `A <: K ∧ B <: K ∧ K <: J ∧ K ne J`. (The producer passes upper-bound today;
  leastness is untested and I did not measure it — see "could not confirm".)
- **Meet totality + correctness:** same shape, dual. **This is currently red on
  the producer in 66 cases**; the test should be written to fail now and pass
  after `None` becomes real bottom.

### F(2) — Cross-implementation agreement

For every pair (A,B) over the **unified member set**, assert
`TypeLibrary::is_subtype(A,B) == Stamp::is_subtype_of(A,B)`. Plus a member-set
equality assertion — same names, same count, no member-gaps — because
disagreement-counting silently under-reports when one side lacks the member (that
is exactly how the brief's divergence list came to say "n/a" for six pairs).

Today this test would report: **4 disagreements over 17 shared members, plus 8
member gaps.** That is the baseline it should start red at.

**Cross-repo mechanics.** This is the one test that cannot live in a single
repo's normal suite. Options, in order of laziness:

1. **Run it from chalk with both `lib/` on `@INC`** — exactly what my probe did:
   `use lib '/home/perigrin/dev/chalk/.../lib'; use lib '/home/perigrin/dev/perl5-son/lib';`
   Works today, zero infrastructure. Downside: hard-codes a sibling checkout path
   and silently skips if absent — so it must **fail loudly, not skip**, or it
   becomes a vacuous pass (this project has a documented history of exactly that
   failure mode).
2. **Vendor the member/parent table as data.** Export `%PARENTS` and `%PARENT` to
   a JSON fixture each side commits, and have each repo test its own table
   against the shared fixture. Removes the path dependency; costs a sync step.

I recommend (1) with a hard `BAIL_OUT` when the producer checkout is missing, on
the grounds that the wire format already couples these two repos far more tightly
than a test path does. Note the existing hazard: the memory notes say the gate
reads perl5-son **live**, so this test inherits the same
no-version-pin/serialize-execution constraint.

### F(3) — Guard that `%STAMP_TO_REPR` is empty or gone

Once `Boolean`/`Bool` is unified, the rename half of the table is dead. Assert
`Chalk::IR::Serialize::JSON` has no `%STAMP_TO_REPR`, or that it contains no
entry whose key differs from its value.

**Do not simply delete the table.** Per its own comment (`JSON.pm:21-25`) it is
*also* a whitelist filter: only concrete lowerable types map, and unmapped
stamps deliberately leave `representation` unset so `_require_repr` reports an
honest GAP instead of mislowering. The correct end state is a **set**, not a
map — e.g. `%LOWERABLE_STAMPS` — and the guard should assert *identity*
(`key eq value` for all entries) rather than emptiness, which keeps the filter
and kills only the rename. A test asserting the table is *empty* would push
someone into deleting the filter and silently re-enabling mislowering of
non-concrete stamps.

---

## What I could not confirm

- **Whether the two papers are "two views of one lattice" as the owner asserts.**
  I verified they agree on all members except `Boolean`/`Bool` spelling and
  `Regex` (formal has no `Regex` at all). I take no position on whether that is
  intended; it is the owner's call.
- **Join *leastness* and meet *greatestness*** on the producer. I measured that
  `join` is always an upper bound and `meet` fails to be a lower bound in 66
  cases. I did **not** verify that `join` returns the *least* upper bound; a join
  that returns a valid-but-too-loose bound would pass my probe. F(1) specifies
  the stronger test.
- **Whether any test currently pins either lattice.** `t/semiring/perl-type-rules.t`
  appears in git history but **does not exist today** (`ls` fails). I did not
  sweep the whole suite for other tests that might assert lattice edges
  incidentally, so "nothing pins it" is unproven — only "the one obviously-named
  file is gone" is established.
- **Why the producer's `None` parent list enumerates those particular 11 types.**
  It looks like a hand-written leaf list that was never updated as members were
  added, but I found no commit message or comment stating intent.
