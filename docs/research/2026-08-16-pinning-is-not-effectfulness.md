# "Must be pinned to the control chain" is not "is effectful"

**Date:** 2026-08-16
**Status:** FINDING. Not a plan. Nothing here is scheduled; it records a
measured defect and what production systems do instead.
**Supersedes:** the step-4d ruling in
`docs/plans/2026-08-13-node-type-and-typelibrary-as-authority.md`, which said
`%CONTROL_CHAIN_OP` "stays a table". That ruling was reached by citing the
table's own comment as evidence for the design the comment describes.
**Predecessors:** `docs/research/2026-08-02-effect-ordering-prior-art.md`
(the four-mechanism taxonomy), `docs/research/2026-08-13-branch-merge-prior-art.md`
(whose closing line names this exact gap as "unverified and load-bearing").

## How this was reached, because the method is the point

The step-4d ruling said `%CONTROL_CHAIN_OP` is "a producer build-site policy,
not a node property". Two defects in that reasoning, both raised by perigrin:

1. **It cited comments as evidence.** The argument for the table was
   `TypedInvariant.pm:78-119`'s own comment, which describes the design it is
   part of. A comment is a claim, not a measurement, and may be stale or
   derived from a misunderstood premise.
2. **"Producer policy" is not an explanation.** It says WHERE the decision
   lives. It does not say whether the decision is CORRECT. Naming the owner of
   a rule is not the same as justifying the rule.

So the question was put to the prior art instead: how do other Sea-of-Nodes
implementations decide this?

## What Chalk has today

`TypedInvariant.pm:118` — the ops required to carry a defined `control_in`:

    my @CONTROL_CHAIN_OPS = qw(Print Assign Return Call Unwind);

`Chalk::IR::Node::is_fixed` — the ops that report an effect — names eleven.
Measured, the two sets are neither equal nor nested:

| | |
|---|---|
| `is_fixed` but NOT control-pinned (7) | BacktickExpr CompoundAssign Match NotMatch RegexMatch RegexSubst TryCatch |
| control-pinned but NOT `is_fixed` (1) | Return |

The stated rationale for the seven is that the match family is "value-ordered
through its RegexCapture/Assign data edges" — its position fixed by dataflow
rather than by a control pin.

## What production Sea-of-Nodes compilers actually do

Researched against primary sources (OpenJDK master, V8 main, Graal master, and
Click & Paleczny 1995). The headline: **in none of the three is "must be
pinned" the same predicate as "is effectful."**

### HotSpot C2 — four orthogonal mechanisms

`StoreNode` overrides NEITHER `pinned()` NOR `is_CFG()`. A C2 store is
effectful, unpinned, and constrained by a THIRD mechanism —
`is_memory_writer()` (`node.hpp:1451`) plus its memory edge. The scheduling
predicate at `gcm.cpp:376` is `pinned()` alone.

| mechanism | predicate | driven by |
|---|---|---|
| block placement | `pinned()` | CFG structure, safepoints |
| re-parent to dominating test | `depends_only_on_test()` | trapping |
| memory ordering | memory edges + `is_memory_writer()` | side effects |
| GVN exclusion | `hash() == NO_HASH` | CFG-ness |

The discriminator for a control pin is TRAPPING, not effects. `divnode.cpp:643`:
"The third input is a Control input, used to prevent hoisting the divide above
an unsafe test" — and `divnode.cpp:624` DISCHARGES that pin when the type
proves the divisor cannot be zero:

    if (in(0) && (ti->_hi < 0 || ti->_lo > 0)) { set_req(0, nullptr); }

A side-effect pin could never be removed by a range proof. A trap pin can.
That single line is the cleanest available evidence that the two are different
properties.

Also worth recording: the 1995 paper contains ZERO occurrences of "pinned" or
"side effect", and says control edges are optional — "This edge is not always
required. Removing it enables a number of global optimizations."

### GraalVM — three axes, and both "impossible" diagonals are populated

`FixedNode` is not "has a side effect". `StateSplit.hasSideEffect()` is a
separate interface whose javadoc defines it as RE-EXECUTABILITY, not ordering.

- fixed but pure: `IntegerDivRemNode extends FixedBinaryNode` — fixed, can
  deoptimize, does not implement `StateSplit`.
- floating but effectful: `MemoryPhiNode extends PhiNode (-> FloatingNode)
  implements SingleMemoryKill`; likewise `MemoryMapNode`.

Read/write is enforced STRUCTURALLY rather than by a list:
`ReadNode extends FloatableAccessNode` vs
`AbstractWriteNode extends FixedAccessNode`. The write class has no
`asFloatingNode()` to call.

### V8 TurboFan — the chain is TOTAL

`kNoWrite`/`kNoRead` are independent property bits, but `EffectInputCount` is a
separate constructor argument and `simplified-operator.cc:2608` hardcodes 1 for
effect in/out REGARDLESS of the property. So `LoadField` is `kNoWrite` AND on
the chain. From the V8 team's own retrospective: "every memory operation needs
both an effect input... and a control input"; "only pure nodes actually float
freely."

COULD NOT CONFIRM any TurboFan notion of "effectful but ordered by data edges".
The one nearby case runs the OPPOSITE way — `CheckedTaggedToTaggedPointer` is
arguably pure yet forced ONTO the chain because it guards followers.

### The answer to the design question

"Must be pinned" is derived from a different property than "is effectful". The
discriminators actually in production are:

1. **can it trap or deoptimize?** (C2 `depends_only_on_test`, Graal
   `DeoptimizingNode`, LLVM `isSafeToSpeculativelyExecute`)
2. **does the ordering have a carrier other than control?** a memory or anchor
   data edge will do
3. **is it a read or a write?** — and in Graal this is a class hierarchy, not a
   predicate

**No production system uses a hand-maintained op-name list.** Each makes it a
type property with nowhere to put the wrong answer.

## The technique Chalk claims IS real — and Chalk is not doing it

Graal's `FloatingReadPhase` genuinely floats effectful nodes on data edges, so
the idea is sound. It is guarded by three preconditions, and the guards are the
finding:

    // FloatingReadPhase.processAccess
    if (!locationIdentity.equals(LocationIdentity.any()) && locationIdentity.isMutable()) {
        MemoryKill lastLocationAccess = state.getLastLocationAccess(locationIdentity);
        access.setLastLocationAccess(lastLocationAccess);   // THE EDGE IS INSTALLED
    }

1. only READS float — writes are structurally barred, and
   `ReadNode.asFloatingNode()` hard-errors on a volatile access
2. the ordering edge is INSTALLED BY A PHASE from a location-keyed memory
   state; it is not assumed to already exist
3. the location identity must be SINGLE, never `ANY_LOCATION`

### Chalk's seven exemptions fail all three

Verified by reading the classes, not the comments about them.

`Match :isa BinOp`, so its inputs are `[subject, pattern]`
(`lib/Chalk/IR/Node/Match.pm`). `RegexCapture`'s own ABOUTME says "inputs[0] is
the RegexMatch/Match node" — an edge from a capture BACK to its own match.

**There is no edge from one Match to another.** Concretely:

    $a =~ /(\d+)/;    # Match#1 — inputs [$a, pattern1]
    $b =~ /(\w+)/;    # Match#2 — inputs [$b, pattern2]
    print $1;         # RegexCapture(n=1) -> Match#2

`Match#1` has no consumer and no edge to `Match#2`. Both write `$1`. Nothing in
the graph orders them relative to each other. That is precisely Graal's
`ANY_LOCATION` case, which `canFloat()` REFUSES: capture state is a single
global location that every match kills.

The other exemptions are worse, and each is convicted by its own comment:

| op | its own comment | verdict |
|---|---|---|
| `RegexSubst` | "s/// mutates its subject" | a STORE; Graal bars stores from floating |
| `CompoundAssign` | "a read-modify-write store" | a STORE |
| `BacktickExpr` | "qx// runs a command: a host-process effect" | no data-edge ordering story at all |
| `TryCatch` | "carries a handler; the guarded body may do anything" | no ordering story at all |
| `Match`/`RegexMatch`/`NotMatch` | "sets the capture state a later $N read depends on" | describes a WRITE to shared state |

**Of the seven, ZERO have a data-edge ordering carrier.** The rationale is the
name of a real technique applied to a case that does not implement it.

## What this means

`%CONTROL_CHAIN_OP` should NOT stay a table, and step 4d's ruling is withdrawn.
But the fix is not "derive it from `is_fixed`" either — that would wrongly
police all seven, and `is_fixed` defaults FALSE, which cannot be the authority
for a soundness question.

The deeper problem is that Chalk now has FOUR near-duplicate spellings of one
set, none of which is the principled discriminator:

| spelling | size | where |
|---|---|---|
| `is_fixed` | 11 | node type (correct SHAPE, wrong default direction for this use) |
| `%CONTROL_CHAIN_OP` | 5 | `TypedInvariant.pm:118` |
| `%STATEMENT_EFFECT_OPS` | 10 | `NodeFactory.pm:155` |
| `is_statement_node` | 11 | `NodeFactory.pm:390` (= `is_fixed` minus Unwind, plus VarDecl) |

They disagree because they are answering DIFFERENT questions with the same
vocabulary, and none of them asks the question production systems ask.

## The direction: adopt Graal's three axes

The four spellings above collapse if the question is SPLIT rather than
re-listed. Graal's decomposition is the simplest of the three surveyed and the
most flexible, and it is the one that fits Chalk's existing shape: each axis is
a type property with a single answer per class, and no axis is derived from
another.

| Graal axis | its question | Chalk today |
|---|---|---|
| `FixedNode` vs `FloatingNode` | may this node be scheduled freely? | `is_fixed` — the right shape, already landed |
| `StateSplit.hasSideEffect()` | is this node re-executable? | **does not exist** |
| `DeoptimizingNode.canDeoptimize()` | can this node trap? | **does not exist** |

Chalk currently answers all three with one predicate plus three op-name lists,
which is why the lists disagree: they are approximations of different axes
sharing one vocabulary. Splitting them is subtraction, not addition — each
existing list becomes a derivation of one axis, or is deleted because it was
conflating two.

**Graal's CLASS HIERARCHY is not part of what to copy.** `FixedNode` vs
`FloatingNode` is a Java expression of the idea, forced by a language where the
natural place to put a per-type constant is a superclass. The idea itself is
three independent yes/no questions per node type, and Chalk can hold them as
three class methods on `Chalk::IR::Node` — exactly the mechanism 4a and 4b just
landed:

    sub schedulable_kind { 'fixed' }      # or 'floating'  — may it move?
    sub is_re_executable { false }        #                — safe to run twice?
    sub can_trap         { false }        #                — may it abort?

A plain `sub` in a `class` block is a class method, inherits through `:isa`, and
is answerable before an instance exists (proved in `beb6989d`). Three subs beat
a hierarchy here: the axes are ORTHOGONAL, so a hierarchy has to name their
combinations — `FixedTrappingPure`, `FixedTrappingEffectful`, ... — where three
independent methods express them by construction.

Graal shows the strain directly. `MemoryPhiNode extends PhiNode
(-> FloatingNode) implements SingleMemoryKill` is floating AND effectful, and
`IntegerDivRemNode extends FixedBinaryNode` is fixed AND pure — both "impossible"
diagonals, each reached by mixing a superclass with an interface because one
hierarchy cannot carry two axes. (The `MemoryPhiNode` half is independently
corroborated by `2026-08-13-branch-merge-prior-art.md:75`, a separate sweep.
Reported but NOT independently re-verified here: `GuardNode extends
FloatingAnchoredNode` as a third such case.)

Chalk has no inheritance constraint forcing that, and `is_fixed` already
demonstrates the simpler form. Keep the decomposition, drop the hierarchy.

Why this beats the alternatives considered:

- It does NOT require the memory-edge machinery C2 uses (`is_memory_writer` +
  alias slices), which is a larger build and presumes a memory-SSA layer Chalk
  has only partly.
- It does NOT require making the effect chain total, as TurboFan does — the
  option V8 itself later moved away from.
- It is expressible with what 4a and 4b just proved works: a class method with
  a conservative default, a completeness test against the class list, and the
  registry kept until agreement is pinned.

Two things it makes possible that the current shape cannot express:

1. `is_fixed`'s default direction stops being a problem. Today it defaults
   FALSE, which is unsafe for a soundness question. Split apart, the SOUNDNESS
   axis (re-executability) gets a conservative default of its own without
   changing what `is_fixed` means for scheduling.
2. The seven exemptions become answerable rather than listed. A `RegexSubst` is
   a write (not re-executable, must be ordered); a `Match` is a write to a
   single global location; a `TryCatch` can trap. Each falls out of an axis
   instead of an enumeration.

**Still required before building, and NOT yet done:** the ordering carrier.
Splitting the axes says correctly that the match family must be ordered; it
does not by itself install the edge that orders them. That is Graal's
`lastLocationAccess`, and Chalk has no equivalent — which is the same missing
primitive step 5 needs (see below). The axes make the requirement statable; the
edge makes it true.

A discriminating test is also required first, and the corpus gate CANNOT
provide it: two matches with both captures read is exactly the shape the gate's
shape leg does not check (`docs/plans/2026-08-03-effect-chain-followups.md`
Part A1 — the shape leg does not check operands of control-reachable nodes).

**Note the adjacency to step 5.** That plan's four failed attempts all
substituted node-kind proxies for an EDGE property, because
`Chalk::IR::Node::add_consumer` keeps one undifferentiated consumer list. Both
findings are the same missing primitive seen from two sides: Chalk cannot say
what KIND an edge is, so it encodes edge facts as op-name lists.

## Provenance

Prior-art claims are from a primary-source sweep of OpenJDK master, V8 main,
Graal master and Click & Paleczny 1995, with verbatim quotes. The Chalk-side
claims — Match's inputs, RegexCapture's direction, and all six exemption
comments — were re-verified by hand against the source files before writing,
rather than taken from the sweep.

COULD NOT CONFIRM in the sweep: `Node::has_special_unique_user` in C2, Click's
thesis (unfetched), arXiv:2107.01815 body (PDF unparseable).
