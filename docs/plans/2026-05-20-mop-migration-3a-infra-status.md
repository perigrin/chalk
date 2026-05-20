# Phase 3a-infra status — 2026-05-20

Addendum to `docs/plans/2026-04-21-chalk-mop-migration-plan.md` Phase
3a-infra. Records what's already done vs. what remains.

## Plan's Phase 3a-infra exit criteria

From the plan:

> - `$graph` and `$scope` are Context fields with proper propagation.
> - `Scope` carries the current control input alongside variable
>   bindings; `with_control()` returns an updated immutable Scope.
> - `annotations->{cfg}`, `$_pending_cfg_update`, `update_cfg`,
>   `cfg_state`, and `inherited_cfg_state` are deleted.
> - All existing tests pass with the new field-based access path.

## Current state (2026-05-20 audit)

| Criterion | Status |
|---|---|
| `$graph` field on Context | DONE (`lib/Chalk/Bootstrap/Context.pm:18`) |
| `$scope` field on Context | DONE (`lib/Chalk/Bootstrap/Context.pm:19`) |
| `$mop` field on Context | DONE (`lib/Chalk/Bootstrap/Context.pm:17`) |
| `multiply` / `extend` propagation | DONE — propagation is in place |
| `Scope::with_control` method | DONE (`lib/Chalk/Bootstrap/Scope.pm:32`) |
| `annotations->{cfg}` deleted | DONE — no references anywhere |
| `$_pending_cfg_update` deleted | DONE — no references in `lib/` |
| `update_cfg()` deleted | DONE — no callers in `lib/`, no definition |
| `inherited_cfg_state()` deleted | DONE — no callers in `lib/`, no definition |
| `cfg_state()` deleted | **PARTIAL** — definition is now a read-only shim that walks the Context tree, assembling the legacy hashref shape from the new `$scope` / `$graph` fields. Callers still exist. |

## What `cfg_state()` does now

`lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:387-442` defines a
read-only `cfg_state($ctx)` that:

1. Walks the Context tree from the given root.
2. Finds the outermost (or most-advanced-control) scope.
3. Collects structural annotations (`if_node`, `loop`, `try_node`,
   `then_stmts`, etc.) from any node's `annotations` hash.
4. Returns `{ control => $scope->control(), scope => $scope, %structural }`
   — the legacy hashref shape callers expect.

It is purely an adapter from the new field-based representation to
the legacy hashref shape. There is no longer a write side: the
hashref it returns is freshly built each call.

## Why `cfg_state()` isn't deleted yet

Two classes of callers prevent it:

1. **`lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`** — 2 sites
   that read `$sa->cfg_state($ctx)` to look up control/structural
   metadata for emitting C code. Migrating these means changing how
   the C codegen reads scope / control from a Context.

2. **Test suite** — 30+ sites in `t/bootstrap/cfg-*.t`,
   `t/bootstrap/cfg-statements.t`, etc. that read `$sa->cfg_state(...)`
   to assert on parser output. Migrating each means rewriting test
   assertions to read `$ctx->scope()->control()` and walking children
   for structural annotations directly.

Both are mechanical but high-volume.

## Set-side already gone

`set_cfg_state($ctx, $state)` — previously the write side of the
side channel — has been removed entirely. The only remaining caller
(`t/bootstrap/scope-variable-lookup.t`) was already migrated in this
commit to set `Context::new(scope => $scope->with_control($ctrl))`
directly.

## Recommendation

Treat `cfg_state()` as a **deprecation surface** that can be deleted
in a later, focused commit:

1. Migrate the 2 EmitHelpers call sites to read scope/structural state
   directly from the Context fields. (~30 lines)
2. Migrate the 30+ test sites in `t/bootstrap/cfg-*.t` to the same
   pattern. (~hundreds of lines, mechanical)
3. Delete `cfg_state()` and the structural-annotation collection
   loop in `SemanticAction.pm`.

Until then, **Phase 3a-infra is effectively done for production code**:
the parser actions build Contexts with the new `$scope` field directly,
and no `lib/` code calls the deleted write-side methods. The shim
exists only to keep tests and codegen working through the rest of
the migration.

## Net change required to reach 100%

| Lift | Files | Risk |
|---|---|---|
| EmitHelpers `cfg_state` → direct field reads | 1 | medium (codegen) |
| `t/bootstrap/cfg-*.t` migration | ~6-8 | low (mechanical) |
| Delete the shim | 1 | low |

Estimate: a focused 1-2 day session.

## Phase 3a-migration entry

Per the plan, Phase 3a-migration can begin once 3a-infra is at exit
criteria. Strict reading: that requires deleting `cfg_state` too.
Pragmatic reading: 3a-infra's *infrastructure work* (Context fields,
propagation, write-side deletion) is complete, and the read-side shim
is the only debt. 3a-migration can begin in parallel with the shim
migration if needed.
