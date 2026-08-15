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
| `Undef` | **A UNIT TYPE: one value, no data — so the TARGET picks whatever constant suits it** (today an `i1` defined-bit that is constantly `false`). NO payload; see below. |
| `Slot` | `{defined: i1, payload: i64}` — the uniform field/element cell reused by `Array`, `Hash`, and class fields. The payload is a one-word UNION, not a pointer — see below. |
| `Array` | `{len, cap, %Slot*}`. |
| `Hash` | linear-scan table of `%HashEntry {key_ptr, key_len, key_enc, val_def, val_pay}`. |
| `ArrayRef` / `HashRef` | `i8*` to the boxed `%Array`/`%Hash`. |
| `Object` | `i8*` to `{%Cls.vt*, %Slot, ...}` (vtable ptr header + one `%Slot` per field). |

These reprs are **representation tags + LLVM types**, NOT IR nodes.

### `Undef` has NO payload (corrected 2026-08-14)

This table previously gave `Undef` the shape `{defined: i1, payload: i64}`,
identical to `Slot`. That was wrong, and the implementation already says so.
`Context.pm:713-718`:

> "The 'payload' (what the variable holds when it is defined) **is not needed**
> for a `Constant(undef)`: the defined bit is always false, so the payload is
> **never read**."

The emitted instruction is commented as dead on its face:

    %payload = add i64 0, 0    ; Constant(undef): payload i64 0 (never used)

The payload exists for ONE structural reason, stated at `Context.pm:716-718`:
`DefinedOr` (`$a // $b`) emits a `phi` that needs a value from BOTH incoming
edges, so the undef edge must supply something even though control never carries
a defined value along it — "the optimizer will eliminate the dead path but the
IR must be well-formed".

That is **phi-shaped scaffolding for one operation's lowering**, not part of what
`Undef` IS. `Undef` is a UNIT TYPE: exactly one value, carrying no information.
Its `i1` is a compile-time-constant `false`.

This matters beyond tidiness. `Bool` and `Undef` both lower to `i1`, and it is
tempting to treat them as two encodings of one machine type. They are not: a
`Bool`'s `i1` carries one bit of REAL information, while an `Undef`'s carries
NONE. That is the underlying reason `Coerce[Bool->Undef]` and
`Coerce[Undef->Bool]` are both refused (`Context.pm:1287`) rather than being
no-ops, and it is why the coercion rule needs its semantic leg — see
`docs/plans/2026-08-14-representation-is-the-targets-type-system.md`.

**RESOLVED (2026-08-14): `Undef` needs no representation. The TARGET picks
whatever constant suits it.**

`Undef` is NOT a fourth refusal class alongside `Scalar` / `Any` / `Unknown`.
Those refuse because something upstream FAILED — narrowing did not run,
inference did not run — and a refusal names a bug to go fix. `Undef` is a
legitimate, fully-known type that simply carries no data. There is nothing to
represent, so there is nothing to refuse.

The backend already implements this, in the fallback `DefinedOr` takes when the
side table has no entry (`Context.pm:2445-2453`):

    # Fallback: emit a zero of the result type if no payload was recorded.
    if ($llvm_type eq 'double') { emit "fadd double 0.0, 0.0" }
    else                        { emit "add $llvm_type 0, 0"   }

That is "whatever constant makes the target happiest" — a type-appropriate zero
synthesized on demand, needing no recorded value at all. (LLVM also has a
literal `undef` value available for this.)

So **`_undef_payload` is redundant with its own fallback**: `Context.pm:730`
records `add i64 0, 0`, `:2444` looks it up, and `:2447` synthesizes the
identical constant when the lookup misses. The table buys nothing.

The contrast with `Slot` twelve lines further down (`:2456`) is the proof:

    $self->{_slot_payload}{ $lhs_ref }
        // die "DefinedOr Slot LHS missing payload in _slot_payload table";

A `Slot` payload is REAL DATA that must be carried, so losing it is a bug and
the code dies. An `Undef` payload is a placeholder any target can mint from
nothing, so the code shrugs and emits a zero. Benign fallback vs `die` is the
implementation already distinguishing "has data" from "is a unit type".

### `Regex` is COMPILE-TIME ONLY (audited 2026-08-14)

`Regex` IS already in the lattice — `Regex => 'Scalar'` (`TypeLibrary.pm:16`), a
leaf type (`:52`) — and it appears in signatures (`split => ['Regex', 'Str',
'Num']`, `'=~' => { right => 'Regex' }`). What it does NOT have is a machine
type, and it never will in the current design.

Measured: `Regex` has **zero** repr branches in the backend. (An earlier count of
"3 branches" was wrong — those matched the OP NAMES `RegexMatch` / `RegexSubst`
/ `RegexCapture`, not repr checks.) A `qr//` literal is a `Constant` with
`const_type => 'regex'`, stamped `Regex` by the loader at `JSON.pm:1227`, whose
comment states the rule: "the matcher value the backend resolves **statically**".
`_lower_regex_match` reads the pattern from the NODE FIELD `$node->pattern` and
hands it to `_compile_regex_pattern` at COMPILE TIME, emitting a bespoke matcher.
The pattern is never an SSA value: never loaded, never phi'd, never passed.

So `Regex` is a FOURTH category, distinct from every other case in this doc:

| category | examples | `type_for` |
|---|---|---|
| real machine types | `Int`, `Str`, `Array` | a machine type |
| unit type | `Undef` | target picks any constant |
| no representation yet / wrong vocabulary | `Scalar`, `Any`, `List`, `Unknown` | refuse — names an upstream bug |
| **compile-time only** | **`Regex`** | **refuse — never reaches runtime** |

Its refusal message must differ from the others: not "narrowing failed", not
"wrong vocabulary", but "this value is resolved statically and never reaches
runtime". If it fires, the bug is that something tried to treat a pattern as a
RUNTIME value — which is the unbuilt `qr//`-as-function case the G6 scope
decision explicitly deferred (`Context.pm:5752`).

### Audit: every Perl ref type against the lattice (2026-08-14)

Enumerated by probing perl 5.42 with `ref()` on one instance of each kind, not
by reading documentation:

| `ref()` | Chalk type | status |
|---|---|---|
| `SCALAR` | `ScalarRef` | in lattice |
| `ARRAY` | `ArrayRef` | in lattice |
| `HASH` | `HashRef` | in lattice |
| `CODE` | `CodeRef` | in lattice |
| `GLOB` | `GlobRef` | in lattice |
| *(blessed)* | `Object` | in lattice |
| `Regexp` | `Regex` | in lattice, compile-time only (above) |
| `REF` | — | **ABSENT** |
| `VSTRING` | — | ABSENT, and correctly so |
| `LVALUE` | — | **ABSENT** |
| `IO` | — | ABSENT |
| `FORMAT` | — | ABSENT |

**`VSTRING` is NOT a gap.** Measured: `v65.66.67 eq "ABC"` is TRUE and its
`length` is 3 — a vstring IS a `Str` value. The `VSTRING` magic only preserves
the original literal so `sprintf("%vd")` can recover it. It needs no lattice
member; it needs `%vd` support if that idiom ever appears.

**`FORMAT` is NOT a gap.** Perl's formats are effectively dead; `\*FOO{FORMAT}`
does not even yield a `FORMAT` ref (measured: it gives `SCALAR`). Out of scope.

**`REF` IS a real gap, and a small one.** `ref(\$x)` is `SCALAR` but `ref(\\$x)`
is `REF` — perl distinguishes a ref-to-scalar from a ref-to-REF. Measured, they
dereference identically, so `ScalarRef` covers the mechanism; what is missing is
only the `ref()` STRING, which matters if a program branches on it. Low priority,
recorded rather than fixed.

**`LVALUE` and `IO`: SETTLED — neither is a lattice gap.** An earlier draft
called these "real gaps, not low priority", citing "lvalue 70 times and io 330
times" in `FromOptree.pm`. **Both numbers were substring noise and the
conclusion was wrong.** Re-measured with word-boundary patterns:

- **`io` -> 330 was garbage.** The matches were `condition`, `region`,
  `function`, `representation`, `iteration` — every word containing "io".
  Genuine IO-handle references (`\bIO\b|GvIO|IoIFP|filehandle|STDIN|STDOUT|
  STDERR`): **10**, and reading them, ALL TEN are about `print`'s stdout effect
  or the existing GAP for an explicit filehandle (`FromOptree.pm:2482-2485`:
  "GAP: $name to an explicit filehandle ... writes only to stdout; honoring a
  handle would misroute"). There is no IO-handle VALUE anywhere — the explicit
  filehandle form is already a loud, deliberate refusal. `IO` is not a type the
  producer can currently emit, so it needs no lattice member until filehandles
  are built.

- **`lvalue` -> 54 genuine matches, but they are the WRONG SENSE.** Every one is
  about `OPf_MOD` context — a padsv/gvsv being an ASSIGNMENT TARGET
  (`FromOptree.pm:1153`, `:1641`, `:1788`). That is lvalue CONTEXT, a property of
  how an op is used, not the `LVALUE` REF TYPE that `\substr($s,0,1)` produces.
  Searching for actual LVALUE-ref handling (`\substr`, refgen-over-substr) finds
  **nothing**. The producer cannot emit an `LVALUE` ref at all.

So both are correctly absent from the PRODUCER. Checked independently against
the Perl SOURCE that Chalk must actually compile — `lib/`, `t/`, and the
producer's own `lib/` — since "the producer cannot emit it" and "no input needs
it" are different claims:

| | `lib/` | `t/` | perl5-son `lib/` |
|---|---|---|---|
| LVALUE refs (`\substr`, `\pos`, `:lvalue`) | 0 | 1 file | 0 |
| IO handle VALUES (`*STDIN{IO}`, `IO::Handle`, `fileno`) | 1 file | 0 | 1 file |
| filehandles at all (`open`/`close`/`<$fh>`) | 0 | — | — |

Every hit is a false positive, read individually:

- `t/bootstrap/perl-recognize-phase3.t:113-117` uses `:lvalue` as ATTRIBUTE
  SYNTAX in a grammar-recognition test (`method name :lvalue() { }`) — parsing
  only, no lvalue-ref value is ever constructed.
- `lib/Chalk/Grammar/Perl/PrecedenceTable.pm:62` and
  `perl5-son/lib/SoN/FromOptree/OpMap.pm:283` are the NAME `fileno` appearing in
  a keyword list and an opcode table respectively — operator metadata, not an IO
  value.

And `lib/` contains **zero** `open`/`close`/`readline` — Chalk's self-hosting
source does no file I/O at all. So neither type is reachable from the producer
NOR needed by any input on the self-hosting path.

The lesson is the one this project keeps relearning — a raw `grep -c` of a short
token measures nothing. `io` as a substring appears in a third of the English
words in a compiler.

Revised status: of the five absent ref types, **NONE is a gap that blocks
anything**. `VSTRING` is a `Str`, `FORMAT` is dead, `REF` is a `ref()`-string
nicety, and `LVALUE`/`IO` are unreachable from the producer. The lattice is
COMPLETE for every value Chalk can currently construct.

### OPEN: who owns a Str's bytes? (raised 2026-08-15, must be answered before
### the `%Str` migration can be called complete)

`{ptr, len, enc}` says what a string IS. It does not say where its bytes LIVE,
and measured, Chalk's Str producers use three different storage classes:

| producer | bytes live in | lifetime |
|---|---|---|
| `_lower_constant` | a private global (`getelementptr [N x i8]* @.str`) | whole program |
| `_lower_concat` | `malloc` heap | until freed (never — leaked, deliberately) |
| `_emit_int_to_str` / stringify | **`alloca` stack** | **until the frame exits** |
| `_box_payload` | `malloc`'d `%StrPair` | escapes the frame |

**`alloca` vs `malloc` is a lifetime distinction, not a performance one.**
`alloca` allocates in the CURRENT STACK FRAME and is reclaimed automatically
when the function returns, so any pointer to it DANGLES once the frame exits.
`malloc` allocates on the heap and survives the frame. So a Str that can outlive
the function that built it MUST be heap or global; a stack one is a
use-after-free waiting for a consumer that outlives the frame.

`_lower_concat` already states the rule in its own comment:

> "The allocation is malloc (not alloca) — SOUND for G4 aggregates where Str
> values escape function frames. alloca would be unsound once a Str escapes its
> defining frame."

…and stringify uses `alloca` regardless. The soundness argument is therefore
PER-PRODUCER and enforced by comment, with nothing in the type or the code
saying which kind of pointer a given `%Str` holds. The corpus cannot catch the
difference: `main` does not return before the process exits, so a dangling
stack Str is indistinguishable from a live one there.

**The likely answer is a SINGLE STRING CONSTRUCTOR.** Today each producer
open-codes its own allocation, which is exactly why they disagree — the same
shape as the four-places-must-agree layout bug fixed in 180546fe, and as the
repr registries this whole line of work is collapsing. One constructor makes the
storage rule an INVARIANT rather than a convention: every `%Str` is built one
way, and "Str bytes are never `alloca`" becomes true by construction instead of
by review. It also gives the encoding field one place to be set, and a future
free/refcount one place to hook.

Three candidate resolutions, smallest first:

1. **Invariant, no new field.** Str bytes are ALWAYS heap-or-global, never
   `alloca`. Stringify's `alloca` becomes a bug to fix. The type stays
   `{ptr, len, enc}`. Matches what `_lower_concat` already argues.
2. **Ownership tag as a fourth field.** A `%Str` records static/heap/stack.
   Honest, but GC-adjacent and much larger than this migration.
3. **Status quo.** Works only while everything leaks or lives in globals, and
   silently breaks the first time a Str must be freed or a frame must be reused.

(1) is the smallest correct answer and is what the single constructor would
enforce. NOT resolved here, and NOT folded into the `{ptr, len, enc}` migration:
that migration is already a flag day across ~27 consumer sites, and bundling a
lifetime change would make it unreviewable. Recorded so it cannot be quietly
skipped — **the `%Str` work is not complete until this is answered.**

#### Can LLVM run a destructor when a string's lifetime ends?

**No. LLVM has no objects, no lifetimes, no scopes and no RAII** — it is
deliberately below that level. A `call @free` is just a call; nothing invokes it
for you. Destructors are a FRONTEND concept: C++ and Rust both emit the calls
explicitly and LLVM only sees the calls. So any destructor here has to be
CHALK's, which is a further argument for the single constructor: if every string
is minted in one place, that is the only place that could ever pair allocation
with release.

Three adjacent mechanisms exist and are worth knowing before designing one:

- **`llvm.lifetime.start` / `llvm.lifetime.end`** — intrinsics marking when an
  `alloca`'s memory is live. OPTIMIZER HINTS, not deallocation: they enable
  stack-slot reuse and use-after-scope detection. They call nothing, and apply
  only to `alloca`, not `malloc`.
- **`invoke` / `landingpad` / `cleanup`** — how C++ destructors actually run
  during unwinding. The frontend emits cleanup blocks and LLVM routes control
  there as an exception propagates. Real machinery, but it is for UNWINDING, and
  Chalk's `Unwind` is currently a hard `exit` rather than a stack unwind.
- **GC intrinsics (`gcroot`, statepoints)** — LLVM does support precise GC by
  letting a frontend mark which SSA values are heap references so a collector
  can find roots. The closest thing to "the system knows this value owns
  memory".

Scope note: Chalk currently LEAKS every string deliberately. `_lower_concat`'s
comment says the malloc leak "is acceptable for main()-returns-then-process-
exits patterns". Freeing at all is a larger question than this migration, and it
interacts with the `Slot` payload — a boxed `%StrPair*` in an array element has
the same ownership question as a bare Str.

### `Slot` vs a reference: what the payload actually is

The `Slot` payload is **NOT a pointer**. It is a ONE-WORD (i64) UNION whose
interpretation is fixed by the container's inferred element repr, and
`_box_payload` (`Context.pm`) enumerates the cases:

| element repr | what the i64 holds | how |
|---|---|---|
| `Int` | the value itself | passes through |
| `Num` | the value itself | `bitcast double -> i64` (one word, no precision lost) |
| `Bool` | the value itself | `zext i1 -> i64` |
| `Str` | a POINTER | heap-allocated `%StrPair`, `ptrtoint` — a Str is a (ptr,len) pair and does not fit in one word |
| `ArrayRef` / `HashRef` / `CodeRef` / `Object` | a POINTER | `ptrtoint i8* -> i64` |

So a payload is a pointer only when the value does not fit in a word. Int, Num
and Bool are stored INLINE. "The payload is a pointer to another data structure"
is true for exactly the boxed half of that table.

**Functionally, then, what distinguishes a Slot from a reference?**

- A **reference** is a first-class VALUE with its own repr (`ArrayRef`,
  `HashRef`, `CodeRef`, `Object`), and it is always a pointer. `\@a` and `@a`
  share backing storage; a reference can be copied, returned, stored, and
  compared as a value in its own right.
- A **Slot** is a STORAGE CELL, not a value. It is the uniform cell an `Array`
  element, a `Hash` value, or a class field lives in. It is never itself a Perl
  value: it is always read THROUGH (unboxed at the use site) or written INTO.
  Its defining feature is the `defined` bit — a Slot can be EMPTY, which no
  reference can be.

The overlap that makes them look alike is that both are one machine word, and
for the boxed reprs a Slot's payload is bit-identical to the reference it holds.
But the direction of the relationship differs: a reference POINTS AT an
aggregate; a Slot IS A CELL WITHIN one. And a Slot additionally answers "is
anything here?" — a question a bare pointer cannot express.

The `defined` bit is structural, not speculative: `%HashEntry` is
`{i8*, i64, i32, i1, i64}` (`Target/LLVM.pm:1212`) — key ptr, key len, key
encoding, **val_def i1**, val payload — so the emptiness bit is carried per
entry in the realized layout. NOT VERIFIED: whether `exists`/`delete` and array
holes are currently WIRED to that bit; I found no code connecting them, so the
bit's availability is confirmed while its consumption is not.

## Coerce (resolved)

`Coerce` is the node `Chalk::IR::Node::Coerce`, parameterized by `from_repr`/`to_repr`
(both in `content_hash`) — a single node, not a sub-kind per coercion, and a node
rather than an edge annotation. (This resolves the two questions previously open
here.) It is a hash-distinct, explicit-on-edge node: a representation change is
always a visible node in the graph, never an implicit reinterpretation.

## Open questions
1. Whether the `Str` `encoding` enum is widened beyond the ASCII slice to the full
   tagged set (UTF-16/ShiftJIS/EBCDIC) — tracked GAP, decide as idioms force it.
