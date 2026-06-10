# Typed IR Representation Model

**Status: PROPOSED — committed as the design basis for the LLVM codegen axis
(Phase 3), VALIDATED for the trivial case + ARCHITECTURE-REVIEWED with review
holes closed; to be validated INCREMENTALLY for the rest by the LLVM corner.**

- **Validated (trivial case):** the `return 1 + 2` → hand-written LLVM IR → real
  `lli` (15.0.7) → compare-to-perl loop runs and matches (both `3`). Proves the
  toolchain works and the model's lowering target is reachable for the
  no-coercion/no-Scalar/no-variable case. The lowering compiler does NOT exist
  yet (the `.ll` at `t/spike/llvm/add.ll` is hand-authored, standing in for it).
- **Architecture-reviewed:** `paad/architecture-reviews/2026-06-06-typed-ir-representation-model-review.md`.
  Three HIGH holes found and now CLOSED in this doc: H1 (hash-consing vs
  representation → §1a: representation is out-of-hash, per-use, Coerce-on-edge),
  H2 (coercion placement unverifiable → the well-typed-graph CHECKABLE invariant),
  H3 (Scalar fallback false-green → §4a: on the L corner, Scalar is a GAP, no
  libperl, mandatory coverage metric). MED items M1 (Int overflow-to-NV) and M3
  (DualVar/Bool/Undef/Ref) folded into the guard specifics.
- **Still to validate (incrementally, by the LLVM corner):** coercion nodes
  (`"42" + 1`), the Scalar-GAP path, Phi/backedge coercion ordering (review M2),
  and everything past pure literal arithmetic. Treat those as design intent, not
  established fact (cf. the work-in-progress status of `perl-type-system-formal.md`).

## Relationship to the formal type system

`docs/architecture/perl-type-system-formal.md` defines **what Perl's types ARE**:
a latent, operational lattice (`Int <: Num <: Str <: Scalar`, plus
Ref/Object/List/...) where membership is defined by coercion round-trips and
operational contracts. In that model a value like `"42"` is *simultaneously* a
`Str` and a `Num` and an `Int` — the types are properties of a value's behavior
**under coercion**, not properties of how it is stored.

This document defines **how we REPRESENT typed values in the IR**. It is the
representational counterpart to the formal doc. The two are a pair:

- Formal doc: the **legality** layer — which coercions exist / are valid, and
  therefore which subtype relationships hold.
- This doc: the **representation** layer — what a value at rest actually IS in
  the IR, and how the latent duality is expressed structurally.

## The core model

### 1. A value at rest has exactly ONE representation

The IR is SSA. A value is a single def. **That def has a single, definite
representation** — a machine-level shape: `i64`, `f64`/`double`, a raw pointer, a
struct, or (the fallback, see §4) a boxed Perl `SV`.

The formal type system's duality ("`42` is both a number and a string") is **NOT**
modelled as a polymorphic value at rest. There is no register that is "secretly
both an int and a string." A value is, at rest, one representation.

#### 1a. Representation is OUT of `content_hash` — a per-use decoration (resolves review H1)

The SoN graph is hash-consed: identical-content nodes share one object, keyed by
`content_hash` (`Node.pm:79`). Representation is **NOT part of `content_hash`**.
It is a per-use decoration, exactly like `control_in` and `schedule_data`
(`Node.pm:28-38`, which are hash-excluded with the documented rationale that
different *uses* of the same content must still hash-cons to one node).

Consequence, stated directly (the same-literal-two-representations case): a
literal `1` is **one** hash-consed def, and it carries **one** representation.
If one consumer needs that `1` as `i64` and another needs it as `Str`, they do
**NOT** fork the def into two nodes. The def keeps its single representation; the
consumer that needs a different representation gets an explicit **`Coerce` node on
its edge** (§2). Cross-representation need is reconciled on the EDGE, never by
splitting the value's identity.

Why not in-hash: putting representation in `content_hash` would make
`Constant(1, Int)` and `Constant(1, Scalar)` distinct nodes, splitting value
identity and breaking the formal doc's observational-equivalence premise (`42`
and `"42"` must remain one value). Representation is a property of *how a def is
used/lowered*, not of *what value it is* — hence per-use, hence out-of-hash.
(Contrast `const_type`, which IS in the hash because it is a structural property
of the literal's source form, not a lowering decision.)

The `Coerce` node itself (§2): its from/to representation IS part of its identity
— a `Coerce[Str→Num](x)` and a `Coerce[Str→Int](x)` are different nodes — so two
consumers needing the *same* coercion of the same value share one hash-consed
`Coerce` node (SSA-clean). (Resolves open-question #3 and review M2.)

### 2. The latent-type duality lives on the EDGES, as explicit coercion nodes

Where Perl would *implicitly* coerce — `$x + 1` when `$x` is a string, or
`"$n"` when `$n` is a number — the IR carries an **explicit `Coerce` node** on
the edge between the producer and the consumer. The coercion node is the
materialization, in the graph, of the formal doc's coercion judgment `v ⇓^T u`.

```
Perl source:   my $y = $x + 1;     # $x is a Str
IR (sketch):   $x : Str
               c  = Coerce[Str→Num]($x)     # explicit; = the ⇓^Num judgment
               $y = Add(c, Const[Num] 1)    # Add consumes Num, produces Num
```

`Add` requires `Num` operands. It does not "accept anything and coerce
internally." The coercion is a separate, visible node. This is exactly how a
normal typed SSA IR works (LLVM makes you write `sitofp`, `zext`, `bitcast`
explicitly); Perl's promiscuous implicit coercion is simply **implicit edges the
front-end must make explicit when building the IR.**

### 3. Subtyping IS the set of legal coercion nodes

`Int <: Num <: Str` from the formal lattice is **implemented** as: "there exists
a legal `Coerce[Int→Num]` / `Coerce[Num→Str]` node the IR may insert on an edge."
Subtyping is not a runtime tag carried on a boxed value; it is the **rule set for
which coercion nodes are insertable**. The lattice is the legality layer for
coercion-node insertion. (This is the "atoi/atoc-like structures implicit to
implement the subtype system" made explicit: each implicit Perl coercion becomes
a concrete node.)

### 4. `Scalar` / boxed-SV is the TOP representation — the conservative fallback

Some values cannot be pinned to a machine representation at IR-build time: a
value read from `<STDIN>`, the return of an un-analyzed sub, a DualVar, a tied or
overloaded value. These take the representation `Scalar` — a **boxed Perl `SV`**.

`Scalar`/boxed-SV is the **top of the representation lattice** — the
conservative, always-correct fallback — exactly as `Scalar` is near the top of
the latent-type lattice. The boxed SV is the *fallback* representation, not the
*default*: the IR commits to a precise representation wherever it can prove one,
and falls back to `Scalar` where it genuinely cannot.

#### 4a. On the L (LLVM) corner, `Scalar` is a GAP — NOT a libperl fallback (resolves review H3)

The LLVM corner's entire purpose is to prove the IR is **self-sufficient**
(runtime-free). Letting it emit libperl calls for `Scalar` values would let it go
green by always falling back — proving nothing, the exact false-green the plan's
"cannot link libperl, cannot cheat" rationale exists to prevent.

Therefore, **the L corner does NOT link libperl and does NOT emit libperl calls.**
A value of representation `Scalar` reaching the L corner is a **GAP**:
"cannot lower runtime-free here" — a legitimate IR-is-dynamic signal recorded in
the gap-map, NOT a pass. (libperl-backed lowering of `Scalar` values is the C/XS
corner's job, Phase 3e — a *different* corner with a *different* question.)

**Mandatory runtime-free-coverage metric:** because `Scalar` is a GAP not a pass,
each idiom's L-corner result must report what fraction of its values/ops lowered
runtime-free vs. fell to `Scalar`-GAP. An idiom is L-GREEN only if it lowers
**fully** runtime-free and matches perl. "Mostly Scalar" cannot read as green —
the coverage metric makes the self-sufficiency claim measurable rather than
silently escapable.

## The well-typed-graph invariant (CHECKABLE — resolves review H2)

"Correctly-typed graph" must be a **checked property, not a hand judgment** —
otherwise the hand-authored-graphs-are-the-spec trust story is un-audited (the
latent-vs-representation decision would just move silently into the hand-author's
head). The invariant the harness MUST enforce:

> **For every operation node, each operand's representation equals the
> operation's required operand representation. The ONLY legal bridge between a
> differing producer representation and a required consumer representation is a
> `Coerce` node. An operation whose operand representation differs from its
> requirement WITHOUT an interposed `Coerce` is a malformed graph.**

This is total and cheap (a single graph walk: for each op, check each operand's
representation against the op's signature; flag any unbridged mismatch). The
harness runs it on every graph — hand-authored or (eventually) parser-produced —
so a mis-typed hand graph FAILS LOUDLY at the invariant rather than silently
producing wrong code or a false green. This makes "the hand graph IS the spec"
an *auditable* claim. (It is the representation-layer analogue of EagerPinning's
control-edge well-formedness checks.)

## Lowering becomes a normal backend, not a runtime reimplementation

Given the model, lowering an IR to any target is mechanical:

- **Each value** → its representation's machine type (`Int`→`i64`,
  `Num`→`double`, ..., `Scalar`→`SV*`).
- **Each `Coerce` node** → the corresponding conversion:
  - representation-widening coercions are cheap/no-op (`Int→Num` ≈ `sitofp` or a
    free widen; `Int→Str` of a literal folds at compile time);
  - a genuinely dynamic coercion (`Str→Num` on an arbitrary runtime string) →
    a real conversion (`atoi`/`strtod`) **or** a libperl call, and this is the
    one place the dynamic/failure/warning behavior (the NaN, dualvar, locale,
    `"0 but true"` concerns from the formal doc) is localized — on the coercion
    node, not smeared across every value.
- **Each operation** (`Add`, etc.) → the native op on its operand
  representation (proved-`Int` `Add` → `i64 add`), or a libperl call when an
  operand is `Scalar`.

So "lower to LLVM" is **not** "reimplement Perl's value semantics." It is
"lower single-representation values + explicit coercion nodes," with libperl
calls only where the representation is genuinely `Scalar`.

## The three axes of the typed-IR contract (collapsed by this model)

The contract a node must satisfy to lower runtime-free, restated under this model:

1. **Latent type** (`Int/Num/Str/Ref/...`) — the legality layer; from
   `perl-type-system-formal.md` + the existing `TypeInference` semiring. *Have it.*
2. **Representation** — falls out of §1: a value's representation IS the machine
   type of its def. There is no separate late "boxed-vs-unboxed inference"; the
   IR-builder commits a representation at value creation, and `Coerce` nodes
   bridge between representations. (Today representation is decided LATE in the
   C-backend `StructPromotion` pass; under this model it must be carried ON THE
   GRAPH from value creation. That move is the substance of Phase 3c.)
3. **Coercion explicitness** — the IR-builder/front-end MUST materialize Perl's
   implicit coercions as explicit `Coerce` nodes governed by the lattice. This is
   a NEW clause in the parser's eventual output contract: "emit a `Coerce` node
   wherever Perl would implicitly coerce." A correctly-typed graph is one in
   which every operation's operands already have the operation's required
   representation (reached via explicit coercions), so codegen never coerces
   implicitly.

The "unboxing guards" framed earlier (no magic/overload/tie/dualvar,
integer-stays-integer) are subsumed here: they are the conditions under which a
value may be GIVEN a non-`Scalar` representation in the first place (or under
which a `Coerce` node is elidable). A value that fails them simply gets
representation `Scalar` and is handled by the fallback path. The formal doc's
semantic-contract violators (NaN ∉ Num, DualVar ∉ Int, tie/overload break
contracts) ARE these guards.

### Guard specifics (resolves review M1, M3)

- **Int overflow-to-NV (M1):** Perl integers silently promote to floating-point
  (NV) on overflow. So `Int` representation = `i64` is sound ONLY under a
  proven-no-overflow guard; an UNGUARDED runtime `Int + Int` must carry an
  `overflow → Coerce(Int→Num)` path (the result widens to `double` on overflow),
  or remain `Scalar`. The trivial literal case `1 + 2` is overflow-free by
  constant-folding; a runtime `$a + $b` of two `Int`s is NOT, absent range
  analysis. State this on every `Int` arithmetic op: native `i64 add` requires
  the no-overflow guard, else the overflow-Coerce edge.
- **DualVar (M3):** `DualVar ∈ Scalar` but ∉ `Int`/`Num`/`Str` (formal doc). A
  value that is or may be a DualVar gets representation `Scalar`; giving it `Int`
  would miscompile (it has independent numeric/string faces). The "not a dualvar"
  guard gates non-`Scalar` representation.
- **Bool / Undef (M3):** representable precisely (`i1`/a tagged niche) but until
  an idiom forces it, both fall to `Scalar` early. Decide their precise
  representation when a corpus idiom demands it.
- **Ref / Object / ArrayRef / HashRef (M3):** representation deferred (a pointer
  to a struct, layout TBD) — see open-question #1. Until then, `Scalar`.

## What this contract demands of the parser (the backward-propagated spec)

Per the CodeGen-verified-first inversion (define the IR from the backend's
needs; the parser comes to meet it), this model adds to the parser's eventual
output contract:

1. Assign each produced value a representation (precise where provable, `Scalar`
   otherwise).
2. Insert explicit `Coerce` nodes wherever Perl semantics imply an implicit
   coercion, governed by the latent-type lattice.
3. Never rely on the codegen to coerce: operations receive operands already in
   the required representation.

Until the parser does this, the contract is specified — and validated — by
HAND-AUTHORED typed graphs (the same way the rest of the harness specifies the
IR without waiting for the untrusted parser).

## Validation plan

- **3a (first validation):** hand-author the typed graph for `return 1 + 2`
  (two `Int`-representation literals → `Add` → `Int` result, no `Coerce` needed,
  no `Scalar` anywhere), lower SoN→LLVM IR, run via `lli`, compare behavior to
  the same source under perl. Green confirms the model end-to-end for the
  trivial case.
- **Next:** `"42" + 1` (forces an explicit `Str→Num` `Coerce` node, literal-
  foldable) — validates the coercion-node mechanism.
- **Then:** a value of representation `Scalar` (e.g. an un-analyzed input) —
  validates the boxed-SV fallback + the "cannot lower runtime-free → gap" signal.
- Each validated idiom either fits the model or forces a documented revision to
  this doc. The model is proven incrementally by the LLVM corner, not asserted.

## Realized representation lattice

The runtime-free LLVM campaign (G2–G5) forced the lattice members and they are now
load-bearing in `Chalk::Target::LLVM`:

| Representation | LLVM type / shape |
|----------------|-------------------|
| `Bool` | `i1`. |
| `Int` | `i64`. |
| `Num` | `double`. |
| `Str` | `{ptr, len, encoding}` where `encoding` is a tagged enum (UTF-8/UTF-16/ShiftJIS/EBCDIC), not a bool flag. ASCII slice implemented; non-ASCII is a tracked GAP. |
| `Undef` | tagged scalar `{defined: i1, payload: i64}` (the niche-encoding alternative was rejected). |
| `Slot` | `{defined: i1, payload: i64}` — the uniform field/element cell reused by `Array`, `Hash`, and class fields. |
| `Array` | `{len, cap, %Slot*}`. |
| `Hash` | linear-scan table of `%HashEntry {key_ptr, key_len, key_enc, val_def, val_pay}`. |
| `ArrayRef` / `HashRef` | `i8*` to the boxed `%Array`/`%Hash`. |
| `Object` | `i8*` to `{%Cls.vt*, %Slot, ...}` (vtable ptr header + one `%Slot` per field). |

These reprs are **representation tags + LLVM types**, NOT IR nodes.

## Coerce (resolved)

`Coerce` is the node `Chalk::IR::Node::Coerce`, parameterized by `from_repr`/`to_repr`
(both in `content_hash`) — a single node, not a sub-kind per coercion, and a node
rather than an edge annotation. (This resolves the two questions previously open
here.) It is a hash-distinct, explicit-on-edge node: a representation change is
always a visible node in the graph, never an implicit reinterpretation.

## Open questions
1. Whether the `Str` `encoding` enum is widened beyond the ASCII slice to the full
   tagged set (UTF-16/ShiftJIS/EBCDIC) — tracked GAP, decide as idioms force it.
