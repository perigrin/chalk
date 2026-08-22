# Prior art: parameters, argument aggregates, node identity, value-ness

**Date:** 2026-08-22
**Method:** deep-research workflow, 109 agents, 26 primary sources fetched,
125 claims extracted, top 25 adversarially verified (3 independent verifiers
each, majority-refute kills). WebSearch budget exhausted at 200/200.
**Instruction given:** report COULD NOT CONFIRM rather than reconstruct.

**Corrects:** `2026-08-22-identity-kind-and-argssource-shape.md`, which stated
several of these as fact from my memory. Five are now UNVERIFIED and one is
narrowed. See "Corrections" at the end.

**CITATION HAZARD:** every V8/OpenJDK citation was fetched from a moving branch
tip (`main`/`master`) on 2026-08-22, not a pinned SHA. Quotes will drift.

---

## VERIFIED (high confidence, 3-0 votes, verbatim source)

### 1. Parameters are individual positional defs with individual types

**Turboshaft** (`operations.h:4438`):

    struct ParameterOp : FixedArityOperationT<0, ParameterOp> {
      int32_t parameter_index;
      RegisterRepresentation rep;
      static constexpr OpEffects effects = OpEffects();
      base::Vector<const RegisterRepresentation> outputs_rep() const { return {&rep, 1}; }
      // "On the callee side a parameter doesn't have an input."

Zero-arity, pure, one output whose representation is per-parameter.
`outputs_rep` cardinality 1 means **no instance can stand for a list**.

**C2** (`callnode.hpp`, `multnode.hpp`, `parse1.cpp`): `ParmNode : public
ProjNode`, projected off `StartNode` by positional index `uint con` ("the field
in the tuple we are projecting"). `ParmNode` stores NO type of its own --
`ProjNode::bottom_type()` does `t->is_tuple()->field_at(_con)` against
`StartNode`'s `TypeTuple _domain`. **CLAIM B confirmed, including TypeFunc's
role.**

Two precision corrections to carry:
- NOT literally 1:1 -- longs/doubles occupy two tuple slots
  (`field_array[pos++] = TypeLong::LONG; field_array[pos++] = Type::HALF;`),
  and the build loop keeps two diverging counters.
- Domain slots 0-4 are Control/I_O/Memory/FramePtr/ReturnAdr; user parameters
  start at `TypeFunc::Parms`.

### 2. THE LOAD-BEARING ONE: length is decoupled from materialization

Turboshaft has two separate operations:

    ArgumentsLengthOp    : FixedArityOperationT<0, ...>   effects = OpEffects()   // PURE
    NewArgumentsElementsOp : FixedArityOperationT<1, ...> effects = OpEffects()
                                 .CanAllocate()          // "the fixed array, which has identity"
                                 .CanDependOnChecks()    // "do not move above checks/branches"

`ArgumentsLengthOp` is **zero-input and does not take the aggregate as an
operand**, so asking for the length *structurally cannot* force materialization.
That is real decoupling, not a peephole. Only `NewArgumentsElementsOp`
allocates, and V8's own inline comments give the reason: the array has
observable identity.

### 3. Rest/variadic is a KIND TAG, not a node type

    struct ArgumentsLengthOp : ... {
      enum class Kind : uint8_t { kArguments, kRest, };
      Kind kind;
      int formal_parameter_count = 0;  // unused for kArguments
      DCHECK_IMPLIES(kind == Kind::kArguments, formal_parameter_count == 0);

No `RestLengthOp` exists. Verified exhaustively, not by grep artifact: over the
full 10,768-line file, `grep -n "Rest"` yields exactly ONE hit (line 6480).
Both discriminators are in `options()`, so both participate in structural
equality and hashing.

### 4. Value-numberability is decided STRUCTURALLY, never by a per-node flag

Turboshaft, two-part test:

    bool EffectsAllowGVN(OpEffects effects) {
      return effects.IsSubsetOf(OpEffects().CanDependOnChecks()
             .CanChangeControlFlow().CanAllocateWithoutIdentity().CanReadMemory());
    }

A genuine lattice containment test (`(bits() & ~other.bits()) == 0`). The
permitted set includes `CanReadMemory` but has **no write counterpart**, so any
writing op fails by construction. Plus a compile-time opcode filter
(`CanBeGVNed<Op>()`) excluding block terminators.

**A deliberate search for a per-operation `value_numberable` boolean found none.**

HEDGE (a 1-2 refutation corrected an over-strong reading): the filter has
hardcoded per-opcode exceptions in BOTH directions -- `DeoptimizeIfOp` admitted
despite effects, `LoadOp` at map offset rejected despite passing. So it is
"GVN-able iff effects ⊆ {...}, modulo named exceptions".

### 5. Turboshaft still GVNs after leaving sea-of-nodes -- via dominator scoping

From `value-numbering-reducer.h`'s own header comment: a node "should only be
replaced by a node defined in blocks that dominate the current block ... when
going down the dominator tree, we add nodes to the hashmap, and when going back
up the dominator tree, we remove nodes". Implemented as a per-block linked list
of hashmap entries (`depth_neighboring_entry`) cleared on the way up. The
dominator-order precondition was verified in the traversal, not assumed.

### 6. PRIORITY 3 ANSWER -- the decision is SPLIT

**The KIND of aggregate is a frontend flag.** V8's `CreateArgumentsType`
(mapped / unmapped / rest) is chosen in `Scope::GetArgumentsType()` from purely
syntactic information: strictness plus whether the parameter list is simple.

**WHETHER the backing store is materialized is decided by ANALYSIS.**
`EscapeAnalysisReducer::Finalize()` walks `node->use_edges()` of each
`NewArgumentsElements` computing an `escaping_use` boolean; state-values and
length-loads are benign, anything unhandled sets `escaping_use = true`. Only
when clean does it replace the allocation with a non-materialized
`ArgumentsElementsState`.

**When elided, the aggregate collapses back to POSITIONAL access:** surviving
`LoadElement`s are retargeted to `LoadFramePointer` + computed offset with the
operator changed to `LoadStackArgument` (plus `formal_parameter_count` for
kRest). A `LoadField` on `length_` folds to the `ArgumentsLength` value.

### 7. Aliasing: V8 CONCEDES rather than pessimizing (medium confidence)

Sloppy-mode mapped arguments allocate a `SloppyArgumentsElements` holding a
context pointer plus per-index **Smi indices into context slots** (not
pointers): `int idx = shared.context_parameters_start() +
parameter_count_without_receiver - 1 - i;`.

In the escape reducer, `mapped_count != 0` makes every `kLoadElement` use set
`escaping_use = true`. So where aliasing is live, V8 **gives up on elision for
that object** rather than introducing a general IR-level aliasing relation.

(A stronger claim -- that V8 cannot elide mapped arguments *at all* -- was
REFUTED 0-3. The true statement is the narrower one above.)

---

## COULD NOT CONFIRM -- treat as UNVERIFIED, not confirmed-by-silence

- **CLAIM A** -- LLVM `Argument` values, `void`-typed instructions.
- **CLAIM C** -- Graal `ParameterNode(index)`.
- **CLAIM F** -- Graal `NodeClass.valueNumberable()`; whether the interface is
  even named `ValueNumberable`.
- **CLAIM G** -- Graal's ValueNode/Stamp structural value-ness; C2's
  `Type::CONTROL`.
- **CLAIM H** -- FixedNode vs FloatingNode orthogonality, `FixedWithNextNode`.
- **CLAIM E's C2 half** -- `Node::hash` / `Node::cmp` / `NodeHash`, and the
  memory-edge argument. Only the Turboshaft effects-lattice analogue verified.
- **Whether Turboshaft retains ANY arguments-elision analysis.**

### THE SCOPE HAZARD, stated plainly

Findings 1-5 are **Turboshaft**. Finding 6 is **TurboFan**
(`escape-analysis-reducer.cc`, `js-create-lowering.cc`). Different pipelines.

Do NOT write "Turboshaft decides materialization by escape analysis" -- that is
unverified. Turboshaft's own escape work is explicitly narrower:
`late-escape-analysis-reducer.h` says it "removes allocation that have no uses
besides the stores initializing the object" -- dead-allocation removal, NOT
virtual-object materialization -- and does not mention arguments objects.

Two verifiers explicitly REFUSED to answer Priority 1(b) for Turboshaft from
TurboFan files, on the grounds that `escape-analysis.cc` is TurboFan by
construction (uses `Node*`, `NodeProperties::GetEffectInput`, an
`EffectGraphReducer` DFS; header "Copyright 2017", predating Turboshaft).

### CLAIM D is two-thirds supported

"NONE of LLVM, C2, or Graal has an argument-list node" is confirmed for
Turboshaft and C2, unverified for LLVM and Graal. The report flags an open
counterexample risk: **deopt metadata is where V8 DOES keep an aggregate** --
`ArgumentsElementsState` survives as a deopt literal after the real allocation
is elided. C2's `SafePointNode`/FrameState edges are the untested analogue.
Do not write CLAIM D as a universal.

---

## What this means for Chalk

**`ArgsSource` is the wrong shape, and the fix is now concretely specified.**
The verified model is:

    parameters        -> N positional defs, individually typed, PURE, zero-input
    "how many args"   -> a pure zero-input op that does NOT take the aggregate
    the aggregate     -> a separate ALLOCATING op, only where observed

Today Chalk has one node meaning "the argument list", and `$_[0]` is
`Subscript(ArgsSource, 0)` -- so indexing and length both route through the
aggregate. The verified decoupling says they should not.

**On `uses_args`:** the split answer says a frontend flag is legitimate for
WHICH KIND of aggregate, and analysis owns WHETHER to materialize. Chalk's
`uses_args` is currently doing the second job. That makes it a **stopgap**, not
a permanent design -- but the analysis that would replace it is escape/demand
analysis over use edges, which Chalk does not have. Keep it, and record that it
is standing in for an analysis.

**On aliasing (`$_[0]` aliases the caller's lvalue):** V8's answer is to detect
the aliasing case and DECLINE to elide, rather than model aliasing in the IR.
That is a cheaper answer than Chalk has been assuming.

**On `identity_kind`:** finding 4 supports deriving it. Turboshaft has NO
per-node value-numberable boolean; it computes the answer from an effects
lattice plus a class-level opcode filter. Chalk's `is_fixed` is the analogous
property. But note the HEDGE -- V8 needs named per-opcode exceptions in both
directions, so a pure derivation may not be achievable; expect an exception
list, and keep it explicit rather than letting it become 62 hand-declarations
again.

---

## Corrections to my own earlier docs

`2026-08-22-identity-kind-and-argssource-shape.md` stated as fact:

- "Graal: `NodeClass.valueNumberable()`, derived from the class" -- **UNVERIFIED**
- "Graal: `ParameterNode(index)`" -- **UNVERIFIED**
- "LLVM: arguments are `Argument` values ... each independently typed" -- **UNVERIFIED**
- "C2: what stops a store being CSE'd is the MEMORY EDGE" -- **UNVERIFIED**
  (the analogous mechanism is verified in Turboshaft, as an effects lattice)
- "NONE of them has a node meaning 'the argument list'" -- **two-thirds
  supported**; LLVM and Graal unchecked, and deopt metadata is a live
  counterexample risk

`2026-08-21-value-node-split-handoff.md` states Graal's ValueNode/Stamp split
as the model for `Chalk::IR::Value`. That claim is **UNVERIFIED**. The split
still stands on its own merits -- the three-meanings-of-undef problem is
measured in Chalk's own code, independent of what Graal does -- but the prior-art
justification should not be cited as established.

## Methodology notes worth keeping

- One WebFetch produced a **documented false negative**: a summary wrongly
  asserted no dominator-order traversal because the summarizer judged from
  method names without resolving `Block`'s base class. Caught by raw `curl`.
- WebFetch **truncates** `turboshaft/operations.h` (10,768 lines); raw download
  is required past ~line 4000.
- Every finding rests on direct primary-source reads with **zero secondary
  corroboration** -- the search budget was exhausted, so no verifier could
  sample the literature for dissent.
