# The node type and TypeLibrary are the authorities; the registries are not

**Date:** 2026-08-13
**Status:** PLAN, v2. Step 1 is LANDED (commit 20e31d5d). Steps 2-5 not started.
**Evidence:** `docs/research/2026-08-13-arm-content-inspection-measured.md` (measurement),
`docs/research/2026-08-13-branch-merge-prior-art.md` (107-agent survey, verified)
**Assessment:** v1 was adversarially assessed and came back with two BLOCKING
findings, both reproduced by hand. v2 is the rewrite. What v1 got wrong is
recorded in "What the assessment killed" below, because the errors are more
instructive than the plan.

## The problem, stated once

Chalk answers three different questions by consulting hand-maintained tables of
op NAMES, when two of them are properties the code already owns:

| question | answered today by | should be answered by |
|---|---|---|
| does this node have an EFFECT? | `%STATEMENT_EFFECT_OPS` (10 names) | the node TYPE |
| what OPERAND TYPES does this operator take? | `%_STR_CONTEXT_OPS` (3 names) | `TypeLibrary` |
| is this a CFG node? a pure value? a mutable read? | more op-name registries | case by case — see step 4 |

Measured, and independently reproduced: **39 uppercase-hash registries in
`lib/`** (the count needs `%_?[A-Z]` — a plain `%[A-Z]` regex gives 34 and
misses `%_STR_CONTEXT_OPS`), **at least 12 keyed by op name across 4 files**
(not 5, as v1 said), and **96 `operation eq '<Op>'` comparisons over 19 distinct
ops**. Every one of the 86 node kinds is already a Perl class.

**The 96 number is measure-sensitive and should not be leaned on.** A broader
honest measure (`$op eq '...'` anywhere) gives 231 over ~53 ops. And of the
strict 96, 75 live in `Serialize/JSON` and `LLVM/Context` — serializer
round-tripping and emitter dispatch, which are LEGITIMATE dispatch. The
fraction that answers a question about a node's NATURE is a minority. The
argument here rests on the specific incompletenesses below, not on a raw count.

### The registry gaps that are real

- **`%STATEMENT_EFFECT_OPS` omits `Unwind`** — the node for `die`, which
  ABORTS. Verified: `NodeFactory.pm:155-158` lists ten ops, no Unwind. A
  diamond-collapse pass consulting this registry would judge a die-only arm
  effect-free and fold it into a select: exactly the miscompile class closed
  three times this month.

  But the two `eq 'Unwind'` sites are NOT "compensation" for the gap, as v1
  claimed. `Context.pm:2649` is the mainline-die abort arm and `:3151` is
  `_find_unwind_consumer` — Unwind-specific LOWERING and ROUTING. They must
  survive. And the registry omission is partly deliberate: `Actions.pm:1701-1716`
  handles Return/Unwind BEFORE the effect-table branch, because they terminate
  the chain rather than advancing it.

- **`%_STR_CONTEXT_OPS` lists `Print StrEq StrNe`** (`Serialize/JSON.pm:786`);
  `StrLt StrGt StrLe StrGe StrCmp` also take Str. **FIVE** omissions, not six —
  `Concat` is NOT one. Concat coerces at the producer build site
  (`FromOptree.pm` multiconcat decoder: "Interpolation is COERCION") and the
  backend hard-dies otherwise (`Context.pm:913`: "GAP: Concat with repr=...
  requires Str operands"). An uncoerced Concat is a loud GAP, not a silent
  miscompile.

  The five are real and masked exactly as v1 said: the backend lowers only
  StrEq/StrNe (`Context.pm:447-448`) while the producer DOES emit StrLt
  (`FromOptree.pm:57`).

### TypeLibrary knows some of it, and is wrong about the rest

`%BINARY_OP_SIGNATURES` is NOT complete, as v1 claimed. `'&.' '|.' '^.' '^^'`
are in `Actions.pm`'s `%BINOP_MAP` but absent from it. Its only lib/ consumers
are `TypeInferenceActions.pm:145` and `:161`, via `get_binary_op`/`get_unary_op`
— v1 got this right only on the second attempt, having first claimed ZERO
consumers by grepping the hash name instead of the accessor.

More seriously: **TypeLibrary is currently WRONG about print.**
`TypeLibrary.pm:156` says `print => { arg_types => ['Any'] }`. The landed
contract (commit 53d2011e) is that Print takes **Str**. TypeLibrary contradicts
the behaviour `%_STR_CONTEXT_OPS` implements.

## Why this is the blocker for the branch-merge work

**It mostly is not.** v1 claimed steps 2-4 gate step 5. The assessment showed
step 5's only real precondition is step 1, which is landed. Steps 2-4 are
registry hygiene in chalk; step 5 is a producer fix in perl5-son. Nothing in
2-4 consults the branch-merge code and nothing in step 5 consults the
registries being deleted.

What survives of the argument: the prior-art survey found the collapse decision
is a LATER pass whose precondition is one uniform per-instruction predicate.
Graal's elegance is that because effectful nodes are fixed BY TYPE, its test
degenerates to "is the arm empty?". Step 1 gives Chalk that predicate. That is
the prerequisite, and it is met.

## Steps

### Step 1 — `is_fixed` on the node type — LANDED (20e31d5d)

`Chalk::IR::Node::is_fixed` defaults false; overridden true on the 11 effectful
classes (the 10 registry entries plus `Unwind`). `t/bootstrap/ir/node-is-fixed.t`
pins agreement with every registry entry AND the `Unwind` gap.

Verified on committed HEAD: corpus gate `gate-green=194 behavior=194 shape=194
invariant=194 worklist=0`.

One defect found in assessment and fixed before commit: the agreement subtest
`pass()`ed when a node could not be constructed, so CompoundAssign reported
agreement it had never checked. It now supplies each class's real required
params and a construction failure is a FAILURE.

### Step 2 — fix TypeLibrary, THEN route the IR side to it

**v1's version of this step was unexecutable.** It proposed building
`signature_for_ir_op` from `%BINARY_OP_SIGNATURES` + `Actions.pm`'s map — but
`Print` is in neither (it is not a binary operator), and TypeLibrary's actual
authority for it, `%BUILTIN_SIGNATURES`, says `Any`. Routing
`_insert_str_coercions` through that either returns undef (coercions silently
stop) or `Any` (no coercion inserted), regressing the landed Print behaviour —
which is the only currently-exercised member of the set.

Revised, in order:

**2a. Make TypeLibrary correct about print/say.** `arg_types => ['Str']`,
matching commit 53d2011e. This is a prerequisite, not a detail.

**2b. Handle the many-to-one map before building any accessor.** Inverting
`%BINOP_MAP` is many-to-one: `And`←{`&&`,`and`}, `Or`←{`||`,`or`},
`Xor`←{`^^`,`xor`}, `BitAnd`←{`&`,`&.`}, `BitOr`←{`|`,`|.`},
`BitXor`←{`^`,`^.`}, `Range`←{`..`,`...`}.

No pair currently has two CONFLICTING registered signatures — but only because
the string-bitwise ops are absent from `%BINARY_OP_SIGNATURES` entirely. The
bitwise trio is a genuine defect in the plan's own premise: string-bitwise
`'&.'` (Str) and numeric `'&'` (int,int→int) lower to the SAME node type
`BitAnd`. For that family **the node type does NOT own the operand types**.

So the accessor must (i) assert no collision has conflicting signatures and die
if one does, and (ii) carry a documented carve-out for the bitwise family until
either the node types split or the string-bitwise ops are lowered. Do not paper
over this: it is the one place the plan's thesis is false.

**2c. Only then** give TypeLibrary `signature_for_ir_op` and have
`_insert_str_coercions` ask it per operand position.

ACCEPTANCE: `%_STR_CONTEXT_OPS` is deleted; Print's coercion behaviour is
unchanged (corpus gate holds at its floor, all four legs); a unit assertion
that a non-Str operand of `StrLt` gets a coercion (StrLt is unlowered, so this
CANNOT be a corpus case); a unit assertion that the accessor DIES on a
conflicting collision rather than silently picking one.

### Step 3 — retire `%STATEMENT_EFFECT_OPS` (harder than v1 said)

v1 said "replace its consumers with `$node->is_fixed`; five call sites; the two
`eq 'Unwind'` special cases go with it." Every clause of that is wrong.

**The real consumers** (verified): `Actions.pm:1718`, `Target/LLVM.pm:420`,
**`NodeFactory.pm:304`**, and `is_statement_node` (`NodeFactory.pm:390-395`)
with three callers — `Context.pm:2629`, `Context.pm:3740`, `Elaborate.pm:377`.
`TypedInvariant.pm` has NO consumer; it is comments only, and `TypedInvariant.pm:80-85`
explicitly warns that deriving from this table "would be the wrong source; that
mistake was already made twice."

**Three things block a mechanical swap:**

1. **`Context.pm:2629` before `:2649`.** The elsif chain tests
   `is_statement_node($op)` BEFORE `$op eq 'Unwind'`. Swap :2629 to `is_fixed`
   and Unwind — now true — matches the statement branch first, making the abort
   arm UNREACHABLE. Mainline `die` gets `lower_value` instead of an abort:
   lli exit 0 where perl exits 255. That is the miscompile corpus T2c pins,
   reintroduced. Any change here reorders the arms first.

2. **`NodeFactory.pm:304` needs the answer BEFORE a node exists.** It is inside
   `make()`, deciding per-call identity vs hash-consing. `feature class` methods
   cannot be invoked on a class name. Feasible — `make()` already builds a temp
   node at :319 for content_hash — but it is a rework of the identity path, not
   a swap, and it touches hash-consing. Treat it as its own commit with its own
   corpus verification.

3. **`is_statement_node` bundles `VarDecl`**, which is not `is_fixed`. The
   replacement predicate must keep it, or the collectors drop declarations.

Also in the same commit: `t/bootstrap/ir/statement-effect-identity.t` pins the
table as "the shared contract."

ACCEPTANCE: zero references to `%STATEMENT_EFFECT_OPS` outside the deletion
commit; the two `eq 'Unwind'` sites still present and reachable, with a test
that a mainline die still aborts (exit 255, matching perl); corpus gate
unchanged all four legs; the `is_fixed` agreement subtest DELETED in the same
commit rather than left vacuous.

### Step 4 — the remaining op-name registries, one per commit

Not a sweep. Two of v1's targets are documented deliberate designs and are
KEEPERS unless something new is learned:

- **`%CONTROL_CHAIN_OP`** (`TypedInvariant.pm:78-119`) is a producer
  build-site-policy invariant, explicitly NOT effectfulness. RegexSubst /
  RegexMatch / Match are `is_fixed` yet deliberately unpinned, value-ordered
  through data edges. Replacing it with `is_fixed` is the twice-made mistake
  its own comment names.
- **`%ROUTED_CFG`'s** exclusion of Start/Return/Unwind is documented intent
  (`NodeFactory.pm:119-124`) — an identity-semantics distinction, not
  incompleteness. v1's "Start, Return, MemStart, Unwind are CFG classes too"
  was a misreading.
- **`%DATA_CLASSES`** maps op name BACK to the class and is load-bearing for
  deserialization. Keeper in some form.

That leaves `%MUTABLE_READ_OPS`, `%PURE_DESCEND_OPS`, `%ALLOC_OPS`, and the
three `OP_*_REPR` tables as the actual candidates. Each gets its own commit and
its own completeness check against the class list.

### Step 5 — the branch-merge fix (NOT gated on 2-4)

Unblocked NOW by step 1. Delete the four `_arm_has_*` predicates and their 15
call sites, build control flow unconditionally in void context, add the collapse
pass.

Its gate is a per-node speculation predicate — NOT a disjunction of effect
kinds, and NOT `!is_fixed`. Skip the cost budget initially, per the research
doc's own recommendation.

The RED already exists and is genuinely red (verified):
`perl5-son/t/from-optree-modifier-effect-in-arm.t` (uncommitted) — subtests 1-2
fail with "GAP: statement modifier with a void effect / element store / die
inside an if/else arm not yet lowered"; the pure-rebind and top-level partners
pass, so a fix cannot pass by disabling the value-merge path.

## Risks

- **Step 5 has a known trap.** A nested `if` inside an arm compiles to the SAME
  `and` op as a statement modifier. An earlier attempt (reverted) silently
  dropped a nested element store: `if ($c) { if ($d) { $a[0] = 9 } }` printed 1
  where perl prints 9, and the untaken polarity PASSED. Test both polarities of
  both shapes.
- **Speculation safety is strictly stronger than effect-freedom.** LLVM's
  `isSafeToSpeculativelyExecute` also rejects pure-but-faulting operations —
  division, loads from non-provably-dereferenceable pointers, malloc,
  terminators, phis. `is_fixed` alone is NOT the collapse gate.
- **`is_fixed`'s false default is NOT "safe".** v1 said it was safe for
  control-chain threading "which only ever needs to include more." Backwards:
  for threading, a false NEGATIVE — a new effectful class forgetting to
  override — silently drops the node from the chain, which is the research
  doc's bug #2 (terminating arms dropped). The mitigation is not the default;
  it is the per-registry completeness check in step 4 and the agreement test in
  step 1.

## What the assessment killed

Recorded because the error pattern repeats:

1. **Claimed `%BINARY_OP_SIGNATURES` COMPLETE.** It is missing four ops. I had
   already been wrong about this table once (claiming zero consumers by
   grepping the hash name rather than the accessor) and did not re-derive it.
2. **Claimed six Str omissions.** Five. `Concat` coerces at the producer and
   GAPs loudly in the backend — I asserted a gap without checking whether the
   mechanism was elsewhere.
3. **Claimed the `eq 'Unwind'` sites were registry compensation.** They are
   lowering and routing, and deleting them reintroduces a fixed miscompile.
4. **Claimed five step-3 call sites**, listing one that does not exist
   (TypedInvariant, comments only) and omitting the one that is hardest
   (NodeFactory.pm:304, which needs the answer before a node exists).
5. **Claimed step 5 was gated on steps 2-4.** It is gated on step 1 alone. The
   ordering was a preference presented as a necessity — which would have
   delayed the actual miscompile-class fix behind three refactors.
6. **Leaned on "96 comparisons"** while conceding in a closing caveat that most
   are legitimate dispatch. The headline used a number the body disowned.

The through-line: I measured, then reasoned from the measurement without
re-deriving it, and every claim I did not re-derive was wrong in the direction
that supported the plan.
