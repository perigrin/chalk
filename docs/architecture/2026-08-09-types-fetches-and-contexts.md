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
one place whose job that is:

- 31 `_require_repr` call sites **[MEASURED]**
- 15 `repr=Scalar` refusals in `Target/LLVM/Context.pm` **[MEASURED]** — guarding a
  value that **nothing anywhere assigns** (0 hits for `set_representation('Scalar')` or
  `representation => 'Scalar'` in either repo) **[MEASURED]**
- 1 signature guard added 2026-08-09 (`_repr_to_llvm_type`, commit `1617a6a3`)

That is a cordon around a missing subsystem, not a type system.

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

The pattern is treating a **correct refusal as a cost to engineer around**. Every guard
in the cordon is that instinct made permanent. A reader extending this design should
expect the same pull, and should read a new refusal as evidence of a missing capability
rather than as an obstacle to the change in hand.

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

The B::SoN path has never used it, and instead grew ~822 lines of ad-hoc stamping in
`IR/Serialize/JSON.pm` **[MEASURED: 822 lines, 15 subs]** whose rules can state things
Perl does not permit (§1).

---

## 1. Operators are strongly typed on input and output

**[MODEL]** Perl's dynamism is in its *values*, not its *operators*. Each operator has a
fixed signature; it coerces its operands to fit. `+` is `(Num, Num) → Num`. `.` is
`(Str, Str) → Str`. **`Add` is never a `Str`.**

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

---

## 2. Representation is a separate question from type

**[CODE]** The `representation` field already says this:

> *"representation is a **per-use lowering decision**, not a structural property of what
> value the node IS … `Coerce` nodes bridge between representations on edges."*
> — `IR/Node.pm:50-55`

**[MODEL]** So membership and storage are orthogonal. `"3"` is a member of `Num` (no
type change needed) *and* may be stored as `{ptr,len}` while `+` needs `i64` (conversion
needed). **Coercion is a representation-level operation.**

**[MEASURED] The tables conflate the two vocabularies**, which is why they contradict:

| table | presents as | actually asks |
|---|---|---|
| `%OP_REQUIRED_REPR` — `Add => 'Int'` | a repr constraint | a **type** constraint |
| `%_COMPUTED_REPR` — `Add => 'join'` | a repr rule | joins **reprs** to answer a **type** question |
| `%_REPR_RANK` — `Int<Num<Str` | a repr ordering | the **type** lattice in repr clothing |

### Representation policy: most recent usage

**[MODEL, perigrin]** Of the candidate policies — narrowest type's representation, most
recent usage's, per-use with conversion at every boundary, or both faces retained
(Perl's own SV, and the DualVar foundation) — **most recent usage is the natural fit for
an SSA IR.**

The reason is specific to SSA: a value is defined once and never mutated, so it can
carry exactly **one** representation, with explicit `Coerce` on the edges that need
another. There are no faces to keep in sync and nothing to invalidate. A mutable-slot
model would need DualVar-shaped storage; SSA does not.

**This also retires "write-once stamping" as an obstacle.** Write-once is *correct*
under SSA — you never re-stamp a definition, you insert a `Coerce`. The current engine's
failure is not that it cannot re-stamp; it is that it has no `Coerce`-insertion, so its
only options are "be right first time" or "decline."

---

## 3. Insert `Coerce` at build time, not in a pass

**[MODEL, perigrin]** Do not write a separate `Coerce`-insertion pass. Insert the node
**when the IR node is constructed and its params are wired**. At that moment the
operator is known (hence its signature) and the operands are known (hence their reprs).

**[CODE] This is already proven — once, hardcoded.** Coercion Slice A, at
`SoN/FromOptree.pm:2275-2281`:

> *"must be coerced to Num before the Divide. Wrap each Int-stamped operand in a
> `Coerce(Int->Num)` at **BUILD** time (no post-hoc graph rewire)"*

guarded by `if ($node_type eq 'Divide')`. Generalising it means replacing that
conditional with a signature lookup. `Divide`'s `(Num,Num)→Num` stops being a special
case and becomes one row in a table.

### What this collapses

- **operator result reprs are known at construction** — from the signature. No
  propagation, no fixpoint, no join. `Add => 'join'` is not fixed, it is *deleted*.
- **operands are coerced to fit, never joined.** The partial-join bail
  (`JSON.pm:1105`) leaves the operator path entirely.
- **`join` is needed only at `Phi`.**

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

So the 15 backend `repr=Scalar` guards **[MEASURED]** are right to refuse, but they are
catching a **type name that leaked into the representation field** — §2's conflation.
`Scalar` is a type; `representation` must never hold it.

**[CODE]** Note `Scalar` is *inhabited*, not merely abstract — the practical doc at :235
says so, `DualVar` being the example. So `DualVar` support and the boxed representation
are the same unlock.

**[CODE]** `None` ("never returns") is already in the lattice and unused. It is the type
of `die`/`exit` — the type-level counterpart to `Unwind`.

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

### Parameterised types are a precondition for the checker

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

**Sequencing constraint:** parameterisation must land *before* the checker is turned on.
Otherwise the checker's first act is to reject `pop`/`shift`/`keys`/`values` across the
corpus, and the pressure will be to weaken the checker rather than fix the library —
which is how the present situation arose.

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

## What remains genuinely inference

After §3 (operators become a table lookup) and §4 (fetches inherit through memory edges),
the residue is small:

- **`Phi`** — a real merge; the only place `join` is needed
- **`Call` return types** — interprocedural, including the recursion cycle that blocks
  `fib` **[MEASURED: `fib` dies at `Context.pm:687`, "Add node has no representation"]**

Both are real problems. Neither is the sprawling type system this looked like before the
operator and fetch cases were separated out.

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

- **Does the clone need `join`?** **Yes.** **[MEASURED]** `set_backedge` is called at 3
  producer sites — a loop `Phi` is built *before* its backedge input exists, so it cannot
  be typed at construction. Operators can be typed at wire-up; Phis force a deferred,
  bounded step regardless. Bounded because the chain is short and join is monotone.
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
- **The `Scalar` collision** — resolved by §6. `Scalar` is a type; the representation
  field must not hold type names; `Unknown` is what the absent case should have been.

**[OPEN]** — none outstanding. Raku was considered as prior art for gradual typing in the
Perl family and **dropped deliberately** (perigrin, 2026-08-09) as a distraction at this
stage.
