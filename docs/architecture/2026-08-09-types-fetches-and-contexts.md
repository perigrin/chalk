# Types, fetches, and contexts

**Status:** architecture note. Design only — nothing here is built.
**Origin:** perigrin, in conversation 2026-08-09. The model is his; the measurements
and the code citations are mine, gathered while he developed it.

**Provenance discipline.** Every claim below is marked:

- **[MEASURED]** — a command was run and its output read
- **[CODE]** — a file:line was read
- **[MODEL]** — perigrin's design position; not yet built, not yet falsified
- **[OPEN]** — genuinely undecided

This matters because on 2026-08-09 alone I committed a 0-byte design doc and cited it
as a plan's source, propagated numbers nothing backed, and recorded a guess as a cause.
This note is written to be checkable.

---

## The problem this replaces

The compiler has **47 places** that ask "did anyone work out this node's type?" and no
one place whose job that is. They are **not all the same guard** — the count covers two
distinct conditions, and conflating them was itself an error in an earlier draft:

| | count | condition | status |
|---|---|---|---|
| **absent** | 31 `_require_repr` call sites **[MEASURED]** | repr is `undef` | **live** — these fire |
| **absent** | 1 signature guard, 2026-08-09 (`_repr_to_llvm_type`, commit `1617a6a3`) | repr is `undef` | **live** |
| **present but unlowerable** | 15 `repr=Scalar` refusals in `Target/LLVM/Context.pm` **[MEASURED]** | repr is the string `Scalar` | **dormant** |

The 15 are dormant because **nothing anywhere assigns that value** — 0 hits for
`set_representation('Scalar')` or `representation => 'Scalar'` in either repo
**[MEASURED]**. So they are currently *unreachable*, not a live cordon. They matter as
**evidence of intent** (someone expected a type name to arrive in a representation field,
which §6 says is the category error) and as a **hazard the moment §7's narrowing starts
producing `Scalar`**, not as 15 firing checks today.

The honest statement is: **32 live guards for an absent type, plus 15 dead guards written
against a type that should never have been a representation.** Both are a cordon around a
missing subsystem; only the first is currently load-bearing.

### How a cordon accumulates

Each guard was written by someone treating *"we don't know the type here"* as a
situation to **survive** rather than to **fix**. That instinct is easy to reproduce — I
generated three fresh instances of it while this note was being written, and each was
corrected:

| I claimed | actually |
|---|---|
| the silent bail at `JSON.pm:1105` is safe, since GAP-not-miscompile holds | the engine hiding that it failed to trace the flow |
| 3 corpus cases carry untyped nodes and run, so an assertion would redden the gate | missed narrowing — a stopped clock, not a constraint to preserve |
| the checker would reject `my $x = pop @a`, which is routine Perl | it rejects **unnarrowed** `pop`, correctly, and points at `@a` |
| parameterisation must land *before* the checker, or it rejects `pop`/`keys` corpus-wide | those rejections are the **deliverable** — a worklist of under-determined code (§7) |

The pattern is treating a **correct refusal as a cost to engineer around**. Every guard
in the cordon is that instinct made permanent.

**It survives being documented.** The fourth row was written into §7 *in the same commit
as the first three rows* — the table was already on the page. A reader extending this
design should assume the pull applies to them too, and should read a new refusal as
evidence of a missing capability rather than as an obstacle to the change in hand.

**And the subsystem is largely already written, orphaned.**
`lib/Chalk/Grammar/Perl/TypeLibrary.pm` **[CODE]** already contains:

```perl
my $num_num_num = { left => 'Num', right => 'Num', result => 'Num' };
my $str_str_str = { left => 'Str', right => 'Str', result => 'Str' };
for my $op (qw(+ - * / % **)) { $BINARY_OP_SIGNATURES{$op} = $num_num_num; }
$BINARY_OP_SIGNATURES{'.'} = $str_str_str;
```

plus `type_satisfies` (membership), `is_subtype`, `narrow_type`, `get_binary_op`,
`get_unary_op`. The only piece genuinely missing is a `join` **[MEASURED: 0 subs
matching `join|lub|meet|unify`]** — and per §3 below, `join` is needed only at merges.

The B::SoN path has never used it, and instead grew an ad-hoc stamping engine inside
`lib/Chalk/IR/Serialize/JSON.pm` whose rules can state things Perl does not permit (§1).

**[MEASURED 2026-08-09, correcting an earlier "822 lines, 15 subs" in this note that
labelled a *region* as the *file*]** — the file is **1446 lines, 23 subs**. The stamping
machinery is **13 subs and 4 tables** spanning `:606`–`:1430`; that span is 825 lines, of
which ~638 are stamping once the two non-stamping subs inside it (`from_json` `:667-756`,
`_replay_classes` `:784-880`) are excluded. The producer's own copy
(`~/dev/perl5-son/lib/SoN/IR/Serialize/JSON.pm`) is 1334 lines / 21 subs.

The corrected number is *smaller* than the one it replaces and the argument is unchanged:
a several-hundred-line hand-maintained stamping engine exists beside an orphaned type
library.

---

## 1. Operators state REQUIREMENTS on their operands

> **[REVISED 2026-08-09 after adversarial review.]** This section first said "each
> operator has a fixed signature; the result comes from the signature, not the operands."
> That is **false for a large part of Perl's operator set** and was falsified by the very
> table this note holds up as the answer — see *Where the fixed-signature claim breaks*
> below. The surviving, load-bearing claim is about **requirements**, not results.

**[MODEL]** Perl's dynamism is in its *values*, not in what its operators *demand*. Each
operator states a **requirement on each operand**: `+` requires `(Num, Num)`; `.`
requires `(Str, Str)`. **That requirement is fixed, knowable from a table, and
independent of what actually flows in.**

Result types are a separate question and are *not* uniformly fixed (below).

**[MEASURED] The loader's rule violates the requirement side.** `%_COMPUTED_REPR` says
`Add => 'join'`, which joins operand representations and can therefore stamp an `Add` as
`Str`. `+` never yields a `Str`. Measured on `my $a = "3"; my $b = "4"; $a + $b`:

**[MEASURED] The loader's rule violates this.** `%_COMPUTED_REPR` says `Add => 'join'`,
which joins operand representations and can therefore stamp an `Add` as `Str`. Measured
on `my $a = "3"; my $b = "4"; $a + $b`:

```
loader:  Constant repr=Str, Constant repr=Str, Add repr=Str
backend: %tmp_3 = add i64 %tmp_1, %tmp_2   ; Add(repr=Int) -> i64 add
lli:     error: '%tmp_1' defined with type 'i8*' but expected 'i64'
```

Two independent defects pointing opposite ways — the loader stamps `Str`, the backend
ignores the stamp and emits `i64` — and **neither caught it. `lli` did.** That is not
GAP-not-miscompile working; that is invalid IR reaching the assembler.

`TypedInvariant.pm` says `Add => 'Int'` **[CODE]**, which is closer to correct, but it
**has no `lib/` consumer** **[MEASURED: 1 `lib/` reference, itself; 8 in `t/`]** — the
compiler never type-checks its own IR. So the loader and the backend can hold
contradictory beliefs about the same node indefinitely.

### The correction

**[MODEL]** `join` is the wrong operation at an operator. Join is for **merges**. An
operator's result type comes from its **signature**, not from its operands. The question
at an operand is not "what do I convert to" but **"is this value a member of the type
this operator requires"** — the round-trip membership test, already implemented as
`type_satisfies`.

The example that shows why this is membership and not conversion: `Int <: Num <: Str`,
so `"3"` genuinely *is* a member of `Num` and `"3" + "4"` needs no type change.
`"hello"` is a `Str` that is **not** a member of `Num`. Same static type, different
answer.

**[NOTE]** `type_satisfies` **[CODE: `TypeLibrary.pm:169`]** returns `true` when the
actual type is `undef` — permissive by default. So membership alone does not catch an
unstamped operand; that is what §3's unconditional coercion is for.

### Where the fixed-signature claim breaks

**[CODE]** `TypeLibrary.pm:272-294` — several operators are genuinely operand- or
context-dependent, and the library already says so:

| operator | library says | why |
|---|---|---|
| `&&` `\|\|` `//` `and` `or` `=` | `(Any, Any) → Any` | **returns one of its operands**; the result really does depend on them (`%_COMPUTED_REPR` agrees: `And => 'same'`) |
| `x` | `(Str, Int) → Str` | context-dependent — `(0) x 3` is a **list** in list context |
| `..` | `(Int, Int) → List` | context-dependent — the **flip-flop** operator in scalar context |
| `&` `\|` `^` | `(Int, Int) → Int` | since 5.22 these are numeric **or string** bitwise, by operand |

So "the result comes from the signature" holds for arithmetic and concatenation — the two
we generalised from — and **fails** for the logical, repetition, range and bitwise
families. Any table encoding results must mark which operators are context-sensitive
rather than pretending a single row covers them.

**The requirement side survives all four.** `&&` requiring `Any` is not a counterexample:
its requirement genuinely *is* "anything." §3 depends only on requirements, so it is
unaffected by this correction.

---

## 2. There is no representation layer — it is types, at two levels

> **[REPLACED 2026-08-09, perigrin.]** This section previously argued that "representation
> is a separate question from type" and that membership and storage are orthogonal
> concerns. **That framing is itself the muddle it was trying to describe.** perigrin's
> correction: *it's just types — LLVM type vs Chalk type — and repr comes for free with
> the LLVM type.* The measurements below support the correction, not the original claim.

**[MODEL, perigrin]** There are **two type levels and one map**:

```
Chalk type  (Int, Num, Str, Bool, Undef, ArrayRef, …)     — what the IR node carries
     │
     └── per-target map (§8) ──▶  LLVM type (i64, double, i8*, i1, …)
```

**"Representation" is not a third layer between them.** It is the *image* of a node's type
under the target's map. Once the LLVM type is chosen, the representation **is** that — the
bit layout comes with it. There is nothing left for a separate field to hold.

### The measurement: `representation` is the type field under a second name

**[MEASURED 2026-08-09]** `%STAMP_TO_REPR` (`IR/Serialize/JSON.pm`), the map from the
producer's type stamp to `representation`, is **the identity map**:

```perl
my %STAMP_TO_REPR = (
    Int => 'Int',  Num => 'Num',  Str => 'Str',
    Boolean => 'Bool',            # the only non-identity entry: a rename
    Undef => 'Undef',  Object => 'Object',
);
```

Five of six entries are `X => 'X'`; the sixth respells `Boolean` as `Bool`. So the pipeline
is **Chalk type → (rename) → "representation" → `_repr_to_llvm_type` → LLVM type**, and
only the last arrow is a real map. The middle step converts nothing.

**[MEASURED]** Instrumenting `set_representation` across all 161 corpus cases (gate green
at 161 with the probe in place) records **2022 assignments over 13 distinct values**:

| value | count | a Chalk lattice type? |
|---|---|---|
| `Int` `Str` `Bool` `Undef` `ArrayRef` `Object` `Num` `HashRef` `Array` `Regex` `Hash` | **2013** | **yes — all 11** |
| `Slot` | 6 | no — a tagging discipline for `Undef ∪ T` |
| `Control` | 3 | **no — not a value type at all** |

**99.6% of everything ever assigned to `representation` is a Chalk type name.** The field
does not hold a distinct kind of information; it holds the type, spelled again.

### The two exceptions prove the point rather than rescuing the field

Neither leftover is a *lower* layer:

- **`Slot`** is the LLVM *struct name* for what should be a lattice type — see below.
- **`Control`** is not a value type in any sense. It marks a node as control-flow, which
  produces no value. **[CODE]** It enters through hand-written corpus spec annotations —
  `%if = If(%c) :Control` (`t/corpus/mdtest/logical.md:720-724`) — where an author put a
  *node classification* in the slot meant for a value's type and nothing objected.

That a node classification can be stored in this field without complaint is the clearest
evidence that it is not a typed layer at all.

### `Slot` is not `Maybe[T]` — it is `Maybe[word]`, and the erasure is lossy

**[MEASURED 2026-08-10]** `%Slot = { i1 defined, i64 payload }`
(`Target/LLVM/Context.pm:3436`). The payload is a **fixed `i64`** with values punned into
it — `ptrtoint i8* to i64` for `ArrayRef`/`HashRef`, direct for `Int`, and a **GAP** for
everything else:

> *"GAP: ArrayRef element[$i] repr=$elem_repr cannot be stored in an i64 Slot payload
> (only Int/ArrayRef/HashRef are lowered)"* — `:3490`, and the same at `:1456`

So `Num` and `Str` GAP. **There is no `T` in a `Slot`.** The payload is untagged —
nothing in it records whether that `i64` was an integer or a pointer — and `T` is
recovered *one level up*, from the container (`_element_repr`, `JSON.pm:1154`, reads the
element type off the container's literal elements).

**It does not "punt to `Scalar`"; it punts to something weaker.** `Scalar` is a boxed SV
that carries its own tag. A `Slot` payload carries none, which is exactly why the
lowerable set is the three `i64`-shaped types and everything else refuses.

**[MEASURED] The runtime already has what the lattice lacks.** A dynamic out-of-bounds
read lowers correctly — the backend emits the defined-bit phi (`:3819-3824`) and
`my $r=[10,20]; my $i=5; defined($r->[$i])` matches perl. So `Maybe[Int]` **exists in the
emitted LLVM**; the node is merely typed plain `Int` while the value is a tagged pair.
`Slot` is that unnamed type's LLVM struct name leaking upward into the type field — the
last instance of this section's muddle once `Control` is set aside.

Note `Undef → i1` as well: the tag with no payload. `Undef` and `Slot` are one idea at two
arities.

**[OPEN] `Maybe[T]` as a constructor, or general union types?** `Maybe[T]` is `T ∪ Undef`.
A narrow `Maybe[T]` constructor sits alongside §7's `Array[T]`/`Hash[T]` and maps
per-instantiation (`Maybe[Int] → {i1,i64}`, `Maybe[Num] → {i1,double}`), which dissolves
the GAPs because nothing must fit a fixed word. General unions are the more honest answer
but change `join` everywhere: today `join(Bool,Int) = Scalar` (the LCA, §6's "correct and
unstorable"); under unions it is `Bool ∪ Int`, which *is* storable. Not resolved here.

**[MEASURED] Chasing this question turned up a live silent miscompile** — a nested rvalue
deref through a missing intermediate does not autovivify
(`my $r=[10,20]; my $v=$r->[5][0]; print scalar(@$r)` — perl `6`, chalk `2`, no GAP).
Filed as **E1** in `docs/plans/2026-08-03-effect-chain-followups.md`.

It matters here because the same syntactic read has two types depending on its
**consumer**: `my $v = $r->[5]` is `Maybe[Int]`, while `$r->[5][0]` guarantees `ArrayRef`
and never Nothing. So **"is this fetch `Maybe[T]`?" cannot be answered at the fetch site**
— §4 and §5 again.

An earlier draft concluded from this that `Maybe[T]` needs a *"does this fetch CREATE?"*
effect axis beside it. **That is wrong and is retracted** (perigrin, 2026-08-10): the
difference is one of **requirement**, not of node kind, and §3 already handles it —
autovivification is a *coercion*. See §3's "the rule reaches further than scalars". The
fetch stays pure.

That also settles `Maybe[T]`'s status here: if arrays can be extended with holes then
**every Perl array is `Array[Maybe[T]]`**, holes being legal Perl — which makes
`%Slot = {i1,i64}` the correct representation of `Maybe[T]` rather than an oddity.

### What this changes downstream

- **`%_REPR_RANK` — `Int < Num < Str` — is the type lattice**, not a representation
  ordering. It is `Int <: Num <: Str` with the subtyping written as a rank.
- **`%OP_REQUIRED_REPR` and `%_COMPUTED_REPR` are type tables** wearing repr names — which
  is why they contradict each other (§1) and why §7's library subsumes both.
- **`_repr_to_llvm_type` is the only genuine map**, and §8 already says it is per-target.
  XS would map `Scalar → SV*` where LLVM cannot map it at all.
- **`from_repr`/`to_repr` on `Coerce` should be types**, and the node should say
  `Coerce(to => Num)` in the *Chalk* vocabulary. The backend decides what that costs.

**The renaming is not cosmetic.** As long as a field called `representation` exists beside
`stamp`, every pass has to decide which one it means, and the answer "they are the same
thing" is not available while both exist.

### One type per definition: most recent usage

**[MODEL, perigrin]** Of the candidate policies — narrowest type's, most recent usage's,
per-use with conversion at every boundary, or both faces retained (Perl's own SV, and the
DualVar foundation) — **most recent usage is the natural fit for an SSA IR.**

The reason is specific to SSA: a value is defined once and never mutated, so it can carry
exactly **one type**, with explicit `Coerce` on the edges that need another. There are no
faces to keep in sync and nothing to invalidate. A mutable-slot model would need
DualVar-shaped storage; SSA does not.

**This is why there is no room for a representation layer (§2).** A separate per-node
representation would only earn its place if one definition could need two machine shapes
at once. Under SSA it cannot: the edge that needs a different shape gets a `Coerce`, which
is *another definition* with its own single type. The second field has nothing left to say.

**It also retires "write-once stamping" as an obstacle.** Write-once is *correct* under
SSA — you never re-stamp a definition, you insert a `Coerce`. The current engine's failure
is not that it cannot re-stamp; it is that it has no `Coerce`-insertion, so its only
options are "be right first time" or "decline."

---

## 3. Insert `Coerce` UNCONDITIONALLY at build time, keyed only on the requirement

> **[REVISED 2026-08-09 after adversarial review.]** This section first justified
> build-time insertion by saying "the operands are known, **hence their reprs**." The
> first half is right and the inference is wrong. We hold the operand *node* — we are
> injecting the `Coerce` between a known producer and a known consumer. But a node's
> **type** is assigned by a later widening fixpoint, so holding the node tells us nothing
> about its repr yet.
>
> The repair is not to move the work into a pass. It is to stop *copying* the operand's
> type at all, and read it from the input edge at the point of use.

**[MODEL, perigrin]** Insert the coercion **when the node is constructed** — we are wiring
the params, the input is right there — and key it **only on what the operator requires**.
You never need to know the operand's *type*, because the requirement is enough:

- the operator's requirement is **knowable at build time**, from the table (§1)
- the source type is **whatever the operand turns out to be**, resolved later by inference
- an **identity** coercion (source already satisfies the requirement) folds away
- an **impossible** one errors *at the coercion*, by which point both types are known and
  the message can name both

So coercion placement becomes **syntactic** — driven by signatures — and inference merely
*resolves* coercions rather than deciding where they go. That inverts the dependency the
review correctly identified as circular.

### The concrete defect: `from_repr` is a denormalized copy, not a missing fact

> **[SHARPENED 2026-08-09, perigrin.]** An earlier version of this subsection said
> `from_repr` "cannot be known at build time." **That is imprecise and it obscures the
> actual bug.** When we build a `Coerce` we are *injecting it between a known producer and
> a known consumer* — we are holding the input node. The input is known.
>
> What is not known at that moment is the input's **type**. And `from_repr` is not an
> independent fact: it is a **copy of `inputs[0]`'s representation**, taken at
> construction. The defect is not a missing input. It is **denormalized state captured
> before the value it copies has settled.**

**[CODE]** `lib/Chalk/IR/Node/Coerce.pm:16,20`:

```perl
field $from_repr :param :reader;   # required — no default
field $to_repr   :param :reader;
```

**`from_repr` duplicates information the node already carries on its input edge.** That
duplication forces every consequence the review found:

**[CODE]** `SoN/FromOptree.pm:109-117` — Slice A must therefore inspect the stamp and
give up when it is absent:

```perl
sub _coerce_int_to_num ($factory, $node) {
    my $stamp = $node->stamp;
    return $node unless defined $stamp && $stamp->type eq 'Int';
```

…so build-time coercion fires **only for pre-stamped operands** — and §4 establishes that
pad reads, the most common operand, carry no stamp. An earlier revision of this note
called that precedent "already proven." It is proven for a subset that excludes the hard
case.

**A coercion should carry only its target.** `Coerce(to => 'Num')`. The `from` is read
from `inputs[0]` **at the point of use**, when it is settled.

### The copy contradicts the IR's own stated contract

**[CODE] `Chalk::IR::Node:133-139` says the opposite of what `Coerce` does:**

```perl
# Late-binding setter for the machine-level representation.
# Called by the IR builder or a lowering pass after the node is
# constructed. Does not affect content_hash or hash-consing identity.
method set_representation($repr) { $representation = $repr; return; }
```

The framework's contract is explicit on both points: representation is **late-bound**, and
it is **not part of identity**. `Coerce` violates both — for its *neighbour's*
representation. It binds `inputs[0]`'s repr **early** (at construction) and makes it
**identity-bearing** (`content_hash`, `Coerce.pm:24-29`).

**The `content_hash` justification does not survive reading.** The comment argues:

> *"`Coerce[Str->Num](x)` and `Coerce[Str->Int](x)` are distinct nodes."*

Both examples have the **same** `from` and differ only in `to`. The whole argument is
carried by `to_repr`. And `from` cannot vary independently of the input: `_serialize_inputs()`
already hashes `inputs[0]`, and in SSA one node has one representation — so
`from_repr` contributes **nothing** to the key that the input edge does not already
contribute.

### The staleness hazard — HYPOTHESISED, TESTED, FALSIFIED

**[FALSIFIED 2026-08-09. This note previously claimed a staleness hazard here. I went
looking for the RED and it does not exist. Recording the negative result, because a
hazard I asserted and did not test would have sent the next reader hunting a bug that
cannot happen.]**

**The hypothesis was:** representation is discovered by a widening fixpoint
(`set_representation` is called at **15 sites** in `lib/Chalk/IR/Serialize/JSON.pm`
**[MEASURED]**, including `$widest` at `:1107`), so an input's repr could move after a
`Coerce` on it was built, leaving `from_repr` stale and sending `_lower_coerce` down the
wrong arm — `sitofp i64` on a value now `i8*`.

**It cannot happen.** Three facts make the two sets **provably disjoint**:

1. **[CODE]** `_coerce_int_to_num` (`SoN/FromOptree.pm:109-117`) wraps **only** nodes the
   producer has **already stamped `Int`**. An unstamped node passes through unwrapped.
2. **[CODE]** That wire stamp is applied in `_deserialize_graph` (`:503`), which runs in
   `from_json` **before every inference pass** — verified by reading the pass order.
3. **[MEASURED]** Every chalk-side inference site is **write-once**: `:584`, `:658`,
   `:952/:956`, `:1043`, `:1346`, `:1360`, `:1422` all guard with
   `next if defined $node->representation` (or the `unless`/`!defined` equivalent). The
   fixpoint at `:1039-1109` is a **filling** loop, not a widening one — `:1043` skips any
   node that already has a repr.

So the nodes that receive a `Coerce` (producer-stamped) and the nodes that receive a
late chalk-side repr (unstamped at produce time) **do not overlap**.

**[MEASURED] Empirical confirmation.** I patched `set_representation` to warn whenever it
was called a second time with a *different* value, and ran the full corpus:

```
RESTAMP count: 0
not-ok count: 0
# TOTAL: gate-green=161  behavior=161  shape=161  invariant=161  gap-declared=21  worklist=0
```

**The probe was smoke-tested in both directions** before the result was believed: a
same-value re-stamp is silent, a differing re-stamp prints
`RESTAMP: node id=1 op=Constant Int -> Str`. And the corpus genuinely exercises `Coerce` —
`arithmetic.md:90-91,230-231` carry four `Coerce(Int -> Num)` nodes, `logical.md:394` one
`Coerce(Int -> Bool)` — so the zero is coverage, not absence.

### What that changes: the bail is what keeps `from_repr` honest

**This is the interesting part, and it inverts the argument.** The guard this section
called the defect —

```perl
return $node unless defined $stamp && $stamp->type eq 'Int';
```

— is **exactly what guarantees `from_repr` is never stale.** Conditional insertion and
consistency are the *same property*. `from_repr` is redundant, but it is redundant and
**correct**.

So:

- **The correctness argument for deleting `from_repr` collapses.** It is not a live
  miscompile and must not be filed as one.
- **The coupling argument survives and is sharpened:** you **cannot** make insertion
  unconditional *while keeping* `from_repr`, because unconditional insertion is precisely
  the case where the field would go stale — you would be wrapping unstamped nodes, whose
  reprs chalk assigns later. The §3 redesign and the field deletion are **one change, not
  two**, and doing them in the wrong order manufactures the very bug this section
  hypothesised.

That is a **design constraint discovered by failing to find a bug**, which is a better
outcome than the bug would have been.

**[MEASURED] Incidental finding from the probe programs.** A two-callsite polymorphic
divide (`sub half { ... $n / 2 } half(10); half("20")`) does not reach the type question
at all — it GAPs earlier, on `my ($n) = @_` list-assign arity binding
(`Context.pm:4439`), and in its `shift`-based form on `Stringify from repr=Num`
(`Context.pm:930`). The `:658` monomorphic-callee assumption is real and documented in
its own ponytail comment, but nothing in reach today exercises it.

### The change is a deletion — an ENABLER, not a bugfix

**Sequenced with §3, never before it.** Nothing is broken today (above), so deleting
`from_repr` on its own buys nothing; deleting it is what makes unconditional insertion
*possible*, because with the field gone there is no early copy left to go stale.

The reader is already in position: `_lower_coerce` reads `$node->from_repr` at `:1022`
and calls `lower_value($node->inputs->[0])` at `:1024`. **The input node is in hand one
line later, at the moment its repr is finally settled.** Reading
`$node->inputs->[0]->representation` removes the copy without adding a lookup.

**[CODE] One consequence to plan for, not to discover:** dropping `from_repr` from
`content_hash` changes the hash-cons key, so two coercions to the same target on the same
input become **one node** where today they are two. That is correct — they *are* the same
coercion — but it is a hash-consing change, and this codebase has already been bitten by
id-keyed cache collisions. Treat it as a named migration step with its own corpus
evidence, not as a field deletion.

**[MODEL, §8]** And the vocabulary is wrong in the same way: `from_repr`/`to_repr` are
**representation** names on a **target-agnostic IR node**. Representation is the
backend's business (§8). The node should carry a *type*; the backend maps it.

### The rule reaches further than scalars: autovivification is a coercion

**[MODEL, perigrin 2026-08-10]** The requirement-driven rule is not limited to widening
`Int` to `Num`. **Perl's autovivification is an instance of it.** Given
`my $r = [10,20]; $r->[5][0]`:

| | operand | requirement | coercion |
|---|---|---|---|
| outer | `Array[Int,2]` | `Array[_, ≥6]` | extend the array |
| inner | `Undef` (the new slot) | `ArrayRef` | allocate an empty arrayref |

Nothing new is needed: the access **states a requirement**, the operand does not satisfy
it, a `Coerce` is inserted unconditionally. `Coerce(Undef → ArrayRef)` — "make an empty
arrayref" — is exactly what perl does.

**This is load-bearing for §4 and §5.** Chalk does not do it today: it is a **live silent
miscompile**, filed as **E1** in `docs/plans/2026-08-03-effect-chain-followups.md`
(`print scalar(@$r)` — perl `6`, chalk `2`, no GAP, in three variants including through an
alias). Reading it as a coercion rather than as a side effect **removes** a "does this
fetch CREATE?" effect axis that an earlier draft of that file proposed: the fetch stays
pure and the requirement carries the work. The leaf-vs-chain difference is a difference of
**requirement**, not of node kind — `my $v = $r->[5]` requires nothing of `$r`, so nothing
fires and the result is honestly `Maybe[Int]`.

**[OPEN] The cost, which must be designed rather than assumed: coercions that store.**
Every `Coerce` today is pure (`sitofp`, `zext`, `icmp`). An array-extending coercion
mutates a heap object **visible through other references** — measured: adding
`my $s = $r` and printing `scalar(@$s)` gives perl `6`, chalk `2`. `Coerce` has no memory
input (`Coerce.pm`: `from_repr`, `to_repr`, `inputs`) while `Subscript` already takes one.
So `Coerce` must either split into pure and memory-transforming kinds or gain an optional
memory edge. Smaller than a new effect axis, and it reuses existing machinery — but **a
coercion that stores is a new thing in this IR.**

### What this collapses

- **coercion placement needs no type information** — only the operator's requirement.
- **operands are coerced to fit, never joined.** The partial-join bail
  (`JSON.pm:1105`) leaves the operator path.
- **`join` is needed only at `Phi`.**
- the loader's fixpoint **is not deleted** — the review was right that it cannot be. Its
  job *shrinks*: it types nodes, which is inference's actual work, instead of doubling as
  a coercion-placement oracle.

---

## 4. Fetches are one operation, parameterised by context

**[MODEL, perigrin]** `PadAccess`, `StashAccess`, `Subscript`, `FieldAccess` and
`Constant` are all **fetches**. They differ only in which context they read.

**[MEASURED] The current model conflates location with value.** For
`our $g = 5; my $x = $g; $x`:

```
1  StashAccess  inputs=[]     repr=Int
2  Constant     inputs=[]     repr=Int
3  Assign       inputs=[1,2]  repr=-      <- node 1 is the STORE TARGET
4  Return       inputs=[1]    repr=-      <- node 1 is ALSO the LOADED VALUE
```

The same node is the location written to *and* the value read back, and it has been
stamped `repr=Int` — a category error, since a location has no value type. It has
`inputs=[]`: **no memory edge, no connection to its defining store.**

**[MEASURED]** Only rvalue `Subscript` carries a memory input (`[container, index,
memory]`). `PadAccess`, `StashAccess`, `FieldAccess`, `Length` do not. So four of five
fetches cannot find the store that defines them, which is why their repr must be guessed
— and why it is simply absent when the guess is unavailable.

**That is a memory-model gap, not a type-inference gap.** The four ring files blocked on
"NO representation" (`cmdopt.t`, `colon.t`, `decl.t`, `package_block.t`) **[MEASURED]**
are waiting on memory-SSA reaching the pad and stash, exactly as it already reaches
array elements.

**[CODE] The code already knows they are the same kind of thing:**
`FromOptree.pm:3942` builds a `FieldAccess` and `:3949` a `PadAccess` — adjacent
branches of one function.

### "Inherit from the store" is not always one hop

**[CORRECTION 2026-08-09]** An earlier draft of this section, and the migration note
below, described a fetch as *inheriting* its type from its defining store — as though it
were always a single lookup. **Loop-carried fetches are not.**

A loop-header `Phi` is constructed **before its backedge input exists**
**[MEASURED: `set_backedge` is called at 6 sites in `~/dev/perl5-son/lib/SoN/FromOptree.pm`
— `:2485`, `:2742`, `:2887`, `:2891`, `:3002`, `:3006`; an earlier "3" in this note came
from reading a `head -3`-truncated listing as a total]**. So a fetch whose defining store
is a loop-carried `Phi` cannot be typed at construction: the value it inherits from is not
yet wired.

That is the honest boundary between §3 and §4:

- **Coercion placement** needs no types and stays fully build-time (§3).
- **Fetch typing** through a straight-line store is one hop.
- **Fetch typing** across a backedge is **fixpoint-dependent**, and the fixpoint is
  exactly what §3's clean-up leaves the loader still doing.

The fixpoint does not disappear; it stops being asked questions it cannot answer.

---

## 5. Contexts are labels, borrowing rules, and lifetimes

**[MODEL, perigrin]** Pad and stash are **leaky implementation detail from Perl**.
Philosophically they are contexts distinguished by three properties:

| axis | what it determines |
|---|---|
| **labels** | how things are named — the part Perl leaks most and that matters least |
| **borrowing rules** | who can see or reference it → **alias analysis** |
| **lifetime** | when it is created and destroyed → **representation scope** |

**The example that proves mechanism is the wrong axis:** a `field` is implemented as a
kind of lexical pad but has an **entirely different lifetime** — object lifetime, not
scope lifetime. Model on the mechanism and you get aliasing and kill behaviour wrong in
both directions.

### Two consequences

**Precise kill sets.** The `Call`-as-memory-transformer note
(`2026-08-06-f3-call-as-memory-transformer-design.md`) adopted Graal's conservative
`any()` default. Under borrowing rules that is needlessly coarse: **an un-referenced
lexical cannot be reached by a call, so a call does not kill it.** `any()` is correct
only for the stash and for anything a reference has escaped to. This is precision
derived from the language's own scoping, without an escape analysis.

**Lifetime bounds the representation decision.** A lexical's representation can be
settled within its scope. A package variable outlives every scope and may be written
from anywhere, so "most recent usage" has no bounded window over it. That — not the
storage mechanism — is why the stash is harder than the pad.

### This is the prior art, arrived at independently

`docs/research/2026-08-02-effect-ordering-prior-art.md` records C2's alias indices and
Graal's `LocationIdentity`: *"a global `ANY_LOCATION` that aliases with everything,
disjoint per-field classes, and **immutable classes that alias with nothing**."*

The constant pool is the immutable class — which is exactly why `Constant` needs no
memory edge and carries an intrinsic type, while the other four do need one.

It also completes a symmetry: **"an assignment is a call minus uncertainty"** was the
write side. A fetch is a load minus uncertainty about *where*. `Call` kills `any()`;
`Assign` kills one location; a fetch reads one location. One memory model.

---

## 6. Two tops: `Unknown` errors, `Any` permits

**[CODE]** The canonical lattice (`docs/architecture/perl-type-system-practical.md:83`)
writes the top as one node, `Any/Unknown`. **[MODEL, perigrin]** These are two distinct
types and the split is what makes the rest work:

| | role |
|---|---|
| **`Unknown`** | the **default** top. If it survives to the type check, that is an **error**. |
| **`Any`** | an **explicitly permissive** top. Opted into; does not error. |

**This is what makes inference total, and it relocates the loud failure correctly.**
The bail at `JSON.pm:1105` should not `die` — it should **assign `Unknown`**. Then:

- inference always assigns something and never declines; there is no "no rule matched,
  skip" case and no `undef` in the representation field
- the **checker** reports the failure, which is the component whose job that is, and it
  reports *all* of them at once rather than whichever one lowering happened to reach
- `Any` is the user's explicit opt-out

`Unknown` — not `Scalar` — is also what makes the **join total**. `Bool ⊔ Int = Scalar`
(their LCA, both being under it); `Str ⊔ List = Unknown`. Every pair has an answer, so
there is no case to skip at. An earlier draft of this note proposed "make the join total
by producing `Scalar` at the top"; that aimed at the wrong element.

### `Scalar` and `List` are ephemeral

**[MODEL, perigrin]** `Scalar` is a sibling of `List` **[CODE: the lattice tree]**, and
both are **ephemeral types without representation**. **Storing one is an error.**

That makes the join's answer honest as well as defined: `Bool ⊔ Int = Scalar` is correct
*and* unstorable — you cannot store "either a Bool or an Int" without a box. The join
succeeds; the **check** rejects the store. The failure lands where the impossibility
actually is, rather than at whichever instruction first needed a machine type.

So the 15 backend `repr=Scalar` guards **[MEASURED]** are right to refuse — but **not for
the reason an earlier draft gave.** That draft said they were catching "a type name that
leaked into the representation field." Per §2 there is no separate field to leak into:
**every** value in there is a type name, and `Scalar` is unremarkable company.

What they are actually catching is `Scalar` **having no image under the LLVM map** — it is
a type the LLVM target cannot lower, exactly as §8 describes. That is a per-target fact,
not a category error: **XS could map `Scalar → SV*`.** The guards belong in the backend,
which is where they are; what they should say is *"this target has no type for `Scalar`"*,
not *"this value is malformed."*

**[CODE]** Note `Scalar` is *inhabited*, not merely abstract — the practical doc at :235
says so, `DualVar` being the example. So `DualVar` support and the boxed representation
are the same unlock.

**[CODE]** `None` ("never returns") is already in the lattice — and, correcting an earlier
claim in this note that it was **unused**, it is **already in use**:
`TypeLibrary.pm:127` gives `die` the signature `(Any) → None`. It is the type-level
counterpart to `Unwind`, and the library already says so.

**`None` is the BOTTOM type. [RESOLVED 2026-08-09, perigrin.]** A doc/code disagreement
was surfaced here and has been settled in favour of the code.

`TypeLibrary` **[CODE: `:10`, `:86-87`, `:191-194`]** says three times that `None` is
bottom — subtype of everything, `$TYPE_BITSET{None} = 0`, and `is_subtype` returning true
whenever the child is `None`. The canonical lattice document drew it as a **child of
`Any`/`Unknown`**, a sibling of `Scalar`/`List`/`Code`/`Glob`. **The document was wrong**
and has been corrected (`docs/architecture/perl-type-system-practical.md`).

Bottom is also the reading the rest of this note needs. `die`'s signature `(Any) → None`
**[CODE: `:127`]** is only usable in an expression position because `None` satisfies
whatever that position requires — which is what being bottom means. And the encoding is
right in both directions: `is_subtype('None', X)` is true by the explicit rule, while
`is_subtype(X, 'None')` is false for every other `X`, since `(0 & X_bits) == X_bits`
fails for nonzero `X_bits`. **No code change is required** — this was documentation drift,
not a defect in `is_subtype`, and §1's membership check is unaffected.

---

## 7. Declarations compile into the library

**[MODEL, perigrin]** Known globals go in the **default** type library — *and that is
what a source-level declaration compiles to*. One mechanism, not two: built-ins are the
pre-populated entries, user declarations extend the same structure.

`+ : (Num,Num) → Num` and `$0 : Str` are the same kind of fact — statements about the
language, not about the program. Neither is inferable; neither should be.

**[CODE]** `runtime-free-boundary.md` already classifies these by implementation
(*"`$!` = errno (Num face) + strerror (Str face)"*; *"`%ENV`, `@ARGV` = host process
state … host-interface layer, NOT libperl"*) but nowhere are those facts written as
**types** a compiler pass can consult.

Examples the library should carry: `$0 : Str`, `@ARGV : Array[Str]`, `%ENV : Hash[Str]`,
`$$ : Int`, `$! : DualVar`, `@_ : List`.

**Consequences for the clone** — these change its shape, and matter before it is written:

- **It cannot be a constant table.** Today `%BINARY_OP_SIGNATURES` is a `my` hash in a
  lexical block. If declarations compile into the library it must be **instantiable and
  extensible per compilation**.
- **Entries need scope.** `my Int $x` is block-scoped; `$0 : Str` is global. A
  declaration's scope *is* a context (§5), with the same borrowing and lifetime
  properties.
- **Four table families**, not one: binary ops, unary ops, builtins **[CODE: `push`,
  `pop`, `shift`, `splice`, `keys` carry `arg_types`/`return_type`]**, and known globals.

### Parameterised types are where narrowing is recorded

**[MEASURED]** The library's projections return the container's *top*, not its element
type:

```
pop    : (Array) → Scalar        keys   : (Hash) → List
shift  : (Array) → Scalar        values : (Hash) → List
unshift: (Array, Any) → Int      <- correct; returns the new length
```

`pop : (Array) → Scalar` is the **right answer for an unnarrowed `Array`** — and it is
unstorable, correctly. The defect is that the library cannot express the *narrowed* case,
so every case degrades to the worst one. The signature must be `pop : (Array[T]) → T`,
so that narrowing on the container reaches the projection.

**[MEASURED] The backend has already hit this wall and worked around it.**
`_lower_builtin_shift_pop` (`Context.pm:3871`) does `my $repr = $node->representation //
'Int'` then GAPs on anything but `Int` — a hardcoded guess standing in for a capability
the library lacks. Another of the 47 guards.

**[MODEL, perigrin] The degenerate answer is fine; the missing narrowing is the
problem.** `pop : (Array) → Scalar` guaranteeing only an ephemeral type in the generic
case is *correct*, provided flow analysis narrows in real contexts — `@a` assigned
`(1,2,3)`, or only ever pushed `Int`s, is `Array[Int]`, and `pop @a` is `Int`.

**And when narrowing fails, the error is the deliverable.** If there is not enough in the
source to narrow `@a`, that is precisely what the developer needs to be told — a reader
cannot tell what is in that array either. The checker's complaints are a worklist of
genuinely under-determined code, not noise to suppress.

So parameterisation is **not** a precondition for avoiding errors. It is **the vocabulary
narrowing is recorded in**: without `Array[T]`, flow analysis has nowhere to put what it
learned, and every case collapses to the degenerate one whether or not the information
was available.

This lands on the direction already recorded (2026-04-25): *flow-typing à la TypeScript —
narrowing along control-flow edges*. Perl's narrowing sources include assignment, the
values flowing in via `push`, `ref()`, `looks_like_number`, and explicit declarations
(§7).

**[NOTE — the pattern survived being documented.]** An earlier revision of this section
called parameterisation a "sequencing constraint: it must land before the checker is
turned on, otherwise the checker rejects `pop`/`shift`/`keys`/`values` corpus-wide." That
was a **fourth** instance of the instinct catalogued in *How a cordon accumulates* — and
it was committed in the same change as that table. Arranging the work so the compiler
does not complain, rather than reading the complaint. Corrected by perigrin, 2026-08-09.

**[MEASURED]** The IR already carries element types (`Target/LLVM/Context.pm`, both
`Serialize/JSON.pm`); the corpus records *"the loader lifts the field type + element
type"*. So the **IR is more expressive than the type library** — the gap is the library's
alone.

### `push` is not evidence of this gap

**[MODEL, perigrin]** `push @a, LIST` genuinely takes an `Array` plus one-or-more
elements of any type — `Scalar ∪ List`, effectively the top. `push : (Array, Any)` is
**correct**, not a limitation. The gap is specifically in **projections**: operations
returning something *drawn from* the container.

---

## 8. The type→target map is a coercion, and it is per-target

**[MODEL, perigrin]** `_repr_to_llvm_type` is not a selector with a guard. **The LLVM
type *is* the representation, for that backend** — so the function is
`coerce(SoNType → LLVMType)`: a **map**, whose domain is exactly the types that target
can represent.

Lookup failure **is** the error, structurally. Ephemeral types are absent *by
construction* rather than rejected by an added check.

**[MEASURED] What that subsumes:**

| today | under the map |
|---|---|
| the `//= die` signature guard (commit `1617a6a3`) | `undef` is not a key |
| **15** separate `repr=Scalar` guards in `Context.pm` | `Scalar` is not a key |
| part of the 31 `_require_repr` sites | absence of an entry already answers |

Fifteen guards written one at a time, each catching the same thing at a different call
site, all subsumed by not putting `Scalar` in the table.

**[MODEL]** This is the same mechanism as §3 at a different scale — value coercions on
edges, type coercions at the backend boundary. It is also what
`2026-07-19-runtime-mop-coerce-multimethod.md` already asserts: the compiler's own passes
*are* coercions, `coerce(SoNGraph, LLVMIR, $program)` being *"LITERALLY the same
operation as `coerce(Int, Str, $v)`"*.

### Three different reasons a type is absent from a map

**[MODEL, perigrin]** "Ephemeral" is not one property:

| | why absent | permanent? |
|---|---|---|
| `Unknown` | an **error state**, not a kind of value | never in any target's map |
| `List` | no runtime object — a context that flattens | ephemeral everywhere |
| `Scalar` | **this target** has no representation for it | **target-specific** |

**[MODEL, perigrin] The map is per-target.** `Scalar`'s absence from the LLVM map is not
a fact about `Scalar` — it is a fact about **runtime-free lowering**.
`docs/architecture/runtime-free-boundary.md` is the constraint that says no libperl,
therefore no `SV*`, therefore no box. An XS/C target built on `SV*` would map
`Scalar → SV*` and those 15 guards would have nothing to guard.

So **the map's domain is the expression of the runtime-free boundary**, not an incidental
limitation.

Two consequences:

- **The map belongs with the target, not with the type library.** The library says what
  types exist and how they relate; each backend says which it can represent. That keeps
  `SoN::TypeLibrary` target-agnostic, which matters with two lowering axes (LLVM live,
  C/XS parked **[CODE: `xs_target_evolution` — C plus thin per-class wrappers, no
  `Target/XS.pm` by design]**).
- **"Should we build the box" is not one question.** In LLVM it is real work *and* in
  tension with the runtime-free premise. In XS it is free. So `DualVar`, `Any`, and
  unnarrowed `Scalar` are cheap on one axis and expensive on the other — an argument for
  the C/XS target beyond "another backend".

**[MODEL]** It also reframes a failure mode: a program that fails to compile under LLVM
for want of narrowing may compile under XS, because `SV*` absorbs what runtime-free
cannot. That is the boundary working, visible as two domains for one map.

**[OPEN]** Nothing in `lib/` currently knows which types are ephemeral — the distinction
exists only in `perl-type-system-practical.md` and in this note. The split has to become
something code can consult.

---

## What remains genuinely inference

After §3 (coercion placement becomes syntactic) and §4 (fetches inherit through memory
edges rather than guessing), the residue is small — but it is **not zero, and it is not a
one-hop walk**:

- **`Phi`** — a real merge; the only place `join` is needed
- **Loop-carried fetches** — a `Phi` typed after its backedge is wired (§4), so this is a
  **fixpoint**, not a lookup. The loader keeps one; it just stops being the thing that
  also decides where coercions go.
- **`Call` return types** — interprocedural, including the recursion cycle that blocks
  `fib` **[MEASURED: `fib` dies at `Context.pm:687`, "Add node has no representation"]**

All three are real problems. None is the sprawling type system this looked like before the
operator and fetch cases were separated out — and the middle one is the reason the
existing fixpoint survives the redesign rather than being deleted by it.

---

## Migration caution — coarse to fine

**[MODEL]** The model above is the destination. The migration must not be.

Two designs died on 2026-08-03 and 2026-08-06 for being larger than the problem — a
world token (unsound *and* closing 1 of 4 bugs) and an F3 `Call` reshape (0 of 40 files
unblocked, proposing to build `define` emission that already existed). The pattern is
reaching for a structural property at a *site* when what is missing is a *pass*, and
then over-building the pass.

Specific cautions:

- **Unify the contract, not the classes.** Keep `PadAccess`/`StashAccess`/`FieldAccess`
  as distinct node types — they honestly document which context — but give them the
  contract `Subscript` already has: a memory input, and a repr **inherited** rather than
  stamped. That extends existing machinery to four more ops instead of introducing a new
  IR shape, and it is testable one op at a time.
- **One memory chain first.** Click shipped a single global `STORE` and named slicing as
  future work. Model contexts properly in the *design* so refinement stays expressible;
  start with one chain and split into distinct location identities when a measurement
  demands it.
- **Clone, do not wire.** `TypeLibrary` must be cloned into B::SoN as `SoN::TypeLibrary`,
  not imported. **[MEASURED]** B::SoN currently loads **0** `Chalk::` modules — the
  invariant the `son-ir-divorce` milestone established, because loading them made ~90
  chalk `lib/` files uncompilable by B::SoN (*"Cannot reopen existing class"*). A type
  library would be a particularly bad first re-import, since a self-hosting compiler must
  eventually compile its own.
- **The clone is a re-keying, not a copy.** `TypeLibrary` keys on grammar operator
  strings (`'+'`, `'.'`, `'x'`); the producer walks an optree where those do not exist.
  The optree has already made distinctions the grammar has not: `eq` and `==` are
  different ops; `use integer` yields `i_add` with a **different signature**
  `(Int,Int)→Int`; TARGMY variants fold assignment in. A wired-in grammar library would
  have silently mapped `i_add` onto `+`'s `(Num,Num)→Num` and lost integer semantics.
  There are **three** vocabularies — grammar strings, optree op names, SoN node ops — and
  the producer's library should be keyed on the side it reads from.

---

## Resolved (was: open questions)

- **Does the clone need `join`?** **Yes.** **[MEASURED 2026-08-09]** `set_backedge` is
  called at **6** sites in `FromOptree.pm` (`:2485`, `:2742`, `:2887`, `:2891`, `:3002`,
  `:3006`) — a loop `Phi` is built *before* its backedge input exists, so it cannot be
  typed at construction. (This note previously said 3; that came from a truncated listing.
  The correction strengthens the point rather than weakening it.) Operators can be typed
  at wire-up; Phis force a deferred, bounded step regardless. Bounded because the chain is
  short and join is monotone.
- **What decides a fetch's repr when the store is unreachable?** §5's borrowing rules
  decide *whether it is knowable at all*: (1) stores visible by construction → inherit;
  (2) not visible but **specified** → the library (§7); (3) neither → `Unknown` → the
  checker errors, unless `Any`. "Was a reference taken" is a local syntactic question
  (`\$x` in scope), not a whole-program escape analysis.
- **Where does the check run?** The blocker **dissolves**. It was "wiring `TypedInvariant`
  in before reconciliation makes the compiler fail on a disagreement neither side owns" —
  but the disagreement is `%OP_REQUIRED_REPR` vs `%_COMPUTED_REPR`, and *both are deleted*
  when the library becomes the single authority. Reconciliation is a side effect of §1
  and §3, not separate work.
- **The `Scalar` collision** — **dissolved by §2, not resolved by §6.** There is no
  "representation vocabulary" for a type name to collide with: 99.6% of everything ever
  assigned to that field is a Chalk type name **[MEASURED]**. `Scalar` is simply a type
  with **no image under the LLVM map** (§8) — a per-target absence, not a malformed value.
  `Unknown` remains what the *absent* case should have been.
- **Is `None` top or bottom?** **Bottom** (perigrin, 2026-08-09). `TypeLibrary` was right;
  the canonical lattice document was wrong and has been corrected. No code change. See §6.

**[OPEN]** — none outstanding. Raku was considered as prior art for gradual typing in the
Perl family and **dropped deliberately** (perigrin, 2026-08-09) as a distraction at this
stage.
