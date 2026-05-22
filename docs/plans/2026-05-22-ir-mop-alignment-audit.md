# IR / MOP Alignment Audit — Phase 3d + Phase 3e

**Date:** 2026-05-22
**Branch:** `fixup-audit-baseline`
**Commit range audited:** `e50d76ba..0d986d1b` (Phase 3d steps 1–7 plus
Phase 3e, plus the corpus alignment audit).
**Method:** code reading, plan-vs-code comparison, isolation probes
(`/tmp/probe-*.pl`).

This audit is read-only. It produces a punch list. Decisions on what
to do with the punch list belong to perigrin.

---

## Executive summary

**Verdict: DRIFT WITH KNOWN GAPS.**

Phase 3d/3e mechanically closed the [miss] and [unreach] gaps the IR
completeness audit found. The new tests pass (315/316 with M7 as a
documented TODO). No prior tests regressed.

But the work landed against a stale architecture spec, and the spec
itself is now out of sync with the code in three places that touch the
new fields. Specifically:

1. **`mop.md` claims per-method factory ownership** ("two methods with
   structurally identical bodies still produce distinct node objects").
   The code does not implement this — `Chalk::MOP::Method->factory` is
   a fresh default-initialized factory that the action layer never
   uses. Production nodes are constructed via a single per-Actions
   factory, then handed to a `MOP::Method` instance whose own factory
   is dead. This drift predates Phase 3d but is now load-bearing: the
   new `set_control_in` setter relies on consumer-list locality
   guarantees that the documentation justifies via per-method
   ownership.

2. **`If->region`, `Loop->region`, `Node->control_in`, and `for_init`
   annotation are write-only in production.** Only the writer site
   (the Block fixup pass in `Actions.pm` and ForStatement's annotation
   stash) and a small set of test/probe walkers ever read them.
   Codegen does not consume them. The accessors exist to make the
   Block fixup pass and `ir-completeness.t`/`build-graph-for-loop.t`
   work; they are not part of any external contract today.

3. **`PostfixModifier` does not merge its constructed If/Loop/Proj/Region
   into the graph.** D4/D5/M5/M6 nevertheless pass `ir-completeness.t`
   because `Graph::nodes()` follows `inputs` unconditionally — the
   nodes reach the result via input-closure from `Return`, not via
   cache membership. This works today; it relies on documented but
   fragile graph-walking semantics (`sea-of-nodes-ir.md:240`).

4. **`Chalk::MOP::Method->{make,make_cfg,merge}` delegators are dead
   code.** Production code calls `$ctx->factory->make` directly. The
   MOP delegators (`MOP/Method.pm:25-28`, `MOP/Sub.pm:23-26`) are
   uncalled. Removing them is plan-discipline cleanup; keeping them
   while documenting the per-method ownership claim creates a false
   impression.

5. **The master MOP migration plan does not mention Phase 3d or 3e.**
   Phase 3a-migration's claimed exit criterion ("computation actions
   build the graph incrementally via `$graph->merge(...)` inside each
   action") was not met when 3a-migration shipped; Phase 3d retrofit
   the missing merges. The master plan's Current State section was
   updated through Phase 7d but does not reflect this retrofit. Phase
   3a-migration's status in `MEMORY.md` is still "COMPLETE 2026-05-20"
   without the qualifier the 2026-05-22 Phase 3-4 reality audit
   explicitly recommended.

None of (1)–(5) blocks Phase 3d/3e from being "useful enough that
ir-completeness.t passes." All of them compound if the scheduler
design proceeds against the current state. Recommended remediation is
small to medium total work and concentrated in documentation +
trivial cleanup.

---

## Concern 1 — Architecture doc claims

### Finding 1.1 — Per-method/per-sub factory ownership: DRIFT

**Claim** (`docs/architecture/mop.md:84-118`, `:167-194`):

> Each `MOP::Method` and `MOP::Sub` owns its own `Chalk::IR::Graph` and
> `Chalk::IR::NodeFactory`, so two methods with structurally identical
> bodies still produce distinct node objects with bounded consumer
> lists.

> The MOP and every factory it transitively owns are **per-parse**: [...]
> Each `declare_method`/`declare_sub`/`declare_adjust` on a `MOP::Class`
> allocates a fresh `Graph` and `NodeFactory` for the new
> method/sub/phaser. Identity of nodes is meaningful only within that
> owner's scope.

**Implementation:**

- `lib/Chalk/MOP/Method.pm:17`: `field $factory :param :reader =
  Chalk::IR::NodeFactory->new;` — a per-Method field default.
- `lib/Chalk/MOP/Class.pm:41-49`: `declare_method` does not pass
  `factory => ...`. The Method takes the field default, allocating a
  *fresh* factory that Actions never injects into.
- `lib/Chalk/Bootstrap/Perl/Actions.pm:82-93`: Actions's `ADJUST`
  allocates ONE `Chalk::IR::NodeFactory`, binds it to both `$factory`
  and `$typed` fields, and calls
  `SemanticAction::set_factory($typed)`.
- `lib/Chalk/Bootstrap/Perl/Actions.pm:325,1074,1194,1257,1303, ...`:
  Action methods call `$ctx->factory->make(...)` — the
  SA-injected/per-Actions factory, NOT the per-Method factory.
- `lib/Chalk/MOP/Method.pm:25-28`: `merge($node) {
  $graph->merge($node) }`, `make($op, %a) { $factory->make($op, %a) }`,
  etc. — these delegators would route through the per-method factory
  but **no production code calls them**.

Probe `/tmp/probe-factory-id.pl` verified this empirically:

```
Method a factory refaddr: 94259256835784
Method b factory refaddr: 94259257053368
SA injected factory refaddr: 94259267809176
```

Three distinct factories per parse: per-Method-a, per-Method-b, and
the SA-injected one that actually built every node.

**Verdict: DRIFT.**

Per-method ownership is documented, partially scaffolded (Method has
the field; delegators exist), but not realized. Production nodes
share one per-parse factory. The doc's claim about "distinct node
objects" between methods with identical bodies is not true today; if
two methods both use, say, `Constant("hello")`, they share a single
Perl object because of the shared factory's hash-cons cache.

This was true before Phase 3d/3e. Phase 3d/3e neither introduced nor
fixed it. But it is now *more* load-bearing because:

- The new `Node->set_control_in` setter mutates `$control_in` on a
  hash-consed data node. If two statement-position `Call`s with
  identical (name, args) hash-cons together (and they do, because
  factory is shared), they'd be the **same Perl object** — and the
  second `set_control_in` overwrites the first.

In practice this hasn't surfaced because (a) `control_in` is excluded
from `content_hash` so any non-trivial difference in *inputs* between
two calls (e.g., a different bound variable) breaks the hash-cons
collision, and (b) statement-position bare calls in Chalk's actual
test corpus rarely have identical (name, args) shapes. But the
`Node.pm:80-89` `set_control_in` has no assertion or guard against
the collision; the design comment in
`docs/plans/2026-05-22-phase-3d-effect-chain-completion.md:357-372`
acknowledges this risk under "Risk 1: hash-cons interaction with
mutation" and proposes (but did not implement) an assertion that the
field is unset or being set to the same value.

**Suggested remediation shape:**

Choose one:

- **(a)** Update `mop.md` to reflect reality: per-parse factory
  ownership, with `MOP::Method->factory` as currently-unused
  scaffolding for a future migration. Delete the dead delegators on
  `MOP::Method` and `MOP::Sub` (or mark them clearly as unused).
- **(b)** Make `declare_method`/`declare_sub` actually use the
  Method's own factory: in Actions, change `$ctx->factory->make(...)`
  sites that occur inside method/sub scope to use the owning
  Method/Sub's factory. This is the larger fix; it matches the doc
  but requires Context to carry the current MOP::Method handle (or
  for Actions to look it up from `$ctx->mop`).

(a) is one session of doc + cleanup. (b) is its own phase.

**Side effects:**

- (a) means `MOP::Method->factory` field is misleading dead weight —
  callers reading `mop.md` will believe per-method ownership exists.
- (b) is intrusive: the existing test fixture
  `t/bootstrap/mop/per-parse-factory-thread.t` will need rewriting,
  and the implicit invariant "Constants with the same value across
  methods are the same Perl object" will break (this may surface
  refaddr-comparing tests).

---

### Finding 1.2 — `Graph::nodes()` cache vs reachability: ALIGNED (with subtlety)

**Claim** (`docs/architecture/sea-of-nodes-ir.md:233-249`):

> `nodes()` traverses both edge directions from every node in the
> graph's `%cache`. Inputs are followed unconditionally [...]
> Consumers are followed only when the consumer is itself in
> `%cache`.

**Implementation:** `lib/Chalk/IR/Graph.pm:104-162`. Matches the spec
verbatim.

**Phase 3d concern:** the new `control_in` edge lives on the base
`Node`. `Graph::nodes()` does not follow `control_in` directly. But
because `set_control_in` calls `$ctrl->add_consumer($self)`, the
side-effect node appears in its predecessor's `consumers` list. So
reachability via `Graph::nodes()` works **IF** the side-effect node
is in cache. The Block fixup pass calls `$graph->merge($s)` for
`Call|Assign|CompoundAssign|RegexSubst|TryCatch` (line 1563), so they
ARE in cache. Good.

For `If|Loop` in the same pass (line 1569-1583), the Block fixup
pass does **NOT** call `$graph->merge($s)`. The assumption is that
the owning action (`IfStatement`, `WhileStatement`, `ForeachStatement`,
`ForStatement`) already merged them. This is true for those four
actions. **It is NOT true for `PostfixModifier` (line 2304+).** See
Finding 3.4.

**Verdict: ALIGNED.** The doc accurately describes the traversal
behavior, and Phase 3d's new edge is reachable via the
consumer-walk + cache filter combination. The asymmetry that
`If->control_in` is `undef` while `If->inputs[0]` carries control
(because `If::set_control_in` overrides mutate `inputs[0]`, see
Finding 4.2) is paper-cut-ergonomic but does not break traversal: a
walker that follows `inputs` plus `control_in` covers both cases.

**Caveat:** A future reader who only knows about `control_in` could
write a walker that misses If/Loop's control edge. The probe and the
two new tests
(`t/bootstrap/mop/ir-completeness.t:80-100`,
`t/bootstrap/mop/build-graph-for-loop.t:46-53`) correctly walk both
`inputs` and `control_in`. Tests authored later may not.

---

### Finding 1.3 — Hash-cons identity vs `control_in`: ALIGNED

**Claim** (`docs/architecture/sea-of-nodes-ir.md:14-19`):

> Hash consing for data nodes. Two data nodes with identical
> operations and identical inputs are guaranteed to be the same
> object.

> Immutability. Once a node is constructed through `NodeFactory`, its
> operation and inputs are never changed. (The Loop node is the
> single exception: it exposes `set_backedge_ctrl` to wire in the
> back edge after the loop body is built [...])

**Implementation:**

- `lib/Chalk/IR/Node.pm:71-73`: `content_hash() { join('|',
  $self->operation(), $self->_serialize_inputs()) }` — `control_in`
  is NOT in `content_hash`. Good (matches the design intent in
  `Node.pm:25-31`).
- `lib/Chalk/IR/Node.pm:80-89`: `set_control_in` mutates the
  `$control_in` field and updates consumer lists.
- `lib/Chalk/IR/Node/If.pm:32-38` and
  `lib/Chalk/IR/Node/Loop.pm:37-43`: override `set_control_in` to
  mutate `inputs->[0]` instead of `$control_in`. **This violates the
  immutability claim**: `inputs` is mutated post-construction. But
  `Node.pm`'s immutability claim already exempts `Loop` for the same
  reason. Adding `If` to the exemption list is a similar small
  carve-out.

Hash-cons collision risk: see Finding 1.1. `content_hash` excludes
`control_in`, so two `Call(push, [@list, 3])` nodes at different
statement positions hash-cons to the same object. The second
`set_control_in` overwrites the first. This is the Phase 3d-design
"Risk 1." It's not blocking but unguarded.

**Verdict: ALIGNED, with two undocumented exemptions.**

Two notes the doc should mention:

- `Node->control_in` is excluded from `content_hash` by design (the
  `Node.pm:25-31` comment says so but the architecture doc does not).
- `If::set_control_in` and `Loop::set_control_in` mutate `inputs->[0]`
  post-construction, joining `Loop::set_backedge_ctrl` and
  `Phi::set_backedge` in the immutability-exemption list.

The architecture doc's immutability paragraph (line 16-17) currently
lists only `Loop` as the exception. It should be updated to:

> The Loop and If nodes expose `set_backedge_ctrl` /
> `set_control_in` / `set_region` setters; Phi nodes expose
> `set_backedge`. Side-effect data nodes (`Call`, `Assign`,
> `CompoundAssign`, `RegexSubst`) expose `set_control_in` on the
> base `Node` class. These setters are the only post-construction
> mutations permitted on IR nodes.

---

### Finding 1.4 — Context field threading: ALIGNED

**Claim** (`docs/architecture/context-comonad.md:202-216`):

> Context carries [...] threading fields used to propagate per-parse
> and per-method state without a side channel: `mop`, `factory`,
> `scope`, `graph`.

> The rule for the first two is simple: `_one_ctx` sets them, every
> `extend()` call inherits them unchanged unless an explicit override
> is passed. Semiring code reads them via `$ctx->mop` and
> `$ctx->factory`.

**Implementation:** Phase 3d/3e action code reads `$ctx->graph()`,
`$ctx->factory`, `_ctx_scope($ctx)`, `_ctx_control($ctx)`. No
side-channel reads were introduced. `set_type_context()` /
`current_type_context()` bridge (documented as outstanding follow-up
in `context-comonad.md:34-42, 351-362`) is untouched by Phase 3d.

**Verdict: ALIGNED.** Phase 3d/3e did not bypass Context. New code
follows the existing read pattern.

One small inconsistency to note: the Block fixup pass at
`Actions.pm:1518` uses `$ctx->factory->make('VarDecl', ...)` whereas
the same pass at `Actions.pm:1539` uses `$factory->make_cfg(...)`
(class-scope field). Both resolve to the same factory instance per
Finding 1.1. The mixed style is a tiny readability paper-cut, not a
correctness issue.

---

## Concern 2 — Master plan alignment

### Finding 2.1 — Phase 3a-migration was not actually complete: DRIFT

**Claim**
(`docs/plans/2026-04-21-chalk-mop-migration-plan.md:1191-1192`):

> Computation actions build the graph incrementally via
> `$graph->merge(...)` inside each action.

And exit criterion (`:1183-1197`): "Branching and looping code still
works (uses older scope logic without Phis at merge points)" —
implies the chain is established even if Phis are missing.

**Implementation:** Prior to Phase 3d, only `VarDecl` and `Return`
threaded control. `Call`, `Assign`, `CompoundAssign`, `RegexSubst`,
`If`, `Loop`, `TryCatch` did NOT. This was documented in the
2026-05-22 Phase 3-4 audit (`phase-3-4-audit.md:134-219`) which
concluded:

> Problem (2) [side-effect statements not on control chain] is the
> real blocker. It is Phase 3a-migration's unfinished scope. The
> plan's wording ("Call, etc.") implied this was covered; the
> implementation only covered VarDecl/Return.

Phase 3d retrofit the merges. Post-Phase-3d, the exit criterion
holds for every construct in the corpus except M7 (iterator-less
foreach, TODO).

**Verdict: DRIFT.** Phase 3a-migration was declared complete in
`MEMORY.md` ("Phase 3a-migration COMPLETE 2026-05-20") and in the
master plan's silent rollup, but its claimed exit criterion was not
met. Phase 3d closed the gap.

**Suggested remediation shape:**

The master plan's Current State section
(`2026-04-21-chalk-mop-migration-plan.md:189-265`) needs an update.
Recommended diff:

- Add an entry: "Phase 3d (effect chain completion) — **SHIPPED**
  2026-05-22 (commits `7416a5df..ec8b7f2d`). Retroactively closed
  the Phase 3a-migration gap: bare-statement Call, Assign,
  CompoundAssign, RegexSubst, If, Loop, TryCatch all now thread the
  control chain via Block-fixup pass."
- Add an entry: "Phase 3e (C-style for) — **SHIPPED** 2026-05-22
  (commit `0d986d1b`). ForStatement action replaces the prior
  `return undef` stub with a Loop/If/Proj/Region construction; init
  returned alongside Loop via `[init, loop]` arrayref so the Block
  fixup pass chains init before Loop."
- Downgrade the "Phase 3a-migration complete" memory note to "Phase
  3a-migration: VarDecl/Return only; Phase 3d completed the
  remaining side-effect chain."
- Reference the new `t/bootstrap/mop/ir-completeness.t` and
  `t/bootstrap/mop/build-graph-for-loop.t` as the regression guards.

`MEMORY.md` index entry needed:

```
- [Phase 3d effect chain completion](phase_3d_effect_chain.md) —
  bare side-effect statements + If/Loop/TryCatch now thread control;
  ir-completeness.t covers 56-snippet corpus
```

**Effort:** small (one commit; doc-only).

---

### Finding 2.2 — Phase 3b/3c silent ship: DRIFT (pre-existing)

The Phase 3-4 audit established that Phase 3b/3c shipped silently
between 2026-05-20 (Phase 3a-migration) and 2026-05-22 without an
entry in the master plan's Current State or `MEMORY.md`. Phase 3d
piggybacks on the assumption that 3b/3c are working. They are. But
this was not the audit's discovery, and the recommended remediation
is documentation, not code.

**Verdict: DRIFT (pre-existing).** Out of scope for Phase 3d/3e
audit; carried forward from the 2026-05-22 Phase 3-4 audit.

---

## Concern 3 — Implementation smell check

### Finding 3.1 — `Node->control_in` reader: SMELL

**Writers in `lib/`:** `Node.pm:80` (the setter — production code:
none calls it directly except the Block fixup pass via subclass
dispatch), `Actions.pm:1566, 1580` (Block fixup).

**Readers in `lib/`:** `Actions.pm:1564, 1565` (the Block fixup pass
itself, checking whether to advance).

**Readers in `t/` and `script/`:** `ir-completeness.t:94-95`,
`build-graph-for-loop.t:48-49`, `probe-ir.pl:126-127`.

**Verdict: SMELL.** `Node->control_in` is a write-only field from
the perspective of any code outside the Block fixup pass and its own
test walkers. Codegen does not consume it. Optimizer passes do not
consume it. If a future pass walks the graph via inputs alone and
ignores `control_in`, it will not see the effect chain for
side-effect data nodes.

**Suggested remediation shape:**

Two options:

- **(a)** Leave it as-is. Phase 3d's design rationale
  (`phase-3d-effect-chain-completion.md:131-178`) was specifically to
  avoid the larger shape change of prefixing `inputs` with a control
  slot. The trade-off is that `control_in` is now a parallel edge
  that not all walkers will follow. Document this trade-off
  explicitly in `sea-of-nodes-ir.md`.
- **(b)** Make optimizer passes and codegen actually consume
  `control_in` — turn it from a write-only field into a load-bearing
  edge. The scheduler eventually needs to. Doing this now (before
  the scheduler exists) is premature.

(a) is the right answer for now. The doc update for `sea-of-nodes-ir.md`
should add a section "Statement-position effect chain":

> Side-effect data nodes (`Call`, `Assign`, `CompoundAssign`,
> `RegexSubst`) carry their effect-chain predecessor via the
> `control_in` field on `Chalk::IR::Node`, set late-binding by the
> `Block` action's control-chain fixup pass
> (`Chalk/Bootstrap/Perl/Actions.pm`). The field is not part of
> `inputs` and is excluded from `content_hash`. A graph walker that
> needs to see the full effect chain must follow both `inputs` and
> `control_in`. The scheduler (planned) will consume this edge to
> derive source-order emit positions.

**Effort:** trivial (doc-only).

---

### Finding 3.2 — `If->region`, `Loop->region` reader: SMELL

**Writers in `lib/`:** `Actions.pm:2353, 2391, 2535, 2619, 2727, 2870,
3003` (seven call sites: PostfixModifier ×2, IfStatement, ElsifChain,
WhileStatement, ForStatement, ForeachStatement).

**Readers in `lib/`:** `Actions.pm:1582` only. **Codegen reads
`Phi->region`, never `If->region` or `Loop->region`.**

**Verdict: SMELL.** The accessors exist solely to round-trip the
post-construct merge point from the constructing action back to the
Block fixup pass that walks past it. They are not consumed anywhere
else.

This is acceptable as a localized state-passing convention if it's
documented. It would be cleaner as an annotation on the Context (the
same way `if_node`, `true_proj`, etc. are stashed), but the existing
annotation-based path in the IfStatement / WhileStatement / etc.
actions already does this (`Actions.pm:2546-2552, 2748-2753`, etc.).
Adding a parallel mechanism (the `region` field on the node) for the
same data is duplication.

**Suggested remediation shape:**

Two options:

- **(a)** Keep the `region` field. Document its purpose as "stored
  by the constructing action, consumed only by the Block fixup pass."
  Note in `sea-of-nodes-ir.md` that the field is not a public part
  of the IR contract.
- **(b)** Drop the `If->region` and `Loop->region` fields. Read the
  region from the annotation stash via `$ctx->cfg_state` (already
  populated by the constructing action). This removes the
  duplicate state.

(b) is the cleaner answer; the annotation already carries the
region. The cost is rewriting the Block fixup pass at
`Actions.pm:1582` to look up the region by walking back from the If
to its annotation context, which is more work than reading
`$s->region`. Worth doing only if the duplication accumulates
elsewhere.

**Effort:** (a) trivial. (b) small (one-pass refactor + tests).

---

### Finding 3.3 — `for_init` annotation: SMELL (dead code)

**Writers in `lib/`:** `Actions.pm:2895` (ForStatement annotations).

**Readers anywhere:** None. Grep verified.

**Verdict: SMELL.** `for_init` is set but never read. The init is
already propagated to the Block fixup pass via the `[init, loop]`
arrayref return value (`Actions.pm:2898-2904`), which is the actual
mechanism.

**Suggested remediation shape:** Delete the `for_init => $init,`
line in `Actions.pm:2895`. No callers, no tests reference it.

**Effort:** trivial (1-line delete).

---

### Finding 3.4 — `PostfixModifier` does not merge its CFG nodes: SMELL

**Construction sites:** `Actions.pm:2340-2363` (loop form),
`Actions.pm:2365-2402` (if form). Both build `If`/`Loop`/`Proj`/`Region`
nodes via `$factory->make(...)`.

**Merge sites:** **None.** Compare to `IfStatement`
(`Actions.pm:2528-2542`) which calls `$graph->merge($if_node);
$graph->merge($true_proj); $graph->merge($false_proj);
$graph->merge($region);` — five merges. PostfixModifier has zero.

**Why it works today:**

The Block fixup pass at `Actions.pm:1569-1583` handles `If|Loop` by
calling `set_control_in` only (no merge). The constructed
If/Loop/Proj/Region appear in `Graph::nodes()` because:

- `Return.inputs[0]` is set to `Region` via the postfix action's
  `with_control($region)` call (line 2354 / 2392).
- The Block fixup pass merges Return into the graph (line 1545).
- `Graph::nodes()` walks Return's inputs unconditionally (input
  closure: `sea-of-nodes-ir.md:240`), discovering Region → Projs →
  If → Loop transitively.

**Verdict: SMELL.** PostfixModifier's omission of `$graph->merge`
is silently rescued by `Graph::nodes()`'s input-closure traversal.
The CFG nodes are NOT in `$graph->%cache` — they only show up in
the `nodes()` output because they're transitive inputs of a cached
node (Return).

If a future change tightens `Graph::nodes()` to return only
cache members (or if the cache is queried directly, e.g. by a
serialization/iteration pass), the postfix If/Loop/Proj/Region
vanish.

Probe `/tmp/probe-postfix-cache.pl` confirms: D4 (postfix if)
produces an `If` node in `body[1]`, reachable from `Graph::nodes()`,
but the `If` is not in cache as a root.

**Suggested remediation shape:**

Add `$graph->merge($if_node); $graph->merge($true_proj);
$graph->merge($false_proj); $graph->merge($region);` to both
PostfixModifier branches (loop and if). Match IfStatement /
WhileStatement / ForeachStatement / ForStatement style. Also call
`$sa->update_graph($graph)` if the pass currently relies on the
default-from-undef `$graph` allocation.

For PostfixModifier loop form, also merge the `Loop` node. (Currently
the loop form constructs Loop/If/body_proj/exit_proj/Region — five
nodes — none merged.)

This is one focused commit, ~10 lines of code. Tests that pass today
will continue to pass; the change moves the postfix CFG into the
graph cache where consumers expect it.

**Effort:** trivial (≤ 1 commit).

---

### Finding 3.5 — `Chalk::MOP::Method.{make,make_cfg,merge}` delegators: SMELL (pre-existing)

**Definitions:** `MOP/Method.pm:25-28`, `MOP/Sub.pm:23-26`.

**Callers in `lib/`:** None.

**Verdict: SMELL (pre-existing).** Dead code. Phase 3d/3e didn't add
them, but the doc claims they make per-method ownership ergonomic
(`mop.md:108-118`). They make nothing ergonomic; they're unused.

**Suggested remediation shape:**

Two options:

- **(a)** Delete the delegators. Update `mop.md:108-118` to remove
  the claim. Tied to Finding 1.1 — if per-method ownership is going
  to remain a doc claim only, the delegators that claim to support
  it should be removed to reduce false promises.
- **(b)** Make production code use them (Finding 1.1 option (b)).

**Effort:** (a) trivial. (b) its own phase.

---

## Concern 4 — Phase 4 codegen contract

### Finding 4.1 — Codegen does not consume `control_in` or `If->region`: ALIGNED (with caveat)

**Claim:** The Phase 4 contract is "codegen reads MOP, no parser
backchannel" (`2026-04-21-chalk-mop-migration-plan.md:1333-1400`).
Implicitly, codegen consumes nodes through their documented
interface.

**Implementation:**

- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:1141`,
  `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:1164` — these read
  `Phi->region` (existing, pre-Phase-3d).
- No site in `lib/Chalk/Bootstrap/Perl/Target/` reads `control_in`,
  `If->region`, `Loop->region`, or `for_init`.

**Verdict: ALIGNED.** Codegen walks body arrayrefs (the
`MethodInfo->body` arrayref or its `MOP::Method->body` equivalent)
plus the `cfg_state` annotation stash (populated by IfStatement /
WhileStatement / etc.). Phase 3d/3e did not extend codegen.

**Caveat:** Phase 4's exit criterion *"No `->body()` readers remain
in `lib/`"* is NOT met (per the Phase 3-4 audit:
`phase-3-4-audit.md:73-90`). 18 reader sites remain. Phase 3d/3e did
not move codegen off `body`. The codegen path is unchanged from
pre-Phase-3d.

This means: **the new IR completeness that Phase 3d/3e delivered is
not actually exercised by codegen.** Codegen still walks `body`. The
graph completeness is verified by `ir-completeness.t` but not by
codegen output.

**Suggested remediation shape:**

This is the work Phase 4 was supposed to finish. The Phase 3-4 audit
named it as the "real next step." Outside Phase 3d/3e scope. Track
as Phase 4-finish (or per the audit's recommendation, Phase 9).

**Effort:** medium-to-large (medium per the audit's optimistic read;
large if codegen edge cases compound).

---

### Finding 4.2 — `If->control_in` returns undef despite If having control: SMELL

The base `Node::control_in` reader returns the `$control_in` field
(initialized to undef). The base `set_control_in` setter mutates
`$control_in`. The If/Loop subclasses override `set_control_in` to
mutate `inputs->[0]` instead. They do NOT override `control_in`
reader. So `If->control_in` always returns `undef`, even though
`If->inputs->[0]` carries control.

**Verdict: SMELL.**

Probe (mental, not run): a future walker that reads
`if_node->control_in` to find the If's control input gets `undef`
and concludes the If is not on a chain. The actual control input is
at `if_node->inputs->[0]`. Two parallel mechanisms to read the same
edge; only one of them returns the right answer per node type.

**Suggested remediation shape:**

Two options:

- **(a)** Override the `control_in` reader on If/Loop to return
  `inputs->[0]`. The reader becomes consistent: every caller of
  `$node->control_in` gets the control input regardless of node
  type. Add ~3 lines to `If.pm` and `Loop.pm`.
- **(b)** Document explicitly that `control_in` is for side-effect
  data nodes only; CFG nodes (If, Loop) keep control in
  `inputs->[0]` and a walker must check both fields. The probe and
  the new tests do this; if all future walkers also do it, this
  works.

(a) is the principled answer. (b) preserves current behavior
exactly.

**Effort:** trivial.

---

### Finding 4.3 — `MOP::Method->body` now carries new shapes: ALIGNED

Pre-Phase-3d body contents:
- `VarDecl`, `Return`, `Unwind` IR nodes
- `Constant` for fall-through final expressions
- Metadata structs (`SubInfo`, `FieldInfo`, ...)

Post-Phase-3d additions:
- `Call`, `Assign`, `CompoundAssign`, `RegexSubst`, `TryCatch` IR
  nodes (statement position)
- `If`, `Loop` IR nodes (statement position)
- For Phase 3e: `[init, loop]` arrayref flattened — but
  `StatementList` flattens this so body sees `[VarDecl, Loop]` not
  `[[VarDecl, Loop]]`.

**Codegen handling:**

- `Target/Perl.pm:282`: dispatches on `cfg_state` annotation
  presence; if `state->{if_node}` or `state->{loop}` or
  `state->{try_node}` defined, calls the respective emit method.
  This works for the new If/Loop body items because the constructing
  actions stash the annotation via `$sa->update_annotations(...)`.
- For bare `Call`/`Assign`/`CompoundAssign`/`RegexSubst` body items
  (newly added by Phase 3d): codegen handles these via the generic
  per-node emit path (they were always handled when they appeared as
  inner subexpressions; what's new is appearing as statement-position
  body items). Codegen emits them with a trailing `;`.

**Verdict: ALIGNED.** Codegen already handled these node types as
expression-position outputs. Phase 3d's contribution is making them
appear in `body` and the graph at statement position. Codegen's body
walker doesn't care whether the node was in body before; it dispatches
on node type. Byte-compat tests pass (19/19).

**Caveat:** byte-compat doesn't test bare-Call-as-statement bodies
strongly. The goldens are 16 small library files (5-105 lines each)
with limited control-flow (only `Class`, `Symbol`, `Rule` use `if`,
none use bare side-effect statements like `print`/`die`). So
byte-compat passing is not a strong correctness oracle for Phase 3d
changes.

For the new bodies that Phase 3d enables (D1, B1, etc.), there is no
end-to-end "round-trip the snippet through codegen and check output"
test. Coverage is structural (ir-completeness.t) not behavioral.

**Suggested remediation shape:** Extend
`t/bootstrap/mop/codegen-byte-compat.t` or add a new test that
round-trips the audit corpus snippets through codegen and validates
the emitted Perl. This is small but non-trivial: the corpus snippets
need to be carefully picked so the generated code is meaningful
(some snippets are not full-program in the sense codegen expects).

**Effort:** small.

---

## Concern 5 — Test coverage honesty

### Finding 5.1 — `ir-completeness.t` cannot detect dropped statements

The audit warned that `ir-completeness.t` only checks that every
body item is in graph and reachable. It cannot detect that a
*source-level statement* never produced an IR body item in the first
place (the prior M25 stub bug: `for (init; cond; incr) BODY` produced
body `[VarDecl, VarDecl, Return]` — no Loop, no body — yet
ir-completeness.t passed M25).

Phase 3e fixed M25 by implementing ForStatement. But the audit
recommended I sweep the corpus for similar drop-the-body bugs in
"passing" snippets.

**Method:**

I ran `script/probe-ir.pl t/fixtures/ir-audit-corpus.pl > /tmp/probe-out.txt`
and inspected each snippet's body count and graph contents. For each
snippet I cross-referenced what statements appear in the source.

**Result:**

Only the documented WARN cases (I3 SubInfo, M7 iterator-less foreach)
show body items not in graph. For every other snippet, the body item
count matches the expected number of statement-position constructs in
the source.

**Probe details (sampling, not exhaustive):**

- **D8 (try/catch):** body=2 (`TryCatch`, `Return`). Source: `try {
  die "boom"; } catch ($e) { return 0; } return 1;` — the outer
  TryCatch wraps the inner body items; the trailing `return 1` is the
  second body item. The inner `die`, `return 0` are inside TryCatch's
  inputs[0] / inputs[2] arrays. Body count is correct.
- **D7 (nested if):** body=3 (`VarDecl`, `If`, `Return`). Source has
  outer if/else with inner if/else inside the `if ($n > 0)` branch.
  The inner `If` is reachable through outer `If`'s `Proj`. Body
  count is correct.
- **M16 (block unless):** body=2 (`If`, `Return`). Source: `unless
  ($n) { return 0; } return 1;`. The inner `return 0` is inside
  If's true-branch. Body count is correct.
- **M17 (bare next):** body=2 (`Loop`, `Return`). Source has
  `foreach my $n (...) { next if $n == 2; }` then `return 1`. The
  `next` lives inside the loop's body annotation, not as a body item.
- **M20 (do block):** body=2 (`VarDecl`, `Return`). Source: `my $r =
  do { my $x = 1; $x + 2 }; return $r;`. The do-block body is inside
  VarDecl's init (a do-block / AnonSub expression). Body count is
  correct.
- **M21 (eval block):** same pattern as M20. Body=2.
- **M22 (sort with block):** body=2. The sort block is inside the
  VarDecl initializer.

**Verdict: NO PROBE-DISCOVERED BUGS.** Every snippet's body item
count matches the source's statement-position construct count, with
the documented exceptions of I3 (SubInfo by design) and M7 (TODO).

This does NOT prove the IR semantically encodes the snippets
correctly. It only proves no statements are dropped. The audit's
caveat (`ir-completeness-audit.md:291-307`) stands: structural
presence + reachability is not semantic correctness.

---

### Finding 5.2 — Tests use the same factory as production: ALIGNED

The new tests (`ir-completeness.t`, `build-graph-for-loop.t`) and the
probe (`probe-ir.pl`) all parse via `TestPipeline::build_perl_ir_parser`,
which sets up the same Actions / SemanticAction / FilterComposite
pipeline as production. They are testing the actual code paths, not
a stub.

**Verdict: ALIGNED.**

---

## Cross-references

### Plans this audit informs

- `docs/plans/2026-04-21-chalk-mop-migration-plan.md` — Current State
  section needs Finding 2.1 update.
- `docs/plans/2026-05-22-phase-3-4-audit.md` — its recommended
  remediation ("Finish Phase 3a-migration's actual scope") was
  delivered as Phase 3d. The audit's recommendation #4 ("Once
  `_body_from_graph` recovers full source-ordered bodies for the
  green-eval file set, replace the 18 `->body()` reader sites with
  graph walks") remains the actual blocker for Phase 4 completion.
- `docs/plans/2026-05-22-ir-completeness-audit.md` — the audit it
  closed. No further follow-up needed beyond what this audit names.
- `docs/plans/2026-05-22-corpus-alignment-audit.md` — M7 (iterator-less
  foreach) remains as a tracked TODO and is the only ir-completeness.t
  failure.

### Architecture docs that need updates

- `docs/architecture/mop.md` — Finding 1.1 (per-method ownership
  claim) and Finding 3.5 (dead delegators).
- `docs/architecture/sea-of-nodes-ir.md` — Finding 1.3 (immutability
  exemption for If::set_control_in / set_region) and Finding 3.1
  (control_in edge documentation).
- `docs/architecture/context-comonad.md` — unchanged by Phase 3d/3e.

### MEMORY.md updates needed

- Add: `phase_3d_effect_chain.md` (Phase 3d landed 2026-05-22; ir-
  completeness.t is the regression guard).
- Downgrade: "Phase 3a-migration COMPLETE 2026-05-20" to reflect that
  Phase 3d retroactively closed unfinished scope.
- Add: M7 iterator-less foreach is a tracked corpus TODO; the
  ForeachStatement action's iterator handling is the gap.

---

## Recommended remediation

Ordered by leverage. All effort estimates assume one developer.

| # | Finding | Effort | Rationale |
|---|---------|--------|-----------|
| 1 | Update master plan Current State (Finding 2.1) | trivial | Plan-discipline. One commit, doc-only. |
| 2 | Update `MEMORY.md` with Phase 3d/3e entry (Finding 2.1) | trivial | Same commit. |
| 3 | Delete `for_init` annotation (Finding 3.3) | trivial | 1-line delete; no callers. |
| 4 | Merge PostfixModifier's CFG nodes into graph (Finding 3.4) | trivial | ≤10 lines; match IfStatement style. Reduces fragility of `Graph::nodes()` input-closure dependency. |
| 5 | Override `control_in` reader on If/Loop (Finding 4.2) | trivial | ~6 lines. Removes "looks like undef but isn't" footgun. |
| 6 | Update `mop.md` to reflect per-parse (not per-method) factory ownership (Finding 1.1) | small | Doc + delete dead delegators in MOP::Method/Sub. |
| 7 | Update `sea-of-nodes-ir.md` for control_in edge documentation (Findings 3.1, 1.3) | trivial | One section addition. |
| 8 | Round-trip codegen test for audit corpus (Finding 4.3 caveat) | small | New test file in t/bootstrap/mop/. |
| 9 | Drop `If->region` / `Loop->region` accessors in favor of annotation lookup (Finding 3.2) | small | Refactor Block fixup pass. Optional. |
| 10 | Finish Phase 4 (codegen reads MOP) — 18 `->body()` reader sites (Finding 4.1) | medium-to-large | Out of Phase 3d/3e scope; tracked in 2026-05-22-phase-3-4-audit.md. |
| 11 | Implement true per-method factory ownership (Finding 1.1 option b) | large | Its own phase; intrusive. Defer until profile shows hash-cons collisions matter. |

**Highest-leverage triage:** items 1–7 are 1–2 commits each, all
trivial-to-small. Doing them in a single "cleanup" session clears
all the SMELL findings and brings docs back in sync with the code,
without touching the scheduler design.

Items 8–9 are nice-to-have. Items 10–11 are their own phases.

---

## Acceptance criteria verification

The brief named five concerns. Verifying each:

**Concern 1: Architecture doc claims — met.** Findings 1.1 (DRIFT),
1.2 (ALIGNED with subtlety), 1.3 (ALIGNED with undocumented
exemptions), 1.4 (ALIGNED).

**Concern 2: Master plan alignment — met.** Findings 2.1 (DRIFT;
remediation named), 2.2 (DRIFT pre-existing; out of scope).

**Concern 3: Implementation smell check — met.** Findings 3.1
(SMELL), 3.2 (SMELL), 3.3 (SMELL — dead code), 3.4 (SMELL — missing
merge), 3.5 (SMELL — dead delegators pre-existing).

**Concern 4: Phase 4 codegen contract — met.** Findings 4.1
(ALIGNED with caveat — Phase 4 not actually complete), 4.2 (SMELL),
4.3 (ALIGNED with caveat — byte-compat coverage thin for new
shapes).

**Concern 5: Test coverage honesty — met.** Finding 5.1 (no
probe-discovered drop bugs), 5.2 (ALIGNED).

All five concerns audited. The brief's structure is reflected in
sections "Concern 1" through "Concern 5" above. The brief's request
for a final executive verdict is at the top: DRIFT WITH KNOWN GAPS.

The brief's "be honest" requirement: Phase 3d/3e accomplished its
stated goal (ir-completeness.t passes). The architecture drift
findings are not Phase 3d's fault — Phase 3d landed against an
already-drifted spec — but they are *exposed* by Phase 3d because the
new fields are advertised in code where the spec is silent. The
right next step is plan-and-doc remediation, not unwinding Phase
3d/3e.
