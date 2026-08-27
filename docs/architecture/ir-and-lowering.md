<!-- ABOUTME: Statement of Chalk's IR/type/representation/lowering architecture: what exists, what is designed, what is open. -->
<!-- ABOUTME: Synthesizes docs/research and docs/plans from 2026-08 into one present-tense design statement; see those files for the measurements this rests on. -->

# IR, Types, and Lowering

This document states the architecture of Chalk's intermediate representation
and its lowering to a target backend: what the IR is, how a value's type is
distinguished from its machine representation, how lowering relates the two,
and how memory access is meant to work. It is a design statement, not a
migration log. Every section is marked with its status:

- **BUILT** — exists in `lib/` today, with file:line evidence.
- **DESIGNED** — agreed direction, not yet implemented.
- **OPEN** — an unresolved question, stated as a question.

A companion audit, `docs/research/2026-08-24-two-ir-architecture-alignment.md`,
measured the code against this design and found it roughly 35% aligned. Where
this document says BUILT, that audit is the receipt. Where it says DESIGNED or
OPEN, treat every sentence as intent, not as a claim about `lib/`.

---

## 1. What the IR is

**Status: BUILT.**

Chalk represents a parsed program as a Sea of Nodes graph (Click & Paleczny
1995): a directed graph of immutable, hash-consed nodes with explicit
data-flow edges and explicit control-flow edges, rather than a basic-block IR
with an implicit instruction sequence. `lib/Chalk/IR/Node.pm` is the base
class every node extends; `lib/Chalk/IR/Graph.pm` is the single graph
container, with a hash-cons cache scoped per-instance
(`lib/Chalk/IR/Graph.pm:15-19`, `field %cache`); `lib/Chalk/IR/NodeFactory.pm`
is the single factory through which every node is constructed. There are 87
node classes under `lib/Chalk/IR/Node/` and no second node hierarchy — a
`find lib -iname "*Lower*" -o -iname "*Machine*" -o -iname "*MIR*"` finds
nothing (audit §1).

There is **one IR machinery**, used to populate potentially more than one
graph. This is the load-bearing framing for everything below: lowering is not
a translation between two kinds of IR node. It is a transformation that
consumes one Sea-of-Nodes graph and produces another Sea-of-Nodes graph, built
with the same `Chalk::IR::Node`/`Graph`/`NodeFactory` machinery, whose nodes
are simply further along — specialized for a particular lowering target. In
the owner's words:

> "Not really two IRs ... it's a graph transformation of the Chalk IR to
> *another* SoN IR that is more specialized for lowering."

Full node-type taxonomy, hash-consing protocol, and use-def chain mechanics
are documented in `sea-of-nodes-ir.md`; this document is scoped to the
type/representation/lowering axis that document does not cover.

---

## 2. The type axis

**Status: DESIGNED as an end-to-end axis; BUILT as a lattice; NOT CONNECTED
as a live field on loaded graphs.**

### The lattice

`lib/Chalk/Grammar/Perl/TypeLibrary.pm` owns a single ordered type lattice —
27 members, `%PARENT` (`TypeLibrary.pm:17-56`), e.g. `Int <: Num <: Str <:
Scalar`, `ArrayRef <: Ref <: Scalar`, with `Unknown` as sole root and `None`
as bottom. This is the canonical copy: it is verified mechanically against
`docs/architecture/perl-type-system-formal.md`'s formal lattice, and it is
verified to have **zero divergence** against the producer's copy
(`~/dev/perl5-son/lib/SoN/IR/Stamp.pm`, `%PARENTS`) across all 25 shared
members (`docs/plans/2026-08-22-two-lattices-one-ir.md`, RESOLVED
2026-08-23). One lattice, mirrored in two repos, is a satisfied prerequisite
for everything downstream that needs to translate from it.

### The stamp field, and where it lives

The type of a value-producing node is carried in a field called **`stamp`**,
not `type`. The name is deliberate: `lib/Chalk/IR/Value.pm:25-31` states it is
"a STAMP in C2's and Graal's sense — an abstract-interpretation fact ABOUT a
value, of which the type is one component," modeled on Graal's `Stamp`
hierarchy, which also carries non-null, exact-type, and integer-bounds facts
alongside the type. Chalk's stamp today holds only the type component; the
name is chosen so the field does not need renaming when refinement passes
(narrowing, range analysis) are added.

`Chalk::IR::Value` (`lib/Chalk/IR/Value.pm:51-52`) is a subclass of
`Chalk::IR::Node` introduced specifically to make "does this node have a
type" a structural, `isa`-checkable question rather than an
`undef`-vs-not-`undef` guess on a field every node carries. Control nodes
(`Start`, `Return`, `Region`, ...) stay on `Chalk::IR::Node` and have no
stamp at all; value-producing nodes are meant to move to
`Chalk::IR::Value`, where `stamp` is required. The producer side of this
split is already load-bearing: `SoN::IR::Value` (perl5-son
`lib/SoN/IR/Value.pm:97-103`) enforces in its `ADJUST` block that every
value node is constructed with a stamp, defaulting unknowable cases to the
literal lattice member `Unknown` — a real, joinable/meetable member of the
lattice, not an absence.

**What this buys, once connected:** an `undef` stamp can only mean one thing
(inference has not run yet), rather than three indistinguishable things —
"this node produces no value", "inference hasn't run", "inference ran and
failed" — which is what a single shared field on every node conflated before
the split (`Value.pm:9-23`).

### The gap: chalk-side stamps are discarded at load

On the **producer** side, this is real: `SoN::IR::Value` requires a stamp,
and a real B::SoN run over Perl source serializes wire `stamp` values with no
`representation` key at all (audit §3, verified on a live run: 12 stamps on
the wire, 0 `representation` keys).

On the **chalk** side, `set_stamp` (`lib/Chalk/IR/Node.pm:212-215`) is
defined and is called from **nowhere in `lib/`** (audit §4, static grep and
independent dynamic re-run: 0 of 14 loaded nodes on a real graph carry a
stamp). The loader instead reads the wire's `stamp` key only to *derive a
representation* from it where the name happens to overlap
(`lib/Chalk/IR/Serialize/JSON.pm:548-549`), then discards the type. So the
chalk-typed graph — "an IR before lowering, carrying Chalk types" — does not
exist today as a live object; it exists only transiently, as wire JSON,
inside the deserializer. `Chalk::IR::Value` is empty scaffolding
(`Value.pm:51-52`, an empty class body) over a field nothing writes.

This matters specifically because of what §4 (lowering) says the type axis
is *for*: it is the transformation's input. Without it, "replace the Chalk
types with lowered types" has nothing to replace.

---

## 3. The representation axis

**Status: DESIGNED as "the same field, after a rewrite," not a second
attribute — BUILT as a field, but populated by the wrong layer.**

### The core claim

> "There should be no representation field. Representation is just the type
> of the lowering target."

and, more precisely:

> "Representation is really just changing the type from a Chalk type to a
> Backend (LLVM) type ... so Node(Int) becomes Node(i64) or Node(u64) or
> whatever the LLVM lowering algorithm decides."

This is not "two attributes that happen to overlap." It is one slot — call it
"the type of this value" — whose *vocabulary* changes from the Chalk lattice
to the lowering target's vocabulary as a consequence of the lowering pass
having run. Measured support for this reading: 11 of the 12 representation
values in use (`lib/Chalk/IR/Node.pm:41-56`'s docstring; `%_REPR_LLVM_TYPE`,
`lib/Chalk/Target/LLVM/Context.pm:3036`) are literally lattice type names —
`Int`, `Num`, `Str`, `Boolean`, `Undef`, `Array`, `Hash`, `ArrayRef`,
`HashRef`, `CodeRef`, `Object`. There is no separate representation
*vocabulary*; there is the type vocabulary, plus one machine-only name
(`Slot`, discussed in §5).

### SSA forbids the alternative

A node is a single definition. In SSA, one def has one value and one type.
Two uses that genuinely needed different machine encodings of that value
would need different *values* — i.e., different defs, i.e., a conversion
node between them (`docs/plans/2026-08-21-type-vs-representation-seams.md`,
"Evidence 3"). So representation cannot legitimately be a per-use property of
one node; it is a per-node property, exactly like a type, and cross-use
differences are reconciled by minting a **new** def (a `Coerce` node) rather
than by attaching two representations to one node. This is why the rewrite
described in §4 is safe: it can only ever *add* defs (insert a `Coerce`
between an existing def and a use), never mutate an existing def's meaning.

### Where representation is set today, and why that is backwards

`set_representation` has 19 real call sites in `lib/` (audit §2): **18 are in
the loader**, `lib/Chalk/IR/Serialize/JSON.pm` (a spread of named functions:
`_seed_direct_call_arg_reprs`, `_stamp_field_access_reprs`,
`_stamp_method_call_reprs`, `_insert_str_coercions`,
`_narrow_unknown_coercions`, `_resolve_direct_calls`, plus an inline site),
and **1 is in the target**, `lib/Chalk/Target/LLVM/Context.pm:5197`. The
loader's assignment is not a single pass; `Serialize/JSON.pm:871` runs one of
these functions to a fixpoint (`while (_stamp_method_call_reprs(...) > 0)`),
because a callee's representation is not knowable until its own internal
calls are stamped — this is genuinely an iterate-to-fixpoint dataflow
analysis, just one that currently lives inside a deserializer instead of
being a pass with a graph in, a graph out.

The comment on `Chalk::IR::Node`'s `representation` field
(`Node.pm:41-56`) itself names the layering violation: it documents LLVM
machine types inline (`'Int' (i64)`, `'Num' (double/f64)`, `'Str'
({ptr,len,encoding})`) on a field that is supposed to hold, per the core
claim above, a value that started as a Chalk type. That docstring belongs to
`%_REPR_LLVM_TYPE` in the LLVM target, not to the shared IR node.

---

## 4. The lowering transformation

**Status: DESIGNED in detail; the seam to insert it at exists; the pass
itself does not exist.**

### The shape

The transformation is: **graph → graph**. It consumes a graph whose
value-producing nodes carry Chalk-lattice stamps, and produces a new graph —
same node machinery, same hash-consing discipline, own `NodeFactory` — whose
nodes carry the lowering target's vocabulary in the same slot. Concretely for
the LLVM target: `Node(stamp=Int)` becomes `Node(stamp=i64)` (or `u64`, or
whichever machine type the lowering decision selects for that value). Where
one Chalk-typed def must lower to two different machine types across the
program (`Int` sometimes needing `u64`, sometimes `i64`), the pass mints a
`Coerce` node between the two lowered defs, rather than attaching two
representations to one node (§3's SSA argument).

The pass contract for this already exists:
`lib/Chalk/Bootstrap/Optimizer/Pass.pm:2,13-14` documents `run($Graph) ->
$Graph` for `scope => 'graph'` subclasses. A conforming lowering pass would
be an ordinary subclass of `Chalk::Bootstrap::Optimizer::Pass`. The seam to
run it at is three lines: `lib/Chalk/Target/LLVM.pm:53-59`'s `lower()` builds
a `Dominators` and an `Elaborate` schedule and hands them to
`lower_with_elaboration`; a lowering pass would sit between the schedule
being built and that call.

### What it replaces

Concretely, per the audit's measurement of what the LLVM target currently
does *during emission* instead of before it:

- **94 representation-comparison branches** across 53 distinct ops in
  `Context.pm` — the distinctions a lowered graph would encode as node kinds
  or resolved types, rather than as string comparisons re-derived at every
  emission site.
- **14 `repr eq 'Scalar'` refusals** (e.g. `Context.pm:1095`, `die "$op with
  repr=Scalar reached LLVM backend"`) — each one a well-formedness
  precondition on the *input* to lowering, currently asserted at 14 separate
  emission sites because there is no single point where the lowered graph's
  construction could refuse `Scalar` once, structurally.
- **30 `_require_repr` assertions** (`Target/LLVM.pm:80`) — "representation
  must be defined by the time we look at this node," which is the pass's
  postcondition asserted piecemeal at every call site instead of once at the
  pass's exit.

None of this is a claim that the target gets uniformly smaller. The 418
`_emit()` calls that build LLVM IR text, and the 33 emission-scoped side
tables that carry the *encoding* half of a representation (`_str_len_table`,
`_undef_defined_bit`, `_slot_payload`, and others — see §5), are concerns of
text emission, not of typing, and a lowered graph does not by itself absorb
them (audit §7's gap-sizing table is the exhaustive accounting).

### Why the removal is safe, and where it stops being mechanical

Per `docs/plans/2026-08-14-representation-is-the-targets-type-system.md`: a
`Coerce` between representation A and representation B may be elided **iff
both** legs hold:

```
skip the Coerce  iff  is_subtype(A, B)              # SEMANTICS (IR-level, target-independent)
                 AND  type_for(A) == type_for(B)     # ENCODING  (target-specific)
```

Neither leg alone is sufficient. `Int -> Num` needs the encoding leg (`i64 !=
double`, so keep the coercion — this is the `sitofp` that makes `3/2` be
`1.5`). `Bool -> Undef` needs the semantic leg (`i1 == i1`, same bits, but
`is_subtype(Bool, Undef)` is false — they are unrelated siblings under
`Scalar`, and reinterpreting one's bit pattern as the other is a semantic
error, not a no-op, even though the machine encoding is identical). A single
check in either direction silently miscompiles the case the other check
catches.

### Design must-answers, carried forward from the source docs

- **Machine-vocabulary coercions are not all lossless.** `Coerce(u64 ->
  i64)` on a value above `2^63-1` is a real miscompile, not a
  representation change. The pass needs a machine-level lossiness table
  distinct from the Chalk-level subtype table.
- **Choosing a representation and inserting its conversions must be one
  decision**, not select-then-repair across two passes — splitting them
  is precisely what produced the UV-wraparound miscompile documented in
  `docs/plans/2026-08-21-type-vs-representation-seams.md` (findings 0a/0b).

---

## 5. Access and provenance: why `Slot` exists, and why it should not

**Status: `Slot` is BUILT and load-bearing today. Its replacement (threading
provenance through the stamp) is DESIGNED, not built.**

### What `Slot` is, today

`Slot` is the one representation-vocabulary member with no type-lattice
meaning (`docs/plans/2026-08-24-there-should-be-no-representation-field.md`
§2). It is the uniform storage cell for an array element, a hash value, or a
class field: `{ i1 defined, i64 payload }`
(`%_REPR_LLVM_TYPE`, `Context.pm:3045`). The payload is an untyped one-word
union — what it *means* depends entirely on the container's inferred element
type, which is not recorded anywhere the cell itself can be asked about
(`docs/research/2026-08-24-chalk-memory-model-baseline.md` §1).

### Why that is a problem

Because no cell records what its payload IS, **the type of a loaded value is
recovered, not carried** — the loader walks back to the container's literal
initializers and takes the join of their types
(`_element_repr`, `IR/Serialize/JSON.pm:1673`). This works only while the
container is a compile-time literal with all its initializers visible in the
graph. It has no model of *stores*: `my @a=(1,2,3); $a[1]="x";` is a
correctly-refused GAP today (`Context.pm:1996`), not a miscompile, but the
refusal is the cost of a container's type being reconstructed from its birth
rather than carried forward through its lifetime
(`chalk-memory-model-baseline.md` §3).

### Reframing what the honest type of a Perl array is

`ArrayRef` and `ArrayRef[Int]` are not two candidate representations of the
same fact; they are two different questions:

> "Perl doesn't optimize Array of Ints ... everything is an Array of
> Scalars. Lowering to Array of Ints then is an *optimization* pass once we
> can guarantee that a given array *only* ever has Ints in it."

Every Perl array is honestly `ArrayRef[Scalar]` — one aggregate kind holding
SVs. The bare `ArrayRef` stamp is not an under-specified type; it is the
*correct, honest type at full generality*. `ArrayRef[Int]` is a proof
obligation an optimization pass discharges (monomorphism over the array's
whole lifetime — all stores, all aliases, all calls that receive it), not a
type the frontend derives (`chalk-memory-model-baseline.md` §4a). Read this
way, `_element_repr`'s initializer-join is a monomorphism check wearing type
inference's clothes, answering the right question (are all the elements the
same width?) over the wrong domain (initializers only, not the whole
lifetime including stores) — which is exactly why it must GAP rather than
miscompile the moment a store disagrees.

### Prior art: neither TurboFan nor Graal does what Chalk does

`docs/research/2026-08-24-typed-memory-prior-art.md` (primary sources,
re-verified against upstream `turbofan-typer.cc` and Graal's `Stamp`
hierarchy) is unambiguous on this point: **neither compiler recovers a
loaded value's type by analyzing what was stored.** Both establish the
invariant *at the store* and let the load assume it:

- **Graal**: `StoreIndexedNode` carries a guard on the write;
  `LoadIndexedNode.createStamp` derives the element's stamp as a **projection
  of the container's stamp** (`type.getComponentType()`), never by walking
  stores or initializers.
- **V8/TurboFan**: an access descriptor (`ElementAccess`/`FieldAccess`)
  carries **both a `Type` and a `MachineType` as separate struct fields**,
  set when the access site is built; a narrow type is enforced by a
  `CheckSmi`/`CheckNumber` guard emitted at the store, and a disagreeing
  store deoptimizes rather than silently widening what the load believes.

The transferable idea, stated directly: **enforce at the store, do not
recover at the load.** Chalk currently tries to do the opposite — recover at
the load what these compilers enforce at the store — and the type-changing
store GAP is the direct, structural consequence.

One constraint does not transfer: V8's narrowing is underwritten by
deoptimization to an interpreter. Chalk has no interpreter to fall back to,
so every narrowing must be either **proven** sound ahead of time, or
**guarded** by an emitted runtime branch (fast path plus a boxed slow path,
both compiled) — code size in place of a deopt mechanism. The prior-art
document names this explicitly as the biggest constraint that does not
transfer.

### Where the design lands: provenance rides in the stamp

> "I think Slot goes away, it shouldn't exist. Instead when we do
> array/hash/ref access we should thread the provenance information through
> so that the lowering pass can set up the right memory access. That
> provenance I think [should] be stored in the Stamp based on what you said
> about C2 and Graal … we probably could have specific Stamp subclasses for
> each type of value access."

This is Graal's own shape, applied to a new axis: `Stamp` there is an
abstract class with per-kind subclasses (`IntegerStamp`, `ObjectStamp`, ...)
each carrying kind-specific facts. A Chalk stamp subclassed by access kind —
array-element access, hash-element access, scalar deref, field access — would
carry the provenance the lowering pass needs to pick the right memory
operation, in the same slot the type already lives in. Under this design,
`Slot` retires: the lowering pass knows the payload's type from the stamp and
picks the encoding directly, so the IR no longer needs a name for an untyped
cell (`docs/plans/2026-08-24-access-provenance-and-the-mop.md`).

### The narrower, cheaper first step: thread use-demand backward

Before a full provenance-in-the-stamp redesign, a smaller, independently
useful mechanism is scoped: propagate *what each consumer needs* backward
from uses to definitions — TurboFan's `PROPAGATE` phase in isolation
(`docs/plans/2026-08-24-thread-use-information-to-lowering.md`). Both
prerequisites are already present: every node's `consumers` list already
names the demand (an `Add` consumer wants a number, a `Coerce` consumer wants
whatever it coerces to), and `TypeLibrary::operand_repr_for_ir_op` already
answers "what representation does this consumer require of its operand at
this position" for a subset of ops. What is missing is only the walk that
accumulates that demand back to each definition. This does not make a
type-changing store compile (that still needs the store path to fall back to
a boxed cell rather than refuse) and does not add alias classes — it changes
*who decides* a `Subscript`'s representation, from "guessed from the
initializer" to "the use says," which is a strictly smaller and more
tractable step than the full provenance redesign.

### Why `%Slot` is not an SV, and what SSA buys

**Status: DESIGN RATIONALE. Constrains the lowering pass; nothing below is
built.**

`%Slot` is `{ i1 defined, i64 payload }` — a discriminated cell holding a
value whose type the compiler could not pin down. Stated that way it is
recognisably **an SV in miniature**: `i1 defined` is `SvOK`, `i64 payload` is
the union with one arm, and the obvious next move — add a tag naming which of
Int/Num/Str/ref the payload holds — is the road to `sv_flags` + `sv_any`.

**That road is the project's recorded failure mode, and it must not be taken
by default.** The optree says *what* IR; the semantics say *how it behaves*;
neither says *how we implement it*, and importing perl's implementation into
that layer is exactly the mistake. The distinction that keeps the two apart:

- **perl needs an SV because it cannot know the type.** Every scalar is
  dynamically typed, so every scalar pays for the discriminator.
- **Chalk needs a tagged cell only where inference FAILED.** The cell is the
  residue of an unproven type, and the whole analysis pipeline exists to make
  it rare.

Same data structure, opposite default. If the tagged cell is the common case,
Chalk has reimplemented perl and gained nothing.

**And SSA removes most of the need for the tag.** A slot in SSA holds one
defined value, and that value's type is fixed at compile time. `(1, "x")` is
not a cell needing a runtime discriminator — it is slot 0 : `Int` and slot 1 :
`Str`, both statically known. The heterogeneity is ACROSS POSITIONS, not
within one. Only a genuinely dynamic index makes element type a runtime
question. So `%Slot` needs no type tag: the `i1` discriminates the one axis
that survives SSA — present versus absent, which is really dynamic (OOB reads,
sparse arrays, `delete`) — and type, which is not dynamic, does not belong in
the cell.

That makes `%Slot` the **un-narrowed encoding**, not the universal one, and
gives the lowering pass a ladder rather than a single answer:

| what has been proven | what is materialised |
|---|---|
| nothing — genuinely dynamic index, or a join that leaves `Scalar` | full `%Slot` per element |
| element positions known statically | per-position type; no cell |
| `Array[Int]` monomorphic over its lifetime | raw `i64` elements; **`%Slot` gone entirely** |

The bottom row is the point: monomorphism does not merely let the tag be
elided, it **deletes the container cell**. An `Array[Int]` is `i64*` plus a
length. `%Slot` is what you pay for having proven nothing yet, and the
optimizer's job is to stop paying it.

**"ELEMENTS NOT UNIFORM" WAS LOOSE WORDING, now corrected in the table above**
(perigrin, 2026-08-27). Mixed element TYPES never justify `%Slot`, for a reason
stronger than the "across positions, not within one" argument above: the lattice
join makes them uniform. `@a` holding an `Int` and a `Str` has type
`Array[Int|Str]`, and since `Int <: Num <: Str` that **reduces to
`Array[Str]`** — monomorphic, bottom row of the ladder, raw `Str` elements and
no cell, with a `Coerce(Int -> Str)` at the `Int` element's store site.

On a TOTAL join (Phase 3) any set of scalar element types has a least upper
bound, so "different types" can never by itself mean "not uniform". What
actually reaches the top row is narrower:

- a **genuinely dynamic index**, where which element is read is a runtime
  question, so no per-position fact applies (the case the paragraph above
  already names);
- a join that lands on **`Scalar`** — cross-kind, e.g. `join(Int, ArrayRef)` —
  which has no machine encoding at all until T2 exists. That is the D2 case
  (`logical.md` L3b/L3c/L3d) that took the gate to 215.

The `i1` is the other axis entirely, and it is not a type question:
present-versus-absent, which IS dynamic (OOB reads, sparse arrays, `delete`).

**A MISS IS NOT A SLOT** (perigrin, 2026-08-27). The ladder's top row is
*heteromorphism* — "dynamic index, elements not uniform" — so `%Slot` is what a
container pays when its elements cannot share a width. A read that is **not in
the container at all** has no membership to encode, and reaching for `%Slot`
there imports a container-uniformity mechanism into a case with no container
question.

Worked case, corpus `references.md` R10: `my %h = (a => 1, b => 2); say($h{z})`.
On the TYPE axis the missing-key read is **`Undef`** — a real lattice member,
statically known, since the key is a literal absent from a literal hash. On the
ENCODING axis the container is uniform `Int`, so by the bottom row it warrants
**no `%Slot` whatsoever**. The `Coerce(Slot -> Str)` in that case's `ir` block
is what today's lowering happens to emit, not what the case requires.

This is the axis distinction in miniature, and it is easy to get backwards: the
gate's SHAPE leg reports encodings (`Subscript :Slot`), the type axis wants
`Undef`, and quoting the shape leg as if it were a type is how `Slot` — which is
not in the lattice at all, and for which `join_types(Slot, Int)` is `Unknown` —
ends up proposed as a stamp. The producer-side rule that follows: a provably
absent read (missing literal key, constant index provably out of range) is
`Undef`; only a genuinely undecidable one (computed index, runtime key) is
`Unknown`.

**Read that as a cost, not a defect. Boxing is okay; incorrect lowering is
not.** The boxed form is CORRECT — it is the encoding that is always available
and always right, and it is the floor the ladder rises from rather than a
failure state to escape. Narrowing removes an unnecessary cost; it never
repairs a wrong answer. Anything that unboxes without a proof is trading the
one property that is not negotiable for the one that is.

This is the same claim §5's `ArrayRef[Scalar]`
reframing makes about types, expressed as machine encodings.

**`Undef` is a unit type, so a `{defined=0}` slot hash-conses to one value.**
There is exactly one inhabitant, which means the payload is not merely
irrelevant — it is not part of the value. Two undef slots are the same value
in the sense hash-consing means, exactly as `true` and `false` are singletons
rather than two `i1`s that compare equal. The type axis already agrees:
`Undef` is in `%LOWERABLE_STAMP` and `_repr_to_llvm_type('Undef')` answers
with a constant rather than refusing (`t/bootstrap/ir/repr-to-llvm-type-total.t`
calls it "a unit type, not a refusal"). The slot-level consequence is that
same fact one layer down — a provably-undef slot need not be materialised as a
cell at all, collapsing the ladder from the other end.

**Which is why `%Slot` is a TARGET type and not a lattice type.** `Scalar` is
a type: a real lattice element meaning "some scalar, not yet narrowed."
`%Slot` is what the LLVM backend picks when it must lower a `Scalar`. A
different target could pick differently; a sufficiently narrowed program never
materialises one at all. The lattice describes the program; the target type
describes a compilation choice about it. This is the cleanest instance of the
rule that **representation is just the type of the lowering target** — and the
reason `Slot` sitting in the stamp field today (the OOB path,
`IR/Serialize/JSON.pm:1459`) is a genuine corruption of the type axis rather
than a harmless naming overlap.

**The concrete first case where the split pays.** `$a[9]` on a three-element
array is *statically* out of bounds — the loader knows it at the site above,
which is why it writes something there at all. It writes `Slot`, the encoding.
The honest type is `Undef`, and once it records that, the unit-type fact means
the backend emits the shared undef instead of constructing a cell. That is one
line in the loader plus the backend knowing what `Undef` means; it is blocked
on the lowering pass existing, but it is small, testable, and already pinned
with a warning in `t/bootstrap/ir/stamp-alias-preconditions.t`.

**Open, and not answered here:** `Array` is excluded from `%LOWERABLE_STAMP`
despite having a machine encoding (`%Array*`), which looks like the same
omission `ArrayRef`/`HashRef` had before slice 3b admitted them. The container
lowers; it is `Array[Scalar]`'s *element* that does not, for want of the boxed
representation this section describes. Whether admitting `Array` is safe on
its own is unmeasured.

---

## 6. The MOP: tie and magic as user-defined implementations of access

**Status: DESIGNED, with one measured, binding constraint.**

### The binding constraint, measured

Perl compiles a container access **once**, and its behavior depends on the
container it is handed **at runtime** — not on anything visible at the
access site. Measured directly: a compiled closure `sub { my $aref = shift;
$aref->[0] }` produces the identical optree whether called with a plain
arrayref or a `Tie::StdArray`-tied one; the tie/magic check lives in the
runtime value (`SvTIED_mg`/`SvMAGICAL`), never in which op was selected
(`docs/plans/2026-08-24-access-provenance-and-the-mop.md`, "The tie/magic
premise").

The consequence for a compiler with no runtime to fall back on: **any
access-provenance fact recorded at compile time is a speculation, never a
proof**, unless the specific container is proven never to escape and never
to be tied within the compilation unit. This was tested against the
apparently-safest case — a `feature class` field — and the safe case does
not exist: a class field is a lexical, and `tie` works on it exactly like any
other lexical (measured repro in the same document: a `:reader` accessor's
output changes under a live tie). So there is no access *kind* with
statically guaranteed provenance; what can exist is a provably-safe
compilation *subset* — e.g., Chalk's own self-hosting corpus, measured to
contain zero `tie` sites and a single, mechanically-convertible dynamic
`@ISA` assignment.

### The framing this motivates

> "I think all of this needs to be governed by a Metaobject Protocol because
> TIE and Magic are both basically alternative/user defined versions of
> *exactly* this MOP."

Rather than treating tie and magic as exceptions bolted onto plain
array/hash/scalar access, model access itself as a MOP dispatch: a plain
array-element fetch and a tied array-element fetch are the same *operation*
(`FETCH`) with different *implementations*. Chalk already has a MOP
(`lib/Chalk/MOP/`) for classes, methods, and fields; whether access dispatch
belongs in that MOP or a sibling protocol over a different kind of subject
(containers, rather than classes) is open (below).

Because every access site is a speculation rather than a proof, every
narrowing this design licenses must be either:

- **PROVEN** — the container demonstrably never escapes and is never tied
  within the compilation unit, or
- **GUARDED** — an emitted runtime branch: a fast path for the plain case, a
  slow path dispatching through the MOP to `FETCH`/`STORE`/etc.

A design that treats provenance as statically settled will miscompile the
first time a container is tied at runtime.

### The complication: "compile time" is not a clean phase boundary in Perl

`BEGIN` blocks, `use` (itself `BEGIN require` + `import`), and string `eval`
all run arbitrary code *during* what would otherwise be "compile time,"
including installing ties. Measured: a `tie` inside a `BEGIN` block is live
for code compiled afterward in the same file. So the honest framing is not
"compile-time facts are proven, runtime facts are speculated" — it is that
facts are true as of the moment the producer (`B::SoN`, which runs at
`CHECK` time) walks the optree, and anything can change both before and
after that moment. Any escape/no-tie analysis this design relies on must be
robust to that, or it may not claim proof at all — only a guard.

---

## 7. Built / Designed / Open — summary

### BUILT (verified against `lib/`, with file:line evidence above)

- One IR machinery: `Chalk::IR::Node`/`Graph`/`NodeFactory`, 87 node classes,
  no competing hierarchy.
- Per-graph, per-factory hash-consing (`Graph.pm:15-19`, `NodeFactory.pm`),
  which supports a second graph population existing alongside the first.
- The type lattice (`TypeLibrary.pm`), canonical and zero-divergent against
  the producer's mirror.
- The `Chalk::IR::Value` / `Chalk::IR::Node` split, making value-ness
  structural.
- The `Pass` contract (`run($Graph) -> $Graph`, `Optimizer/Pass.pm`).
- `Slot` as the actual, working, in-use representation for an untyped
  memory cell, including a working boxing path (`_box_payload`) for every
  scalar type.
- The two-check coercion-elision rule (`is_subtype` AND `type_for`),
  stated in a target-side comment citing its source document
  (`Context.pm:3020-3026`).

### DESIGNED (agreed direction, not implemented)

- The graph→graph lowering pass itself. Zero exist; the seam to insert one
  at is three lines (`Target/LLVM.pm:53-59`).
  **Its first step is deleting the `representation` alias** — see below.
- Connecting `set_stamp` on load, so a chalk-typed graph is a live object
  and not only transient wire JSON.
- **Deleting `Chalk::IR::Node`'s `representation`/`set_representation` alias.**
  Under `docs/plans/2026-08-24-loader-analysis-pipeline.md` the loader moves
  onto the type axis and these two become DELIBERATELY SILENT forwarders onto
  `stamp`/`set_stamp`, so the backend's 43 reads keep working with no edits
  during the transition. There is no deprecation warning by design — the
  enforcement is that deleting the alias breaks compilation at every remaining
  caller. **Nothing will otherwise remind anyone the alias exists**, which is
  why its removal is recorded here as a named step of the lowering work rather
  than left to be rediscovered.
- Retiring `Slot` by threading access provenance through Stamp subclasses.
- **`%Slot` as the un-narrowed encoding on a narrowing ladder, NOT a
  general-purpose SV.** SSA fixes each slot's type at compile time, so the cell
  needs no type tag — only the defined-bit, which is genuinely dynamic.
  Monomorphism (`Array[Int]`) deletes the cell rather than merely eliding a
  tag; a provably-`Undef` slot collapses to a hash-consed singleton. This is
  why `%Slot` is a target type and not a lattice type. See §5.
- Recording `Undef` (not `Slot`) as the type of a statically-OOB element read,
  which is the first small case where the type/target split pays.
- Backward use-demand propagation as a smaller, prerequisite-satisfied first
  step toward informed representation selection.
- Modeling tie/magic as MOP-dispatched alternative implementations of the
  same access operations plain containers use.

### OPEN (unresolved questions, carried forward from the source documents —
not resolved here)

1. Whether the 87 node classes split, merge, or stay 1:1 under a lowered
   population; deciding which of the 94 measured representation-branch
   distinctions become node kinds is undecided.
2. Whether the 33 emission-scoped side tables in the LLVM target (encoding
   the *encoding* half of a representation — string length, undef-defined
   bit, slot payload, regex capture offsets) can be carried on lowered nodes
   directly, or need a separate design per table.
3. Whether the loader's existing iterate-to-fixpoint representation-seeding
   passes terminate unchanged if run over two graph populations in flight
   at once, rather than one.
4. What the demand lattice for backward use-propagation is (TurboFan's
   `Truncation` is a distinct, smaller lattice from the type lattice; reusing
   the type lattice for it is likely a category error) and what happens when
   two consumers disagree on demand.
5. Whether access-dispatch provenance belongs in `lib/Chalk/MOP/` (the
   existing class/method/field MOP) or a sibling protocol over a different
   kind of subject (containers).
6. What the slow path through a MOP `FETCH`/`STORE` dispatch actually costs
   on a runtime-free target — a real function-pointer call to emitted code,
   but the tied object is a blessed Perl object, and the machinery for that
   boundary does not yet exist.
7. What is *provable* for the escape/no-tie analysis a guard needs, given
   that "compile time" is not a clean phase boundary in Perl (`BEGIN`, `use`,
   string `eval` all run code that can install ties before or during
   compilation of later code) — whether a syntactic scan can ever be sound,
   or whether only a narrower provable subset (e.g., the self-hosting
   corpus) is reachable without a real escape analysis.
8. Whether machine-level coercion lossiness (e.g., `u64 -> i64` on an
   out-of-range value) is tracked in a new table, and whether selecting a
   representation and inserting its conversions can be kept as one atomic
   decision inside the lowering pass, as the safety argument in §4 requires.

---

## References

- `docs/research/2026-08-24-two-ir-architecture-alignment.md` — the
  measured audit this document's BUILT/DESIGNED/OPEN split is based on.
- `docs/research/2026-08-24-typed-memory-prior-art.md` — TurboFan/Graal
  primary-source research behind §5.
- `docs/research/2026-08-24-chalk-memory-model-baseline.md` — measured
  baseline of Chalk's current memory model behind §5.
- `docs/plans/2026-08-24-there-should-be-no-representation-field.md`,
  `docs/plans/2026-08-21-type-vs-representation-seams.md`,
  `docs/plans/2026-08-14-representation-is-the-targets-type-system.md` —
  the representation-axis design history behind §3 and §4.
- `docs/plans/2026-08-24-access-provenance-and-the-mop.md`,
  `docs/plans/2026-08-24-thread-use-information-to-lowering.md` — the
  access/provenance/MOP design behind §5 and §6.
- `docs/plans/2026-08-22-two-lattices-one-ir.md` — the resolved lattice
  unification behind §2.
- `docs/architecture/sea-of-nodes-ir.md` — node taxonomy, hash-consing
  protocol, and use-def chain mechanics not repeated here.
- `docs/architecture/typed-ir-representation.md` — an earlier
  representation design (2026-06/2026-08-14), largely superseded by §3-§4
  above; kept for its per-representation LLVM layout detail (`Str`, `Slot`,
  `Array`, `Hash`, `Object` shapes) which this document does not repeat.
- `docs/architecture/ir-lowering.md` — the codegen *pipeline mechanics*
  (BNF/Perl target entry points, emission dispatch, fixup passes); this
  document covers the type/representation axis that document does not.
