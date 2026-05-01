# Phase 3a-migration scope reframe under HEAD

**Date:** 2026-05-01
**Branch:** `g4-phase-3a-migration-reframe`
**Author:** perigrin (via read-only audit)
**Purpose:** reframe Phase 3a-migration scope under current HEAD; narrow
reading per perigrin's 2026-05-01 decision (codegen `cfg_state`
retirement defers to Phase 4).

This addendum supplements
`docs/plans/2026-04-21-chalk-mop-migration-plan.md` (the MOP migration
plan, §"Phase 3a-migration: Bottom-up graph construction", lines
1063-1161) and
`docs/plans/2026-04-25-audit-3-mop-ir-findings.md` (Audit 3, which
named the prior 3a-migration framing).

It does NOT amend the plans in place. It records that the prior plan
text and the prior audit text are partially stale, identifies which
parts of the original 3a-migration scope have already moved out from
under it, and proposes a narrower entry point that matches the code
state under HEAD.

## TL;DR

Audit 3 named the migration target as "the ~50 `update_cfg`/`cfg_state`
callers in `Actions.pm`". Under HEAD, that surface is gone:
`Actions.pm` has zero executable callers of any of those three
methods. The remaining callers all live in **codegen** (`Target/Perl.pm`
and `Target/EmitHelpers.pm`).

Under perigrin's 2026-05-01 narrow reading:

- **Phase 3a-migration is just bottom-up graph construction.** Its
  remaining work is migrating computation actions in `Actions.pm`
  (`VariableDeclaration`, `Assign`, `Call`, etc.) from singleton
  `$factory`/`$typed` construction to `$ctx->graph->merge(...)`,
  threading control through `$ctx->scope->control`, and ultimately
  deleting `_build_method_graph`.
- **Codegen `cfg_state` shim retirement defers to Phase 4** ("codegen
  reads MOP"). The four shim callers in `Target/Perl.pm` and
  `Target/EmitHelpers.pm` are codegen sites, not parse-time sites, and
  they retire alongside the broader codegen migration to graph-walk.
- The `cfg_state()` read-only shim in `SemanticAction.pm` survives
  through Phase 3a-migration AND Phase 3b/3c — it can only be deleted
  once the four codegen callers stop calling it.

## Verification findings under HEAD

I re-probed each of the framing claims directly. Citations are
file:line under HEAD (`worktree-pu`, tip `2a6230ff`).

### Finding 1 — `Actions.pm` caller count (Audit 3's named target)

Audit 3 (`docs/plans/2026-04-25-audit-3-mop-ir-findings.md:205`) names
"the ~50 `update_cfg`/`cfg_state`/`inherited_cfg_state` callers in
`Actions.pm`" as the migration boundary.

Under HEAD, `lib/Chalk/Bootstrap/Perl/Actions.pm` contains exactly
**three** mentions of those identifiers, and **all three are
comments**, not executable calls:

- `lib/Chalk/Bootstrap/Perl/Actions.pm:728` — "No `cfg_state` is
  available here (fixup runs post-parse), so a fresh Start node serves
  as the control token." (inside `_fixup_stmts`'s return-merge branch)
- `lib/Chalk/Bootstrap/Perl/Actions.pm:747` — same comment for the
  die→Unwind fixup branch.
- `lib/Chalk/Bootstrap/Perl/Actions.pm:1112` — historical narrative
  describing what `ExpressionStatement` does for postfix-modifier
  alts: "wires the expression into the `PostfixModifier`'s `cfg_state`
  body_stmts so codegen emits the body inside the control flow
  construct."

Zero executable calls remain. The Audit 3 framing ("~50 callers in
Actions.pm") was correct at the time it was written but is now stale —
3a-infra's mechanical sweep already retired them. The remaining
references in `Actions.pm` are descriptive comments about the
post-parse fixup pipeline; they do not block 3a-migration.

### Finding 2 — All `cfg_state` callers across `lib/`

Searching `lib/` for any reference (executable or comment) to the
three identifiers (`cfg_state`, `inherited_cfg_state`, `update_cfg`):

**Defines / declares:**
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:362` — `method
  cfg_state($ctx)` declaration. Read-only shim (see Finding 3).

**Executable callers of `$sa->cfg_state(...)`:**
- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:94` —
  `_build_cfg_lookup`'s walk loop, building a per-IR-node lookup
  table at codegen time.
- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:1020` —
  `emit_from_cfg_state($sa, $ctx)`, dispatching to `emit_cfg_if` /
  `emit_cfg_loop` / try-catch emission.
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:183` —
  `_build_cfg_lookup`'s walk loop, with optional `$cfg_snapshot`
  pre-built at parse time. Falls back to live `$sa->cfg_state(...)`
  when no snapshot is provided.
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:1365` —
  `emit_from_cfg_state($declared_vars)`'s entry call.

That is the **complete** executable surface: four call sites, all in
codegen targets.

**Comments only:**
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm:37` — historical comment
  explaining why the schedule maps by node identity.
- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:41,69-71,86-100,202,877,
  879,1015,1023,1034,1047,1059` — comments describing the codegen
  flow's interaction with the lookup table.
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:36,45-46,172-175,
  1361,1368,1380,1409` — same.
- `lib/Chalk/Bootstrap/Perl/Target/C.pm:1474` — comment noting that
  `$sa` and `$ctx` are stored for emission methods that need
  `cfg_state`.
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:67,353-360` —
  preamble describing the shim's purpose and structural-key
  enumeration.
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:104,327` —
  historical comments about control/scope info and the stale-value
  merge problem.
- `lib/Chalk/Bootstrap/Perl/Actions.pm:728,747,1112` — the three
  Actions comments enumerated in Finding 1.

`update_cfg`, `inherited_cfg_state`, and `_pending_cfg_update` are
all gone from the executable surface — they were deleted by 3a-infra
(commit `885beb87` per
`docs/plans/2026-05-01-session-handoff.md:34`).

### Finding 3 — SA `cfg_state` shim is read-only and codegen-facing

`lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:353-417` declares the
shim. The preamble at `:353-360` self-describes as:

> Read-only compatibility shim: assemble a `cfg_state` hashref from
> the new first-class fields. Returns a hashref with:
>   `control`  => `$scope->control()`  (from scope field)
>   `scope`    => `$scope`             (the scope object itself)
>   + any structural keys from annotations (if_node, loop, try_node, ...)

The implementation at `:362-417` walks the Context tree iteratively,
collecting:
1. The first non-Start scope it finds (`:386-397` — outermost wins;
   ties broken by "more-advanced control").
2. Structural annotations from any node in the tree (`:399-403` —
   keys: `if_node`, `loop`, `try_node`, `then_stmts`, `else_stmts`,
   `body_stmts`, `statements`, `loop_if`, `body_proj`, `exit_proj`,
   `true_proj`, `false_proj`, `loop_jump`, `iterator`, `list`,
   `catch_var`, `try_stmts`, `catch_stmts`).

Returns a hashref `{control, scope, ...structural_keys}`, or `undef`
if no scope is found (`:408`).

It is purely read-only: no mutation of the Context tree, no scope
update, no graph merge. It is a **view function** over the
graph/scope/annotation triple that 3a-infra already promoted to
first-class.

**Conclusion:** under the narrow reading, this shim cannot be
deleted by 3a-migration. Its four codegen consumers (Finding 2)
must migrate first. Deletion belongs to Phase 4.

### Finding 4 — Phase 3a-infra exit state confirmed

`lib/Chalk/Bootstrap/Context.pm:17-18`:

```
field $graph       :param :reader = undef;
field $scope       :param :reader = undef;
```

`extend()` propagates them at `:40-41` (with `%opts` overrides).
`SemanticAction.pm`'s `multiply()` (entry at `:183`) does scope
propagation via `_mul_ctx` at `:97-113` (`scope => _merge_scope(...)`,
no graph field set on the multiply-result Context — graph propagation
flows via `extend()` and via `_complete_sa` rebuilds at `:244,274`
which explicitly carry `graph => $result_ctx->graph()`).

Note: the prompt asked about a `with()` method. Context.pm does
**not** have a `with()` method; field updates flow through `extend()`
with `%opts` overrides. The propagation behavior the prompt was
asking about is correctly in place via `extend()` and via
SemanticAction's `_complete_sa` rebuilding Contexts with `graph =>
$result_ctx->graph()` and explicit `scope => ...` arguments.

Note also: `_mul_ctx` does **not** carry `graph` forward at the
multiply level. This is a likely 3a-migration concern: when
`_mul_ctx` joins two child Contexts that each carry a graph (e.g.
adjacent statements in a Block), the multiply-result Context has
`graph => undef`. 3a-migration's `Block` synthesis step will need to
either (a) reach into children to harvest graphs, (b) extend
`_mul_ctx` to merge graphs, or (c) require that statements thread
their graph through `extend()` rather than relying on multiply.
Option (c) appears most consistent with the bottom-up plan.

`update_cfg`, `inherited_cfg_state`, `_pending_cfg_update`, and the
`annotations->{cfg}` side-channel are all deleted from the executable
surface, matching 3a-infra's exit criteria
(`2026-04-21-chalk-mop-migration-plan.md:1053-1059`).

3a-infra is complete.

### Finding 5 — `_build_method_graph` is unchanged from Audit 3

`lib/Chalk/Bootstrap/Perl/Actions.pm:1561-1639`. Behavior matches
Audit 3's description verbatim:

- `:1564-1582` — walks Context subtree collecting annotation entries
  for `if_node` / `loop` / `try_node`, building a `%schedule` keyed
  by IR refaddr.
- `:1586` — `my $start = _ctx_control($ctx) // $factory->make('Start');`
  (now reads `$ctx->scope->control()` directly, not the deleted
  `inherited_cfg_state`).
- `:1588-1595` — collects existing `Return` / `Unwind` from
  `$fixed_body` as exits.
- `:1597-1609` — synthesizes implicit `Return` on fall-through when no
  explicit Return/Unwind exists in `$fixed_body`.
- `:1611-1631` — seeds `body_stmts` from the body and from the
  schedule's `then_stmts` / `else_stmts` / `statements` / `body_stmts`
  keys.
- `:1633-1638` — returns
  `Chalk::IR::Graph->new(start, returns, schedule, body_stmts)`.

This is still "Return-collector + body_stmts seeder" exactly as
Audit 3 named it (`docs/plans/2026-04-25-audit-3-mop-ir-findings.md:30`)
and as the CLAUDE.md Plan Discipline section (lines 198-211) calls
out. No new SoN construction, no Phi insertion. The mechanical change
since Audit 3 is the swap from `inherited_cfg_state` to
`$ctx->scope->control()` at `:1586` — i.e., 3a-infra's mechanical
migration but no semantic change.

### Finding 6 — Computation-action prerequisites: status of `VariableDeclaration`, `Assign`, `Call`

The MOP plan
(`docs/plans/2026-04-21-chalk-mop-migration-plan.md:1076-1097`) names
these three as the first migration targets and says each should:

> reads `$ctx->scope` for variable resolution, constructs its typed
> node, **merges it into `$ctx->graph`**, and extends the Context with
> the updated graph and scope.

Status under HEAD:

- **`VariableDeclaration`** (`Actions.pm:2105-2160`) reads scope at
  `:2152` (`my $scope = _ctx_scope($ctx)`), constructs a typed
  `VarDecl` node at `:2144-2147` via `$typed->make('VarDecl', ...,
  compat_class => 'VarDecl')`, updates scope at `:2154-2155`
  (`$scope->define(...)`, then `$sa->update_scope($new_scope)`), and
  returns the bare `$var_decl` IR node as focus.
  - **Does NOT** call `$ctx->graph->merge(...)`.
  - **Does NOT** thread control input through scope.
- **`AssignmentExpression`** (`Actions.pm:2584+`) — referenced at
  `:2615` reading scope; same pattern, uses `$factory`/`$typed`
  singletons.
- **`CallExpression`** (`Actions.pm:1828+`) — same pattern, uses
  singletons.

There are zero `$ctx->graph->merge(...)` call sites in
`lib/Chalk/Bootstrap/Perl/Actions.pm`. (Verified by searching for
`graph->merge` and `ctx->graph` across `lib/`; only matches outside
`Actions.pm` are in `MOP/Method.pm`, `MOP/Sub.pm`, `MOP/Phaser.pm`
delegators and `SemanticAction.pm`'s extend-time graph propagation.)

The migration to bottom-up graph construction has not started in any
action.

`lib/Chalk/IR/Graph.pm:50-58` provides the target API:
`$graph->merge($node)` — hash-conses `$node` into the graph by
`content_hash`, returns the existing or freshly-merged node.

## Reframed Phase 3a-migration scope (narrow)

Under perigrin's 2026-05-01 narrow reading:

### What 3a-migration DOES include

1. Migrate computation actions in `Actions.pm` (`VariableDeclaration`,
   `AssignmentExpression`, `CallExpression`, and other side-effect
   actions) to:
   - Read scope via `$ctx->scope` (already in place via `_ctx_scope`).
   - Construct typed nodes via the existing `$typed`/`$factory`
     singletons (no MOP migration in this phase).
   - **Merge each constructed node into `$ctx->graph` via
     `$graph->merge($node)`.**
   - Thread linear control: each side-effect node's control input is
     `$ctx->scope->control()`; after construction, update the scope
     with `$scope->with_control($new_node)` so the next side-effect
     statement chains correctly.
2. Migrate `Block` to synthesize `{graph, type}` per
   `2026-04-21-chalk-mop-migration-plan.md:1100-1105`.
3. Migrate `MethodDefinition` / `SubroutineDefinition` to read
   `{graph, type}` from their body Block child's Context, attach the
   graph to the MOP metaobject, and synthesize implicit Return on
   fall-through.
4. **Delete `_build_method_graph`** from `Actions.pm:1561-1639`.

The result: linear-code graphs are fully reachable from `start`
through inputs alone, and the post-hoc body_stmts seeding goes away.

### What 3a-migration does NOT include (deferred to Phase 4)

5. **The four codegen callers of `$sa->cfg_state(...)` are NOT
   retired in 3a-migration.** They retire in Phase 4 ("codegen reads
   MOP, migrates `body()` callers"). Specifically:
   - `Target/Perl.pm:94` and `:1020`
   - `Target/EmitHelpers.pm:183` and `:1365`
6. The `cfg_state()` read-only shim at `SemanticAction.pm:362` is NOT
   deleted in 3a-migration. It survives until those four codegen
   callers retire.
7. The 18 codegen reader sites of `->body()` (CLAUDE.md, Plan
   Discipline, Phase 4 territory) are NOT touched.
8. Phi insertion (3b) and loop Phi (3c) are explicitly excluded by the
   plan and remain so.

### Why this narrowing makes sense under HEAD

The original Audit 3 framing assumed that retiring `cfg_state` callers
in `Actions.pm` was a precondition for 3a-migration. Under HEAD that
work is **already done** (Finding 1) — 3a-infra mechanically swept it.
What remains is genuinely separate: the codegen-side consumers were
never `Actions.pm` callers in the first place. They are codegen-side
*readers* of a parse-time view function (`cfg_state` is the view).
Forcing them into 3a-migration would conflate "build the IR
correctly" (3a-migration's job) with "read the IR correctly at
codegen" (Phase 4's job).

The narrow reading also matches the plan's own stated entry/exit
criteria for 3a-migration
(`2026-04-21-chalk-mop-migration-plan.md:1143-1158`), which never
mention codegen callers or the SA shim. The plan was correct; the
audit summary that the bridge doc inherited was the source of drift.

## Updated entry/exit criteria (refinement, not rewrite)

The plan's stated criteria
(`2026-04-21-chalk-mop-migration-plan.md:1063-1161`) are still
correct. Two clarifications:

**Entry** — "Phase 3a-infra complete" remains accurate. Confirmed by
Finding 4. **No additional precondition is needed** — Audit 3's
"retire ~50 cfg_state callers in Actions.pm" was the 3a-infra exit
criterion, not a 3a-migration entry criterion, and it is satisfied.

**Exit** — the plan's six bullets at `:1143-1158` are correct. Add an
explicit non-goal:

- **Non-goal:** The four codegen callers of `$sa->cfg_state(...)` in
  `Target/Perl.pm` and `Target/EmitHelpers.pm` are NOT retired in
  this phase, and the `cfg_state()` shim in `SemanticAction.pm`
  remains in place. These retire in Phase 4.

## First concrete migration step (TDD red proposal)

**Migration target:** `VariableDeclaration` at
`lib/Chalk/Bootstrap/Perl/Actions.pm:2105-2160`.

**Why this first:**

1. **Smallest semantic surface.** `VariableDeclaration` constructs
   exactly one IR node (`VarDecl`), already reads scope, and already
   updates scope. Adding a `$graph->merge($var_decl)` and a control
   thread via `$scope->with_control(...)` is the minimum-viable
   bottom-up graph construction step.
2. **Already partially threaded.** Scope reading and updating are
   already in place at `:2152-2155`. The work is additive: thread
   graph-merge alongside existing scope-update.
3. **Clean failure mode.** A failing test on graph-reachability is
   easy to write (assert that the synthesized `VarDecl` node appears
   in `$method->graph->nodes()` reachable from start through inputs)
   and easy to make pass without disturbing `_build_method_graph`'s
   existing body_stmts seeding. The two paths can coexist during
   migration; `_build_method_graph` deletion is the *last* step of
   3a-migration, not the first.
4. **No dependency on Block synthesis or MethodDefinition migration.**
   Those follow `VariableDeclaration` once the first action is wired.
5. **Control-input semantics are well-defined.** A `VarDecl` is a
   side-effect node; its control input is `$ctx->scope->control()`,
   and its post-execution control is itself. This is the canonical
   linear-chain primitive.

**Failing TDD test (red phase):** create
`t/bootstrap/mop/build-graph-vardecl-merge.t` that:

1. Parses a method body containing a single `my $x = 1;` statement.
2. Asserts that the resulting `Chalk::IR::Graph` (read from the
   method metaobject) contains the `VarDecl` node by walking from
   `$graph->start()` through inputs **without consulting
   `body_stmts`**. Concretely: `$graph->reachable_from_start()`
   (whatever the bidirectional walk API is — see Phase 7 in the plan)
   includes the `VarDecl`.
3. Equivalent reformulation if the bidirectional API does not yet
   exist: assert that the `VarDecl` node's control input is
   `$graph->start()` (i.e., the first side-effect statement chains to
   Start, not to `undef`), AND assert that
   `$graph->cache->{$vardecl->content_hash()}` is the same identity
   as the returned `VarDecl` (i.e., it was hash-consed via
   `$graph->merge`, not just constructed via `$typed->make`).

The current code constructs the node via the singleton `$typed`
without going through `$graph->merge`, so identity through
`$graph->cache` will mismatch — that's the red.

**Migration target file:line for the green phase:**
`lib/Chalk/Bootstrap/Perl/Actions.pm:2144-2159`. Replace the singleton
`$typed->make('VarDecl', ...)` with a `$ctx->graph->merge(...)` call,
add a `with_control($var_decl)` chain to the scope update, and ensure
the result Context exposes the updated graph and scope back to the
SA propagation path.

## Coupling with parallel tracks

### Track 1 / G1: SA-zero contract migration

**Status under HEAD:** branch `g1-sa-zero-contract` exists; the
session handoff (`docs/plans/2026-05-01-session-handoff.md:65-70`,
Decision 4) records SA-zero migration as "Not started" but planned.
Decision 4's migration ordering is "SemanticAction → TypeInference →
Precedence → Structural", so SA-zero is the first to land.

**Coupling assessment:** SA-zero's surface is
`SemanticAction.pm:116-118` (`method zero { return undef; }`) — it
returns `undef` today and Decision 4 wants it to return a Context.
3a-migration's surface is `Actions.pm` computation actions plus the
`Block` / `MethodDefinition` / `SubroutineDefinition` graph
synthesis. They share the file `SemanticAction.pm` only in that
3a-migration relies on `multiply()`'s graph propagation (`:244,274`)
already working under 3a-infra.

**Conflict risk:** low textually. SA-zero changes `zero()`'s return
type and any code that consumes `zero()`'s result (the Earley
filter-zero short-circuit in `FilterComposite.pm`); 3a-migration
changes `Actions.pm` action methods and downstream `Block` / method
synthesis. Both will touch `multiply()` in `SemanticAction.pm`
adjacent to existing graph/scope propagation, but at different code
sites.

**Sequencing recommendation:** these can land in either order. If
SA-zero lands first, 3a-migration inherits Context-typed `zero()` for
free (no behavioral change for the linear case). If 3a-migration
lands first, SA-zero will see a richer `multiply()` propagation
surface but no new dependency.

### Track 2 / G5a: oracle harness work

**Coupling:** none. G5a does not touch parser/IR/codegen.

### Track 3 / G4 successors (Phase 3b, 3c, 4, 5, 6)

3b and 3c depend on 3a-migration. Phase 4 is where the codegen
`cfg_state` callers retire. The narrow reading explicitly defers that
work to Phase 4; this is consistent with the plan's existing entry
criterion for Phase 4 (`:1170` "Phase 3a-migration complete").

## What remains for Phase 4 instead

Phase 4 ("codegen reads MOP, migrate `body()` callers") under the
narrow reading absorbs the codegen `cfg_state` retirement. The
specific call sites and shim to retire in Phase 4:

**Codegen callers of `$sa->cfg_state(...)` (4 total):**
1. `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:94` — inside
   `_build_cfg_lookup`'s walk loop. Replace with a graph-walk that
   consumes `Method::graph` directly.
2. `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:1020` — inside
   `emit_from_cfg_state($sa, $ctx)`. The whole method becomes
   "emit from graph" once the lookup table is graph-derived.
3. `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:183` — same as #1
   for the C/XS emission path.
4. `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:1365` — same as #2.

**Shim to delete in Phase 4 (after the four callers retire):**
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:353-417` — the
  `cfg_state` read-only compatibility shim. No other consumers exist
  (verified by Finding 2: zero direct test callers and zero other
  `lib/` callers).

**Phase 4 also retires (from the existing plan and CLAUDE.md):**
- The 18 `->body()` reader sites in `Actions.pm`, `EmitHelpers.pm`,
  and `StructPromotion.pm`.
- The `body` field on `MethodInfo` / `ClassInfo` / `SubInfo`
  (CLAUDE.md, Plan Discipline §3).

Once 3a-migration finishes, every method's `Chalk::IR::Graph` will
expose its full linear computation graph via `start` and inputs.
Phase 4's codegen migration will read **that** instead of the
`cfg_state` view function.

## Methodology lesson

This reframe was triggered by re-probing under HEAD before accepting
the audit's "next-task" framing. The audit was correct at the time it
was written (Apr 25), but 3a-infra (commit `885beb87`, Apr 30 per the
session handoff doc) moved the surface out from under the audit's
description. The audit named "~50 callers in `Actions.pm`"; HEAD has
zero. The bridge doc's `Three parallel tracks` section
(`2026-05-01-session-handoff.md:466-477`) inherited the older framing
unchanged.

This is the same pattern as the Phase A.2 lessons:
*"the audit names a trigger; the RCA verifies it under current HEAD.
Five or six instances in this session where trigger identification
was wrong on first pass."*
(`2026-05-01-session-handoff.md:166-169`). 3a-migration's framing is
the seventh instance.

When acting on plan/audit guidance, re-probe the named surface before
proposing scope.
