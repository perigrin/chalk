# Factory Unification Audit (Phase 7c #2 pre-flight)

**Status:** AUDIT, 2026-05-21
**Oracle:** Code-vs-plan (Phase 7b stages 2c/2d, this file's brief), plus
internal-invariant oracle on factory-ownership of consumer pointers per
`lib/Chalk/IR/Graph.pm` lines 112-118 (consumer pointers must stay
graph-local; current Graph::nodes() comment names the singleton's
process-wide cache as the leakage source).

## Executive summary

`Chalk::Bootstrap::Semiring::SemanticAction::_one_ctx` (file
`lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:60-86`) and
`Chalk::Bootstrap::Perl::Actions`'s `ADJUST` (file
`lib/Chalk/Bootstrap/Perl/Actions.pm:76-79`) construct two unrelated
`Chalk::IR::NodeFactory->new` instances per parse. No wiring point exists
that connects them — they never refer to the same object. Actions reads its
own `$typed` (33 call sites) for typed data nodes, and the Bootstrap
singleton via `$factory` (61 call sites) for legacy permissive-make ops,
including the controlling nodes (`Start`, `Return`, `Unwind`) that flow
into typed nodes built by `$typed`. Consumer pointers therefore cross
factory boundaries: a `Return` built by Actions's `$factory`
(Bootstrap singleton) has its `$start` input registered as a consumer on a
`Start` node owned by either the Bootstrap singleton or, separately, the
`_one_ctx` factory whose Start is also built via the singleton (line 72-73).
The two `Chalk::IR::NodeFactory->new` factories created at lines
`SemanticAction.pm:82` and `Actions.pm:78` are never reached by each
other's nodes; the singleton is in fact the leakage carrier today, not
those `->new` factories.

**Verdict: unify via path (b) — `_one_ctx` is the producer, Actions is the
consumer.** Promote the `_one_ctx`-seeded factory to be the single
parse-level typed factory by switching Actions to read `$ctx->factory()`
from each action's incoming Context. Expected scope: ~35 typed call-site
edits in `Actions.pm` (already use `$typed`, switch the reader), drop the
`$typed` field + `ADJUST`. Stages 2d/2e of the existing Phase 7b plan
already describe this; this audit confirms it is the correct path.

## 1. `_one_ctx` factory creation

Reading `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:60-86`: `_one_ctx`
creates one Context per `(reset_cache, set_mop)` epoch. Inside the
`if (!defined $_one_singleton)` branch it constructs both
`Chalk::Bootstrap::IR::NodeFactory->instance()` (the Bootstrap singleton,
used only to build the singleton's `Start` node — see comments at 67-71)
**and** a fresh `Chalk::IR::NodeFactory->new` (line 82), which it stores
into the Context's `factory` field. The `$_one_singleton` class lexical
(`my $_one_singleton` at line 45) holds the Context.

Lifecycle: cleared explicitly in three places:
- `reset_cache()` at line 172 (`$_one_singleton = undef`),
- `set_mop()` at line 209 (`$_mop = $mop; $_one_singleton = undef`).

So the factory is **reused across all `->one()` calls within a single
parse**, and reset between parses by `reset_cache`. The test
`t/bootstrap/mop/per-parse-factory-thread.t:30-33` asserts exactly this:
after `reset_cache`, the next `->one()` carries a different factory
refaddr. There is no invalidation other than `reset_cache` and `set_mop`.

## 2. Actions factory creation

`lib/Chalk/Bootstrap/Perl/Actions.pm:73-79` declares two fields and an
`ADJUST`:

```
field $factory;
field $typed;
ADJUST {
    $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    $typed   = Chalk::IR::NodeFactory->new();
}
```

`$typed` is a fresh `Chalk::IR::NodeFactory->new` per Actions instance.
Actions is instantiated once per parser-build by
`TestPipeline::_build_perl_parser_with_actions` at
`t/bootstrap/lib/TestPipeline.pm:184`
(`Chalk::Bootstrap::Perl::Actions->new()` passed into `SemanticAction`).
A second instantiation site exists in
`t/bootstrap/xs-earley-full-semiring.t:88` and `t/bootstrap/c-end-to-end.t:397`.
Actions's lifetime equals the parser's lifetime — it can outlive a single
`parse_value` call if a test reuses the parser, but no production code path
re-uses an Actions across multiple files (`reset_cache` is called between
files; Actions is rebuilt with a fresh parser by `build_perl_ir_parser`).

## 3. Are the two factories ever the same instance?

**No.** Tracing the construction sites:
- `_build_perl_parser_with_actions` (TestPipeline:134-162) builds a fresh
  `SemanticAction->new(actions => $actions)` and passes the Actions
  reference in via `actions =>`. SemanticAction does not look at
  `$actions->typed` and never installs a factory into Actions.
- `_one_ctx` builds its own `Chalk::IR::NodeFactory->new` (line 82).
- Actions's `ADJUST` builds its own `Chalk::IR::NodeFactory->new` (line 78).
- There is no setter on Actions that would replace `$typed` with the
  Context-seeded factory.

The two `->new` factories at `Actions.pm:78` and `SemanticAction.pm:82`
are different `refaddr`s and have disjoint `%cache` and `$cfg_counter`
state.

## 4. Cross-factory consumer-pointer leakage

Consider Actions's `Return` construction at
`lib/Chalk/Bootstrap/Perl/Actions.pm:357-360`:

```
my $control = _ctx_control($ctx) // $factory->make('Start');
return $factory->make_cfg('Return',
    inputs => [$control, $value // _make_const($factory, 'undef')],
);
```

`$factory` here is the **Bootstrap singleton**, not Actions's `$typed`,
not `_one_ctx`'s typed factory. So:

- The `Return`'s `inputs` list contains a `$control` node. If `$control`
  came from a typed factory (e.g., a `Start` built earlier by the
  `_one_ctx`-seeded factory and propagated through scope), then
  `_register_consumers` (`Chalk/IR/NodeFactory.pm:122-136`) registers the
  Return as a consumer on the Start by calling `$input->add_consumer($node)`
  (line 133). **Yes** — the Return appears in `$start->consumers`,
  regardless of which factory built either node. Consumer pointers are
  attached to node fields directly (`Chalk/IR/Node.pm:17, 26-28`), not via
  any factory-side bookkeeping. There is no factory-affinity check.
- The Return goes into the **Bootstrap singleton's** cache *if* `make_cfg`
  is called via the singleton's shim (`Chalk/Bootstrap/IR/NodeFactory.pm:75-78`
  delegates to its private `$_new_factory`); the singleton's `%node_cache`
  receives the entry. The `_one_ctx`-seeded factory's `%cache` and the
  per-Actions `$typed` `%cache` both stay empty for this Return.
- When `Graph::nodes()` (`Chalk/IR/Graph.pm:104-162`) walks consumers from
  a graph-cached node, the consumer-pointer is followed if and only if the
  pointed-to node is in the graph's `%cache` (the `$in_cache` predicate at
  line 119-125). The Graph's `%cache` is populated via `$graph->merge($node)`
  (line 49-57) or `_seed` (line 39-44). So a Return that was built but never
  passed through `graph->merge` will not be in the cache, and bidirectional
  walking skips it — which is the existing safety argument. **But** any
  Return that *was* merged into the graph stays reachable from any input it
  consumes, including inputs owned by a different factory, because consumer
  pointers are factory-agnostic.

In short: cross-factory consumer-pointer leakage is structurally
possible today and is the exact problem Phase 7b is meant to close
(see Graph.pm:112-118 comment naming the singleton's process-wide cache
as the leak).

## 5. What unification would look like

Path **(b) — Actions reads `$ctx->factory()`** is the recommended path,
matching Phase 7b §Stage 2d
(`docs/plans/2026-05-21-phase-7b-factory-promotion.md:154-158`).

- **Touches:** `lib/Chalk/Bootstrap/Perl/Actions.pm` — ~33 `$typed->`
  call sites switch to `$ctx->factory->`, the `field $typed` and the
  ADJUST initialization of `$typed` are removed. The `$factory` field
  (Bootstrap singleton) remains for the 61 call sites still on the
  legacy permissive-make path until Phase 7c #3 unifies them too.
  Net diff: roughly 35 lines changed.
- **Lifecycle:** `_one_ctx` runs the first time `$semiring->one()` is
  called inside Earley (`lib/Chalk/Bootstrap/Earley.pm:439`), which is
  inside `parse_value` and **after** Actions's ADJUST (which ran at
  Actions construction during `build_perl_ir_parser`). So at the time
  Actions methods execute, `$ctx->factory()` is guaranteed populated.

Path **(a) — `_one_ctx` accepts a factory parameter** is worse because
it requires either changing the `->one()` signature (Earley calls
`$semiring->one()` with no arguments at five call sites in Earley.pm) or
introducing a separate `set_factory()` setter and a "who calls it first"
ordering constraint. Path (b) keeps `one()` zero-argument and lets the
SA semiring own the factory's creation.

## 6. Lifecycle ordering — who runs first?

Walking `build_perl_ir_parser($g, start => 'Program')` at
`t/bootstrap/lib/TestPipeline.pm:181-186`:

1. `Actions->new` runs first. Actions's ADJUST fires immediately — `$typed`
   and `$factory` populated.
2. `SemanticAction->new(actions => $actions)` runs next
   (TestPipeline.pm:147-149). No factory created at this point; `_one_ctx`
   is lazy.
3. `set_mop` is called at TestPipeline.pm:152, clearing `$_one_singleton`
   (it was undef already).
4. `parse_value` calls `$semiring->one()` for the first time (Earley.pm:439).
   FilterComposite::one() at FilterComposite.pm:100-132 calls
   `$self->_sa()->one()`, which calls SA's `_one_ctx()`. **This is when
   the per-parse typed factory is created.**
5. Actions methods fire from inside `_complete_sa` (SA.pm:256-402) during
   chart processing. Each action sees its incoming `$ctx`, which is
   descended from the one() Context — `$ctx->factory()` is the
   `_one_ctx`-seeded factory.

So **`_one_ctx` runs after Actions::ADJUST but before any Actions method
fires**. Path (b) works because by the time Actions code runs, the factory
is reachable via `$ctx`. A lazy accessor on the SA instance is unnecessary
— `$ctx->factory()` is already available.

## 7. Tests that depend on factory identity

`grep -rn 'factory()' t/bootstrap/` returns mostly the
`per-parse-factory-thread.t` test (above) and the `ir-use-def.t` tests
which explicitly construct `Chalk::IR::NodeFactory->new` for unit-level
testing of consumer-pointer registration. None of them assert that
`_one_ctx`'s factory and Actions's `$typed` are *different*.

The 123 test files calling `reset_for_testing` (Phase 7b plan §Out of
scope, line 180) all reset the Bootstrap singleton, not the per-Actions
`$typed`. After path (b) unification, `$typed` is gone; `_one_ctx`'s
factory is recreated by `reset_cache` (already covered). No test
modifications required beyond those Phase 7b already enumerated.

The only test that could plausibly break is `per-parse-factory-thread.t`
itself, which already passes; it would continue to pass since `_one_ctx`
remains the producer.

## Migration recipe (path b, minimum surface)

1. **Add a fallback** in `Actions.pm`: `my sub _factory($ctx) {
   return $ctx->factory() // $typed; }` — a temporary shim so callers can
   migrate piecewise without an all-or-nothing flag day.
2. **Migrate the 33 `$typed->` call sites in Actions.pm** to read
   `_factory($ctx)->` (or take the factory at method top: `my $tf =
   $ctx->factory() // $typed;`).
3. **Verify tests:** the `mop/per-parse-factory-thread.t` test, the full
   `t/bootstrap/` suite, and any `c-end-to-end.t`-style integration test
   that exercises the Earley pipeline.
4. **Remove the `$typed` field** and the `$typed = Chalk::IR::NodeFactory->new`
   line from `ADJUST`. The shim from step 1 collapses to
   `$ctx->factory()`.
5. **Do NOT** touch the 61 `$factory->` sites in this migration. Those
   still construct CFG-routed (Start/Return/Unwind) via the legacy
   `Chalk::Bootstrap::IR::NodeFactory` API. Their migration is Phase 7c #3.

## Risks I noticed

- **Action methods that receive `$ctx` from outside a `_complete_sa`
  invocation** (e.g., the `_resolve_from_scope` helper at Actions.pm:185,
  which receives a `$factory` parameter from a caller) could see
  `$ctx->factory()` as undef if called from a code path where one() was
  never instantiated (e.g., unit tests that hand-construct Contexts).
  Mitigation: the `// $typed` fallback in step 1 covers this until tests
  are audited. After `$typed` is removed, an explicit fallback to
  `Chalk::IR::NodeFactory->new` would be needed for hand-constructed
  test Contexts, or those tests must seed `factory =>` themselves.
- **Two factories sharing a content-hash key is a no-op today** because
  they share no nodes, but after unification the merged factory will see
  *all* node constructions deduped against a single `%cache`. Any silent
  reliance on the current "Actions's `$typed` cache is small" property
  (e.g., test counts assuming a particular `node_count()`) needs review.
  None found in `t/bootstrap/`, but `t/benchmark/parse-performance.t` and
  any memory-bound benchmark should be spot-checked.
- **The Bootstrap singleton's `Start` node at SA.pm:73** is still used by
  `_one_ctx` to seed the scope. After path (b) unification, that Start is
  *not* in the per-parse factory's cache. Any consumer registered on it
  (Returns built by Actions reading `_factory($ctx)`) will create a
  cross-factory consumer pointer in the opposite direction. The Phase 7b
  plan §Decisions made explicit (lines 96-108) flags this and proposes a
  placeholder-Start sentinel as Stage 2e. That work must land before this
  migration if cross-factory leakage is to be fully closed.
- **`Chalk::Grammar::BNF::Actions`** (`lib/Chalk/Grammar/BNF/Actions.pm:15`)
  also reads the Bootstrap singleton. It is *not* in scope for this
  migration — it constructs Symbol/Rule data-model objects, not method-body
  IR — but the same dual-factory pattern would re-emerge there if anyone
  starts building IR from BNF actions. Worth a comment in the migration
  commit message.
- **Other singleton consumers (`DCE.pm:45`, `StructPromotion.pm:491`,
  `Target/C.pm:131`)** still depend on `instance()` being callable. Until
  Phase 7c, those remain wired to the singleton; the migration recipe
  above does not break them.
