# `identity_kind` is derivable, and `ArgsSource` is the wrong shape

**Date:** 2026-08-22
**Status:** MEASURED, nothing changed. Two findings raised by perigrin while
reviewing the `Chalk::IR::Value` split.
**Related:** `2026-08-21-value-node-split-handoff.md`,
`2026-08-21-type-vs-representation-seams.md`

---

## 1. `identity_kind` records who got round to marking a class, not a fact

**What it is:** may two structurally identical occurrences of this op be the
SAME node? `hash_consed` = yes (`1 + 2` twice is one node). `per_call` = no,
each occurrence is a distinct event.

**MEASURED across all 82 non-abstract node classes:**

    per_call    (20): ALL INHERIT the default. Zero declare it.
    hash_consed (62): ALL DECLARE it themselves. Zero inherit.

No exceptions in either direction. So the flag is not recording a per-class
property -- it is recording *"has anyone gotten round to marking this one
consable?"* The base default is `per_call` (deliberately conservative:
Node.pm:148, "losing an optimisation beats losing a statement"), and 62 classes
opt out by hand.

Corollary: **the NodeFactory comment at :169-176 is stale.** It says
`ArrayRef`/`HashRef` "now declare `sub identity_kind { 'per_call' }`
themselves". They do not; they inherit it. The same comment is cited as the
reason `%ALLOC_OPS` was deleted.

**The 20 `per_call` ops are almost exactly the fixed + allocating ones:**

    effects:     Assign CompoundAssign Call Print RegexSubst RegexMatch
                 Match NotMatch BacktickExpr TryCatch
    control:     If Loop Region Proj Phi VarDecl ListAssign
    allocation:  ArrayRef HashRef AnonSub

### How the others do it -- both DERIVE the answer

> **VERIFICATION STATUS (2026-08-22).** The Graal and C2 mechanism claims below
> were written from memory and are **UNVERIFIED**. A research pass
> (`docs/research/2026-08-22-parameters-identity-valueness-prior-art.md`) could
> NOT confirm Graal's `NodeClass.valueNumberable()`, the `ValueNumberable`
> interface name, or C2's `Node::hash`/`NodeHash`/memory-edge argument.
>
> What IS verified, verbatim from V8 source: **Turboshaft has NO per-operation
> value-numberable boolean.** It computes the answer from an effects-lattice
> subset test plus a class-level opcode filter -- WITH named per-opcode
> exceptions in both directions. That supports deriving, and warns that a pure
> derivation may need an explicit exception list rather than being total.

- **C2:** hash-consing runs through a global value-number table (`NodeHash`).
  What stops a store being CSE'd is not a flag -- stores carry a MEMORY EDGE, so
  two stores have different memory inputs and cannot be structurally equal.
  Identity falls out of graph shape.
- **Graal:** `NodeClass.valueNumberable()`, derived from the class.
  `FloatingNode`s implementing `ValueNumberable` get GVN'd; `FixedNode`s
  generally do not, being anchored in the control chain.

Both derive it from the SAME property: **fixed/effectful things are not
value-numbered, because their control or memory inputs already distinguish
them.** Chalk has `is_fixed`. `is_fixed || allocates` would derive ~all 82
answers.

### perigrin's three questions

1. **Rename to `can_cons`?** Better -- it names the decision rather than a
   category. But if derived, the predicate collapses into `is_fixed || allocates`
   and there is nothing left to name.
2. **Move it to `Value`?** It CANNOT move: `If`, `Loop`, `Proj`, `Print`,
   `VarDecl` are control nodes that need the answer. That is itself evidence it
   is about OCCURRENCE IDENTITY, not about values -- a `Node`-level question.
3. **Why not derive it?** No visible reason. The documented exception
   (`Start`/`Return`/`Unwind` differing between `make()` and `make_cfg()`,
   Node.pm:155-162) is about the CONSTRUCTOR, not the type, and survives either
   way.

### Before replacing it -- a measurement, not a refactor

62 hand-declarations are 62 chances one disagrees with the derivation. Compute
`is_fixed || allocates` for every class, diff against the declared value, and
INVESTIGATE each mismatch rather than assuming it is stale. A single genuine
disagreement means the axes are not redundant after all. Cheap to run and it
must precede any deletion.

---

## 2. `ArgsSource` models perl's implementation of arguments, not perl's semantics

`Chalk::IR::Node::ArgsSource` is a nullary hash-consed node meaning "the current
sub's `@_`". `$_[0]` is then `Subscript(ArgsSource, 0)`.

It was a genuine improvement over what preceded it -- `@_` rode on
`StashAccess(main,'_')`, and with identity keyed on name alone `$_` and `@_`
hash-consed into ONE node feeding both a `shift @_` and a RegexMatch subject.
Splitting it closed a real defect.

**But the shape is still wrong.** perigrin: *given how Perl traditionally did
its semantics it's not entirely wrong but definitely not optimal ... it also
doesn't seem like it should be shaped like this even if we were trying for the
same IR semantics.*

### How the others do it -- parameters are DEFS, not a container

> **VERIFICATION STATUS (2026-08-22).** VERIFIED for Turboshaft and C2 from
> verbatim source; **UNVERIFIED for LLVM and Graal**. Turboshaft's `ParameterOp`
> is zero-input, pure, positionally indexed, with ONE output -- so no instance
> can stand for a list. C2's `ParmNode` is a `ProjNode` off `StartNode`, typed
> by `TypeTuple` field rather than carrying a type itself. The universal "NONE
> of them" is only two-thirds supported, and deopt metadata is a live
> counterexample risk: V8 keeps `ArgumentsElementsState` as a deopt literal
> after eliding the real allocation.
>
> **The load-bearing verified finding: LENGTH IS DECOUPLED FROM
> MATERIALIZATION.** `ArgumentsLengthOp` is zero-input, pure, and does NOT take
> the aggregate as an operand -- so asking for the length structurally cannot
> force allocation. Only `NewArgumentsElementsOp` allocates, marked
> `.CanAllocate().CanDependOnChecks()` because the array has observable
> identity.

- **LLVM:** arguments are `Argument` values in the function signature (`%0`,
  `%1`), each independently typed.
- **C2:** `ParmNode`s projected off `StartNode`, one per parameter, each with
  its own type.
- **Graal:** `ParameterNode(index)`.

**None of them has a node meaning "the argument list."** Parameters are
individual definitions, positionally indexed, typed independently.

### Why that matters here

`ArgsSource` models `@_` as an opaque AGGREGATE you index into, which:

- forces `Subscript(ArgsSource, N)` where a positional def would do;
- defeats typing each parameter separately -- one node, one type, for N
  unrelated values;
- is the same layering leak as `PadAccess` (seams doc finding 3): modelling
  perl's storage rather than the language's meaning.

Perl's actual semantics are that **parameters ALIAS the caller's arguments** --
an aliasing relationship between N caller values and N callee names. That is not
a container; the container is how perl implements it.

### It also subsumes `uses_args` -- but the real answer is SPLIT

> **VERIFIED (2026-08-22):** the decision is split two ways. The KIND of
> aggregate is a frontend flag (V8's `CreateArgumentsType`, chosen in
> `Scope::GetArgumentsType()` from strictness + simple-parameter-list alone).
> WHETHER to materialize is decided by ANALYSIS over use edges
> (`EscapeAnalysisReducer::Finalize` computes an `escaping_use` boolean).
>
> Chalk's `uses_args` is doing the SECOND job, which makes it a **stopgap** --
> but the analysis that would replace it is escape/demand analysis Chalk does
> not have. Keep it, and record that it stands in for an analysis.
>
> **SCOPE HAZARD:** the escape-analysis half is **TurboFan**, not Turboshaft.
> Whether Turboshaft retains any arguments-elision mechanism is COULD NOT
> CONFIRM.

`uses_args` exists because materialising a real `@_` array is expensive and
usually unnecessary (the NoSnails direction in perl core). Under the ParmNode
model that falls out: parameters are defs, and an actual aggregate is
materialised ONLY when something genuinely wants the array -- `goto &f`,
`shift @_` in a loop, aliasing. No producer-side flag required.

### Not proposed here

The producer already emits `param_names` on direct calls. Whether that is
already the positional model (making `ArgsSource` only a fallback) is UNCHECKED,
and it decides how big this is. Check before designing.

---

## Status

Nothing in this document is fixed. The `Chalk::IR::Value` split is separate and
lands independently; these are two shape questions it surfaced.

---

## MEASURED 2026-08-22: Chalk has NO parameter representation, it has TWO ACCIDENTS

perigrin asked whether Chalk projects parameters off `Start` like TurboFan/C2.
It does not -- and the measurement is worse than the question assumed.

Two subs, two completely different encodings of "a parameter", neither of which
names the concept:

    sub f { my ($a,$b) = @_; $a + $b }
      Start       inputs=[]
      PadAccess   inputs=[] targ=1 varname=$a     <- untyped
      PadAccess   inputs=[] targ=2 varname=$b     <- untyped
      Add         inputs=[PadAccess,PadAccess]
      Assign      inputs=[PadAccess,PadAccess]    <- disconnected

    sub g { $_[0] * 2 }
      Start       inputs=[]
      ArgsSource  inputs=[]
      Subscript   inputs=[ArgsSource,Constant(0),MemStart]   <- untyped, MEMORY input
      Multiply    inputs=[Subscript,Constant(2)]

### Three defects visible in one measurement

1. **`my ($a,$b) = @_` produces NO parameter nodes.** It produces `PadAccess`
   -- the same perl-implementation leak as the cross-sub lexical case (seams
   doc finding 3). `@_` has vanished from the graph entirely. This is the MOST
   COMMON parameter idiom in Perl, and it does not go through `ArgsSource` at
   all.

2. **`$_[0]` is a MEMORY READ.** The `Subscript` takes `MemStart` as an input,
   so reading a parameter is ordered against memory operations. Both V8
   pipelines make a parameter PURE -- TurboFan `Operator::kPure`, Turboshaft
   `OpEffects()`. A pure parameter can float, CSE, and hoist; Chalk's cannot,
   for no semantic reason.

3. **Both encodings are untyped.** These are the `~35 corpus gaps` at their
   source.

### Nothing hangs off `Start`

    TurboFan   Parameter    value_in=1 -> Start        Operator::kPure
    C2         ParmNode     ProjNode off StartNode     typed via TypeTuple
    Turboshaft ParameterOp  arity 0 (no input)         OpEffects() (pure)
    Chalk      -- nothing --

Chalk's `Start` is a bare control token with no value projections. Two of the
three verified systems project parameters off Start; the third makes them
zero-input. Chalk does neither because it has no parameter node to place.

### This RESCOPES the ArgsSource finding

The `ArgsSource` critique above is correct but addresses the RARER path.
Fixing `ArgsSource` alone leaves `my ($a,$b) = @_` -- the common case -- still
emitting `PadAccess`. The real finding is:

**Chalk has no parameter representation. It has two accidental encodings that
share nothing: a pad slot and a memory-read subscript.**

A positional `Parameter` node would unify them: `my ($a,$b) = @_` binds
parameters 0 and 1; `$_[0]` reads parameter 0. Same nodes, one concept, pure,
individually typed -- and `uses_args` becomes "did anything need the aggregate",
which is the analysis question rather than a producer flag.

### Verified TurboFan detail worth copying

`common-operator.cc`, verbatim:

    IrOpcode::kParameter, Operator::kPure,     // opcode
    "Parameter",                               // name
    1, 0, 0, 1, 0, 0,                          // counts
    ParameterInfo(index, debug_name));         // parameter info

`hash_value(ParameterInfo p) { return p.index(); }` -- parameters hash-cons by
index, so two reads of parameter 0 are ONE node. Correct: a parameter is a
single incoming value, not an event.

`kMinIndex = Linkage::kJSCallClosureParamIndex` -- indices may be NEGATIVE,
reserving slots below zero for closure/context/receiver. That is the answer to
the invocant question: `$self` is a parameter at a reserved index, not a
special case.

NOTE the TurboFan/Turboshaft divergence: TurboFan's Parameter has
`value_in = 1` (projects off Start); Turboshaft's is arity 0 with the explicit
comment "On the callee side a parameter doesn't have an input." Do not
generalize one to the other.
