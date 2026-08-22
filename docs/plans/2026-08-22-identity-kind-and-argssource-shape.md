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

### It also subsumes `uses_args`

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
