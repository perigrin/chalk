# Phase 3a-migration session-open context — 2026-05-20

Context handoff for the next session picking up Task #87
(Phase 3a-migration of the MOP migration plan). Captures the
why/what/where so a fresh session can land the first TDD commit
without re-discovering everything.

## Goal

Migrate computation actions in `lib/Chalk/Bootstrap/Perl/Actions.pm`
to build IR graphs incrementally via `$ctx->graph` and chain control
via `$ctx->scope->control`. Block synthesizes `{graph, type}`.
MethodDefinition/SubroutineDefinition read that and attach to the MOP
metaobject. Delete `_build_method_graph` (~80 lines).

End state: linear method bodies produce graphs reachable from `Start`
through `inputs()` alone, with no `body_stmts` / `schedule` side
channels needed. Branching and looping still use older logic (3b/3c
handle Phi insertion).

## What's already in place (preconditions met)

Phase 3a-infra completed in commit `9887e5d1`. Confirmed:

- `Chalk::Bootstrap::Context` has `field $graph`, `field $scope`,
  `field $mop` with `:param :reader` and propagation through
  `multiply`/`extend`.
- `Chalk::Bootstrap::Scope::with_control($node)` returns an
  immutable Scope with the control input replaced.
- The cfg_state side-channel (`update_cfg`, `set_cfg_state`,
  `inherited_cfg_state`, `_pending_cfg_update`,
  `annotations->{cfg}`) is fully deleted from `lib/`.
- `Context::cfg_state()` is the read-side accessor (walks the tree,
  returns hashref with control/scope + structural annotation keys).
  SA's `cfg_state` shim is gone.
- `Chalk::IR::Graph` exists with `merge($node)` (hash-cons) and
  `nodes()` (BFS from start/returns/body_stmts). Already used by
  `_build_method_graph` as the output container.

## What changes in 3a-migration

Three categories of change in `lib/Chalk/Bootstrap/Perl/Actions.pm`:

### 1. Computation actions (side-effect)

Each of `VariableDeclaration`, `Assign`, `Call`, etc. should:

1. Read scope from `$ctx->scope` for variable resolution
2. Construct its typed IR node
3. Get current control: `my $ctrl = $ctx->scope->control`
4. Build the node with `$ctrl` as control input
5. `$ctx->graph->merge($new_node)` to hash-cons into the graph
6. Return a Context extended with
   `scope => $scope->with_control($new_node)` plus the new IR node
   as focus

Pure-value actions (`Constant`, `BinaryExpression` with no side
effects) skip step 4-6; they just merge into the graph and return
the node as focus.

### 2. Block

Currently returns `\@stmts` (arrayref). Must change to return
`{ graph => $g, type => $t }` where:

- `$g` is the accumulated graph from constituent statements
- `$t` is the union of all exit value types — every explicit
  Return/Unwind value type, plus the implicit return (final
  expression's type) if a fall-through path exists. TI already
  computes types per-rule; Block must collect them from its
  children's TI annotations.

Block has two callers: `MethodDefinition` (Actions.pm:628) and
`SubroutineDefinition` (Actions.pm:698). Both already destructure
the body arrayref from Block's `ARRAY`-typed focus; they need to
adapt to the new shape.

### 3. MethodDefinition / SubroutineDefinition / AdjustBlock

Each should:

1. Read the Block's `{graph, type}` from its body child's Context
2. Use the block's type as the method's return type (replaces
   TI-focus reading at Actions.pm:662-674)
3. Synthesize implicit Return if fall-through path exists and graph
   has no Return — already done by `_build_method_graph:808-816`,
   move into the action directly
4. Collect Return/Unwind nodes from the entire graph as method
   exits (replace `_build_method_graph:795-802`)
5. Register VarDecl nodes from the body on the Method metaobject as
   lexical-binding metadata (new — currently no equivalent)
6. Attach the graph to the MOP metaobject (`MethodInfo` already has
   a `graph` field at line 12)
7. Return the metaobject as focus WITHOUT propagating scope or graph
   (structural boundary — method body's scope doesn't leak out)

### 4. Delete `_build_method_graph`

Lives in `lib/Chalk/Bootstrap/Perl/Actions.pm:768-846`. Once
MethodDefinition/SubroutineDefinition/AdjustBlock all use the
Block-{graph,type} pattern, this helper has no callers.

Also delete the `$schedule`/`body_stmts` collection it does — that's
the bottom-up reachability via `inputs()` is supposed to replace.

## TDD-first tests (write before any implementation)

Per the plan and per project rules (CLAUDE.md TDD discipline). Each
should fail meaningfully against the current implementation.

Path: `t/bootstrap/mop/` (directory already exists with 15 sibling
tests for MOP basics).

1. **`block-type.t`** — Block synthesizes `{graph, type}`
   - Empty block → `{graph => empty, type => 'Void'}`
   - `{ 42 }` → `{graph => ..., type => 'Int'}` (final-expr value)
   - `{ return 42 }` → `{graph => ..., type => 'Int'}` (explicit return)
   - `{ if (...) { return 1 } 'fallthrough' }` → type is union of
     both exit types

2. **`build-graph-control-chain.t`** — side-effect statements chain
   control back to Start in linear method bodies
   - `method foo() { my $x = 1; my $y = 2 }` — VarDecl(x)'s control
     is Start; VarDecl(y)'s control is VarDecl(x)

3. **`build-graph-linear-reachability.t`** — for linear bodies,
   `$method->graph->nodes()` reaches everything from `start` via
   `inputs()` alone (no `body_stmts` seed needed)

4. **`method-lexical-bindings.t`** — MethodDefinition registers
   VarDecl IR nodes on the Method metaobject as lexical-binding
   metadata accessible via the metaobject

5. **`method-implicit-return.t`** — MethodDefinition synthesizes a
   Return on fall-through, preserves explicit Returns, collects
   nested Returns from loops/branches as exits, does NOT collect
   from inner nested subs/methods

## Files to touch

Primary edits:

| File | Lines around | What changes |
|---|---|---|
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | 1275-1287 | Block returns `{graph, type}` |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | 1345+ | VariableDeclaration uses Context fields |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | (search Assign) | AssignmentExpression uses Context fields |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | 628-690 | MethodDefinition reads Block's {graph, type}, attaches to MOP |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | 698-760 | SubroutineDefinition same |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | 850+ | AdjustBlock same |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | 768-846 | DELETE `_build_method_graph` |

Tests to add: `t/bootstrap/mop/block-type.t` + 4 others.

## Strategy: do it in commits

Multi-day refactor. Order:

1. **Commit 1 (TDD setup):** All 5 test files. Verify they fail
   meaningfully against current impl. No production code change.
2. **Commit 2 (Block synthesis):** Block returns `{graph, type}`,
   MethodDefinition and SubroutineDefinition adapted to new shape.
   `block-type.t` should pass.
3. **Commit 3 (VariableDeclaration):** Migrate VariableDeclaration
   to scope/graph extension. Some
   `build-graph-control-chain.t` cases pass.
4. **Commit 4 (Assignment + Call):** Migrate AssignmentExpression
   and CallExpression. Full `build-graph-control-chain.t` passes.
5. **Commit 5 (Implicit return + lexical bindings):** Push
   implicit-return synthesis and VarDecl-collection out of
   `_build_method_graph` into MethodDefinition itself.
   `method-implicit-return.t` and `method-lexical-bindings.t` pass.
6. **Commit 6 (Delete `_build_method_graph`):** Remove the helper.
   `build-graph-linear-reachability.t` should pass (graph is
   reachable from Start without body_stmts seed).

Each commit must keep the regression invariant: all 9887e5d1-green
tests stay green. The 5 pre-existing failures (cfg-loop-phi,
scope-if-merge, semantic-action-scope, postfix-loop-phi,
phi-integration, earley-chart-repr.t timing test,
earley-semantic-integration test 3) stay failing identically (do
not improve, do not worsen — they're tracked separately).

## Gotchas to avoid

1. **Context immutability.** Each action *returns* a Context; it
   does NOT mutate `$ctx`. Use `extend()` or build a fresh Context
   to update scope/graph.

2. **`current_type_context()` and `current_mop()` exist.** Per
   `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`, SA has
   class-level current-instance accessors. MethodDefinition reads
   the TI focus via `current_type_context()` (Actions.pm:662).
   These exist because intermediate multiply contexts don't always
   propagate every field — when in doubt, use them, but prefer
   `$ctx->scope` etc. directly when the field is propagated.

3. **TI may still hold the authoritative return type.** Phase
   3a-migration says "Block's type IS the method's return type" —
   but TypeInferenceActions::MethodDefinition currently writes
   `method_return_type` to TI focus and Actions.pm reads it.
   Either: (a) keep both temporarily and assert they match, or
   (b) cut over fully and remove the TI-side code. Plan suggests
   (b) but be careful about test breakage.

4. **Block's existing callers also handle `{__adjust_body, __phaser_block}` markers.**
   Actions.pm:1282 — Block collects these too. The new
   `{graph, type}` return shape must not break this. Options:
   add a third key for these markers, or keep the arrayref shape
   for Block and add the `{graph, type}` info to its Context
   annotations instead. The plan implies the former; verify
   against actual callers.

5. **Graph from Block must propagate up.** When Block returns
   its `{graph, type}` focus, MethodDefinition gets it via
   `_collect_ir_leaves` (Actions.pm:629). The graph reference
   needs to be the same one MethodDefinition then attaches to
   the MethodInfo — which means computation actions inside the
   block must have `$ctx->graph` pointing at the same Graph
   object Block ends up returning. The Block's Context's
   `$graph` field must be propagated bottom-up from the inner
   computation actions, not freshly constructed at Block scope.

6. **`current_instance()` of SA is the bridge to the actions object.**
   Some actions reach into SA via this for scope queries. After
   migration, prefer `$ctx->scope` directly.

7. **AdjustBlock has the same shape as Method but with `__adjust_body` marker.**
   Symmetrical migration to MethodDefinition.

## Tooling already in place

- `script/chalk-mop-audit` — validates Info/MOP shape across the
  corpus, 0 violations at session-exit. Use to spot-check that the
  migration doesn't introduce shape regressions.
- `script/chalk-fixup-audit` — validates parser correctness (tie
  count, walker fire count). Should remain 0 ties and 0 walker fires.

## State of `origin/pu` at this handoff

- HEAD: `9887e5d1` (Phase 3a-infra complete via cfg_state migration)
- All in-flight work committed and pushed
- Working tree clean
- No pending stashes or background tasks

## First action for the next session

Pick up Task #87. Write `t/bootstrap/mop/block-type.t` first.
Run it against HEAD to verify it fails meaningfully (Block currently
returns an arrayref, not a hashref with `graph`/`type` keys).
Commit it as "test(mop): block-type spec for Phase 3a-migration".
That's the smallest TDD entry point.

After that test is committed and failing, then implement Block's
synthesis in a follow-up commit.

## Reference files

- Plan: `docs/plans/2026-04-21-chalk-mop-migration-plan.md:1063-1161`
  (Phase 3a-migration scope, exit criteria)
- Status: `docs/plans/2026-05-20-mop-migration-3a-infra-status.md`
  (3a-infra completion record — the precondition this builds on)
- Current Actions.pm: 2470 lines, see methods listed above
- Existing MOP tests: `t/bootstrap/mop/` (15 files)
- Current `_build_method_graph`: Actions.pm:768-846 (to delete)
