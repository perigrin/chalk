# The node type and TypeLibrary are the authorities; the registries are not

**Date:** 2026-08-13 (step 4 rewritten 2026-08-15)
**Status:** PLAN, v3. Steps 1 and 2 are LANDED (`20e31d5d`; `075e5f9c`,
`005ee5e6`, `b5383f9c`, `5f1573c7`). Step 3 is DEPRIORITISED on measurement —
its safety is already banked by step 1's test; see its DO-NOT-RETRY note.
Step 4 is the live work and was REWRITTEN: v2 drafted it as a cleanup sweep
and never named the mechanism step 1 had just proved. Step 5 is BLOCKED in the
backend after four attempts (`docs/plans/2026-08-13-post-merge-statement-ownership.md`).

**Next action: step 4a** (`staleness_kind`) — the only registry measured to
silently miscompile, and the only one with no completeness test.
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
| does this node have an EFFECT? | `%STATEMENT_EFFECT_OPS` (10 names) | the node TYPE — `is_fixed`, LANDED |
| what OPERAND TYPES does this operator take? | `%_STR_CONTEXT_OPS` (3 names) | `TypeLibrary`, LANDED |
| may a cached value for this node go STALE? | `%MUTABLE_READ_OPS` + `%PURE_DESCEND_OPS`, third bucket implicit | the node TYPE — `staleness_kind`, step 4a |
| is this node hash-consed or per-call? | 4 tables + 2 constructors + 3 hardcoded ops | the node TYPE — `identity_kind`, step 4b |
| may this WIRE STRING become a class? | `%DATA_CLASSES` | stays a table — it is a trust boundary, step 4c |
| does the PRODUCER pin this op to the chain? | `%CONTROL_CHAIN_OP` | stays a table — it is perl5-son's policy, step 4d |

The first two rows are done. The rest are step 4, and the pattern is the one
step 1 proved: **a question about a node's nature belongs on the node class.**
The two "stays a table" rows are the genuine exceptions, and each is an
exception for a specific measured reason rather than by default.

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

**LANDED** — 2a in `075e5f9c`/`005ee5e6` (floor 194→196), 2b/2c in `b5383f9c`,
corrected in `5f1573c7`. Corpus gate self-verified at gate-green=196
behavior=196 shape=196 invariant=196 worklist=0.

**2a's stated fix was SUPERSEDED and deliberately not applied.** This step said
to make TypeLibrary `print => arg_types => ['Str']`. That is wrong, for the
reason this same step gives above: `print` is variadic over `Any` BY DESIGN
because perl flattens a list into it, and tightening it rejects `print @a`,
`print undef`, `print $ref` at parse time (`TypeInference.pm:391` returns undef
= kills the parse). `TypeLibrary.pm:156` still reads `['Any']` and should stay
that way. The Print NODE's Str-only contract is a DIFFERENT claim at a
different layer, and it lives in `%_NODE_OPERAND_REPR` in `Serialize/JSON.pm`.
Print is deliberately absent from the IR-op map. The corpus case pinning this
is "Print an ARRAY flattens it and coerces each element" in
`t/corpus/mdtest/statements.md`.

**Two defects found while writing the required assertions**, neither
anticipated here, both fixed in `b5383f9c`:

1. The variadic rule (`$args->[-1]`) was applied to NON-variadic signatures.
   `length` is `arg_types => ['Str']` — one entry — yet the accessor claimed
   Length wanted Str at position 1, 5, any position. The rule holds only where
   a signature IS variadic (a trailing `Any`).
2. `Ord` and `Chr` mapped node types that DO NOT EXIST (the factory rejects
   both). They could never be consulted, so they pinned nothing while reading
   as coverage — and `type-library.t` asserted their answers, the same vacuous
   shape one layer up. The map is now checked against the factory.

Neither was reachable as a miscompile: every remaining mapped op has a
SYMMETRIC `(Str, Str)` signature, so a wrong position returns the right answer.
That masking ends the moment an asymmetric op is added, and `x` `(Str, Int)`
and `substr` `(Str, Num, Num)` are already in the table.

**A claim made and RETRACTED here, recorded so it is not re-derived:** that a
BinOp carries a leading control slot, so the inputs index diverges from the
signature position. It does not. Control rides its own `control_in` wire key
(`Serialize/JSON.pm:292-299` calls the flattening "the old convention"), and
the producer emits `Concat(%lhs, %rhs)` — two operands, no control slot. The
wrong claim came from copying `inputs => [undef, $a, $b]` out of
`graph-bidirectional-traversal.t` and reading a hand-written test's local
convention as the producer's shape.

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

**DO NOT RETRY AS WRITTEN — deprioritised on measurement, 2026-08-15.** All
three blockers above are CONFIRMED real (measured directly, note the line
numbers have drifted: the sites are now `Context.pm:3020`, `:4131`,
`Elaborate.pm:377`):

| op | `is_fixed` | in table | `is_statement_node` |
|---|---|---|---|
| the 10 members | YES | YES | YES |
| `VarDecl` | **no** | no | **YES** |
| `Unwind` | **YES** | **no** | no |

`is_statement_node` is exactly "`is_fixed` minus Unwind, plus VarDecl". The
Unwind hazard is real: `Context.pm:3020` tests `is_statement_node` BEFORE
`:3040`'s `eq 'Unwind'`, so a naive swap makes the abort arm unreachable and
reintroduces the miscompile corpus T2c pins.

**But the safety this step would buy is ALREADY BANKED.** Step 1 shipped
`node-is-fixed.t`, which pins agreement on all 10 registry entries AND
explicitly pins the Unwind gap — verified running. The two mechanisms cannot
silently diverge today. So this step is a risky deletion, touching the identity
path and the abort arm, in exchange for tidiness rather than safety.

Step 4a is the same KIND of work with a live silent-miscompile risk and no test
at all. Do that first. Revisit step 3 only if the registry and `is_fixed` are
ever found to disagree, or as the last cleanup once 4a/4b have landed.

### Step 4 — the remaining registries become TYPE PROPERTIES

**v2 drafted this as a cleanup sweep and never named the mechanism.** That was
the defect: step 1 had just proved the mechanism one page earlier — put the
answer on the node class, keep the registry, pin agreement with a test, delete
the registry later — and step 4 did not reuse it. Read as written it looks like
low-value hygiene, which is how it was repeatedly deprioritised. It is not: it
is the plan's own thesis (see the table in "The problem, stated once", whose
third row names exactly these registries), applied to the registries step 1 did
not reach.

Every one of the 86 node kinds is already a Perl class. A question about a
node's NATURE belongs on that class.

**The pattern, from step 1 (do not invent a new one):** add the method with a
safe default on `Chalk::IR::Node`, override on the classes that differ, land a
test pinning that the method and the registry AGREE on every op the registry
names, and only then delete the registry. This is what makes the deletion
provably behaviour-preserving, and it is what lets `NodeFactory.pm:304` keep
consulting a table while the type property is being established.

#### 4a. `staleness_kind` — DO THIS FIRST, it is the only live silent miscompile

`%MUTABLE_READ_OPS` (4 ops) and `%PURE_DESCEND_OPS` (46 ops) at
`Context.pm:584-600` implement ONE predicate, `_reads_mutable_location`: may a
cached SSA ref for this node go stale across a store?

The `if/elsif` at `:615-632` makes a THIRD bucket implicit — 27 ops in neither
table, which fall through to "no". Measured, that bucket is two unrelated
groups that coincidentally want the same answer: 17 statement-effects (fixed at
a control position) and 10 others (`Constant`, `Phi`, `Start`, `ArrayRef`,
`StructFieldAccess`, `Yada`, ...).

**This is the dangerous shape in the whole plan.** Membership in the answering
bucket is defined by ABSENCE from two lists, and a miss returns a confident
wrong answer — a stale SSA ref served across a store, which is the bug class
(`whole-branch review C1/C2`) the comment itself names. Verified: **no test
pins either list's completeness** (`llvm-mut-read-memo-cross-graph-collision.t`
covers memo KEYING, a different bug).

Contrast `%DATA_CLASSES`, where a miss `die`s. Loud registries can wait; this
one cannot.

`staleness_kind` returns `mutable_read` / `transparent` / `opaque`. Note
`Coerce`, `Interpolate`, `TernaryExpr` are in the descend list and are not
"pure" in any ordinary sense — the property is TRANSPARENCY (my value is stale
exactly when an input's is), not purity. Name it accordingly.

**`StructFieldAccess` is the shape to watch, but it is NOT live today.** It is
a field access landing in the silent-`opaque` bucket by absence while
`FieldAccess` is in `%MUTABLE_READ_OPS` — but measured, it has ZERO references
in the LLVM backend. It exists only in `StructPromotion` (analyze-only) and the
parked Perl target, so it never reaches `_reads_mutable_location`. It is
therefore a latent misclassification that goes live the day the struct path
does, not a bug to fix now. Classify it deliberately rather than by absence,
and say which bucket and why.

ACCEPTANCE: a completeness test asserting every op in the wire allowlist is
classified exactly once across the three buckets, so a new op FAILS rather than
silently answering `opaque`; agreement with both existing tables on every op
they name; corpus gate unchanged all four legs.

#### 4b. `identity_kind` — and the two-constructor split behind it

**v2 missed this entirely.** It called `%ROUTED_CFG`'s Start/Return/Unwind
exclusion "documented intent" and stopped. The comment it trusted
(`NodeFactory.pm:119-124`) actually says `%ROUTED_CFG` holds ops "that have CFG
semantics ... but are constructed via `make()` rather than `make_cfg()`" —
which is not a semantic distinction at all. It is an artifact of an unfinished
Bootstrap migration.

Measured:

- `make_cfg` has **5 real call sites** — 4 in the legacy hand-written
  `Actions.pm` frontend, 1 generic in the loader (`Serialize/JSON.pm:483`).
- `%CFG_CLASSES` declares 7 ops, but `If`/`Proj`/`Region`/`Loop` are **never**
  called through it. They get per-call identity via `%ROUTED_CFG` through
  `make()` instead — and they are also the ONLY ops reaching `make()` that are
  absent from `%DATA_CLASSES`.
- `Start`/`Return`/`Unwind` are in **both** tables, so the same op gets
  different identity depending on the entry point rather than on the node.
- Every justification in the comments is historical: "used to be constructed
  via Bootstrap::make()", "Mirrors Bootstrap's %CFG_OPS", "legacy Bootstrap API
  shape". `Phi` has a hand-written special case at the top of `make()`
  (`:200-241`) purely to keep the legacy call shape working.

The IR has ONE genuine distinction here — hash-consed by content vs per-call
identity. Today it is assembled from `%STATEMENT_EFFECT_OPS` ∪ `%ALLOC_OPS` ∪
`%ROUTED_CFG` ∪ `%CFG_CLASSES`, with `Phi`/`VarDecl`/`ListAssign` hardcoded
ahead of all of them. `%ALLOC_OPS` folds in here: "each occurrence allocates"
is what `ArrayRef` IS.

This is the "literal moved, contract didn't" shape CLAUDE.md names for the MOP
migration. It touches the identity path and hash-consing, so it is its own
commit with its own corpus verification — and it is gated on 4a landing first,
because 4a is the live risk and this is structural.

**Constraint the refactor must respect (see 4c): `make()` needs the identity
answer BEFORE a node exists, and `is_fixed` is a `feature class` method that
cannot be called on a class name.** That is `NodeFactory.pm:304`. The step-1
pattern already handles it — the registry survives until the property is
established — but a design that assumes it can ask the node first is wrong.

#### 4c. `%DATA_CLASSES` is NOT a node property — it is a trust boundary

v2 called it "load-bearing for deserialization. Keeper in some form," which is
right for a reason it did not state, and the reason changes what may be done to
it.

Measured: **55 of its ~70 entries are constructed nowhere in `lib/` by a
literal name.** Every arithmetic op, every comparison, `Print`, `Assign`,
`PadAccess` — no static `make('Add')` call exists. They are reachable ONLY
through the dynamic loader at `Serialize/JSON.pm:486`, where `$op` is a string
decoded off the JSON wire.

So `%DATA_CLASSES` is not describing nodes. It is the allowlist deciding which
wire strings may become classes, and a miss `die`s ("Unknown data node
operation") — the GAP-not-miscompile invariant working as intended. A node
cannot carry it: it is consulted BEFORE there is a node.

It also has zero drift, verified against the filesystem: no phantom entries,
and the 9 unlisted `.pm` files are 6 abstract bases (`Node`, `BinOp`,
`UnaryOp`, `Access`, `Aggregate`, `Regex`) plus the 4 CFG classes.

ACTION: rename to `%KNOWN_OPS` (or similar) and document it as the wire
boundary. Do NOT delete it, and do NOT replace it with autoloading
`Chalk::IR::Node::$op` — that trades an allowlist for arbitrary class loading
from untrusted input. Its routing role, which is the part that IS an artifact,
is what 4b removes.

#### 4d. `%CONTROL_CHAIN_OP` stays a table — the genuine exception

Confirmed keeper, and worth stating why in the terms of this step: it is NOT a
property of Chalk's node type. It is a property of **perl5-son's build sites**,
derived by reading the producer at SHA `40d8f8b` — every entry in
`TypedInvariant.pm:78-119` cites a producer file:line, and `Assign` is in the
set EXCEPT at the list-assign fallback (`FromOptree.pm:2067`).

Putting this on the node type would assert a cross-repo build-site policy as an
intrinsic fact. Its own comment records that deriving it from the effect table
"would be the wrong source; that mistake was already made twice." It stays a
table, in the repo that checks the invariant.

#### The end state

One allowlist at the wire boundary (4c), three type properties on the nodes
(`is_fixed` from step 1, `staleness_kind` from 4a, `identity_kind` from 4b),
and one producer-policy table (4d). That replaces 7 tables and the
two-constructor split.

The three `OP_*_REPR` tables are NOT part of this step. They are a repr
question, and `docs/plans/2026-08-14-representation-is-the-targets-type-system.md`
owns that axis.

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

## What v2's step 4 got wrong (found 2026-08-15, on execution)

A different failure from the six above: not a wrong measurement, a **missing
mechanism**. Recorded because the consequence was worse than a wrong number.

Step 1 proved the pattern — put the answer on the node class, keep the
registry, pin agreement, delete later. Step 4, written on the same day, one
page below it, described its own work as "the remaining op-name registries, one
per commit" and never mentioned that pattern. It then spent most of its length
arguing three registries were KEEPERS and left the actual targets as a bare
list.

The result: step 4 read as low-value hygiene and was repeatedly deprioritised —
by me, in this session, three times — while the plan's TITLE says the node type
is the authority and its problem statement names those exact registries. The
work was never out of scope; the step just did not say what it was.

Three of the four keeper/candidate rankings were also backwards on the axis
that matters, which only surfaced once each was measured:

1. **`%PURE_DESCEND_OPS` ranked as a "candidate."** It is the ONLY registry
   measured to silently miscompile — a miss serves a stale SSA ref across a
   store — and it has no completeness test. It should have been ranked first.
2. **`%DATA_CLASSES` called a keeper for the wrong reason** ("load-bearing for
   deserialization"). It is a keeper because it is a TRUST BOUNDARY: 55 of ~70
   entries exist only to validate strings arriving off the wire. That reason
   also forbids the obvious "just autoload the class" fix, which the v2 wording
   would not have caught.
3. **The two-constructor split was not noticed at all.** `%ROUTED_CFG`'s
   exclusion was accepted as "documented intent" by reading a comment that
   actually documents an unfinished Bootstrap migration.

The lesson generalises past this plan: **a step that names its targets but not
its mechanism will be read as optional.** When a preceding step establishes a
pattern, the following step must say it is applying it.
