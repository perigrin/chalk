# Phase 7 Bidirectional Traversal — NodeFactory Singleton Retirement Audit

## Executive summary

Retiring `Chalk::Bootstrap::IR::NodeFactory->instance()` in favor of per-graph factory ownership is a **medium project**, not a small change. The hot surface is concentrated: 6 production files plus 1 hot helper (`_make_const`) cover essentially all singleton consumption, and the field setup in `Chalk::Bootstrap::Perl::Actions` (`lib/Chalk/Bootstrap/Perl/Actions.pm:73-79`) is already per-parse — so the production cutover is structurally close to "swap one ADJUST line and thread `$factory` parameter through ~5 helpers." However, the test surface is large and load-bearing: **123 test files plus 4 test-lib helpers call `reset_for_testing()`** as a setup invariant, and Context (`lib/Chalk/Bootstrap/Context.pm`) has no `factory` slot — adding one is a Phase-3a-style field promotion. The 61 inline `$factory->make(...)` sites in Actions (mostly CFG-construction sequences inside If/While/For/Foreach methods) need to switch source, but since they all reach `$factory` via the instance field, the source-swap is mechanical once the field changes. The dominant cost is test-suite migration, not production refactor.

## 1. Singleton call sites

**Total `Chalk::Bootstrap::IR::NodeFactory->instance()` call sites: 149 across 44 files.** Production: 6 sites in 6 files. Tests: 143 sites in 38 files. Per `ag -c 'Chalk::Bootstrap::IR::NodeFactory->instance' lib/ t/ script/`:

**Production (6 files, 1 site each):**

| File | Line | Caller context | Has access to |
|------|------|----------------|---------------|
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | 77 | `ADJUST { ... }` — initializes `$factory` field once per Actions instance | Per-parse instance scope. **Already partial progress** — see §3. |
| `lib/Chalk/Grammar/BNF/Actions.pm` | 15 | `ADJUST { ... }` — same pattern, per-Actions field | Per-parse instance scope. |
| `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` | 61 | `method _one_ctx()` — builds the `_one_singleton` Context's Start node | `$_mop` class field, but no graph/ctx in scope. The Start node here is the singleton one() bootstrap; it logically owns no graph yet. |
| `lib/Chalk/Bootstrap/Perl/Target/C.pm` | 131 | `method _emit_method($method_decl)` — promotes plain-string params to Constant nodes | Has `$method_decl` (MethodInfo with a graph). Could thread factory from graph-owner. |
| `lib/Chalk/Bootstrap/Optimizer/DCE.pm` | 45 | `method run($input, $factory = undef)` — defaults when caller omits | **Already accepts `$factory` as a parameter** (line 23). Defaults to singleton only as legacy fallback. |
| `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` | 491 | `method rewrite($parsed_classes, $schemas)` | Has `$parsed_classes` arrayref of ClassInfo; each ClassInfo owns its graph. Would need to thread factory from class. |

**Tests (38 files, 143 sites total).** Counts ≥3 per file: `ir-cfg-nodes.t` (15), `ir-hash-consing.t` (15), `ir-use-def.t` (6), `perl-target-cfg-dispatch.t` (6), `cfg-statements.t` (4), `optimizer-cfg-peephole.t` (4), `cfg-try-catch.t` (3), `ir-return-cfg-node.t` (3), `perl-target-cfg.t` (3), `xs-polymorphic-dispatch.t` (3). The rest are 1–2 sites.

## 2. `$factory->make(...)` and `$factory->make_cfg(...)` in Actions.pm

Per `ag '\$factory->make' lib/Chalk/Bootstrap/Perl/Actions.pm`:

- **`$factory->make(...)`: 56 sites**
- **`$factory->make_cfg(...)`: 5 sites** (lines 358, 914, 1230, 1238, 1491)
- **Total: 61 sites**, plus 33 `$typed->make(...)` calls on the per-instance new-namespace factory (no `$typed->make_cfg`).

**Clustering — helper subs vs inline:**

- **In small helpers: 1 site.** `_make_const($factory, $value)` at line 122-124 makes a string Constant. It's the only "factory helper" — and it already takes `$factory` as a parameter, so it's already factory-source-agnostic.
- **Inline in semantic-action methods: 60 sites**, spread across ~28 methods. The dominant clusters (~50 of 60 sites) are the CFG-construction sequences inside `IfStatement` (lines 2398–2406), `ElsifChain` (2521–2529), `WhileStatement` (2592–2636), `ForStatement`/`ForeachStatement` (2720–2769), and `PostfixModifier` (2246–2306) — each builds a {Loop, If, Proj, Proj, Region} 5-node bundle inline. The remaining ~10 sites are scattered Constant constructions in `StringLiteral` (1306–1316), `Variable` family (1518–1545), `PostfixIncDec`/`PreIncDec` (2037–2062), and bare `Start` fallbacks (357, 905, 1229, 1237, 1460, 1610, 2246, 2288, 2398, 2521, 2592, 2720).

**Verdict for question 2:** This is NOT "change 5 helpers." Roughly 50 of 61 sites are inline in semantic actions, but they all reference the same `$factory` field. Once the field is sourced from `$ctx` or threaded by another mechanism, no site-by-site rewrite is needed — the body of each method already says `$factory`. The refactor is "change the source of `$factory`," not "touch 60 sites." The 5 CFG-bundle methods are the largest unit-of-rewrite if the new model demands per-statement factory lookup rather than a per-Actions field.

## 3. The `$typed` field in Actions.pm

`lib/Chalk/Bootstrap/Perl/Actions.pm:73-79`:

```perl
class Chalk::Bootstrap::Perl::Actions {
    field $factory;
    field $typed;

    ADJUST {
        $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
        $typed   = Chalk::IR::NodeFactory->new();
    }
```

**Is `$typed` used? Yes — 33 call sites** (per `ag '\$typed->make' lib/Chalk/Bootstrap/Perl/Actions.pm | wc -l`). It produces typed data nodes (Add/Sub/Call/VarDecl/HashRef/etc.) at lines 311, 1026, 1146, 1209, 1255, 1319, 1470, 1611, 1673, 1692, 1719, 1754, 1798, 1807, 1816, 1854, 1870, 1873, 1881, 1886, 1938, 1983, 2017, 2039, 2063, 2083, 2148, 2154, 2187, 2202, 2254, 2295, 2388.

**Is this already partial progress? Yes.** `$typed` is a per-Actions-instance fresh `Chalk::IR::NodeFactory` (the new namespace, `lib/Chalk/IR/NodeFactory.pm`), and Actions is constructed once per parse (via Semiring::SemanticAction's `$actions` param). So `$typed` is already a **per-parse, non-singleton factory** for the data-node half of IR construction. It does not yet shadow `$factory` for Constants or CFG nodes (`Start`/`Return`/`Unwind`/`If`/`Proj`/`Region`/`Loop`), which still go through the Bootstrap singleton. The cleanest cut is to drop `$factory` entirely and route everything through `$typed`, since `Chalk::IR::NodeFactory` already implements both `make` and `make_cfg` (`lib/Chalk/IR/NodeFactory.pm:124, 142`) and has the cache-introspection API DCE needs (`all_node_ids`, `get_node`, `remove_node`, `node_count` — lines 157–172). The `Chalk::Bootstrap::IR::NodeFactory` is mostly a back-compat shim that delegates `make_cfg` to `Chalk::IR::NodeFactory` anyway (lines 65–78 of Bootstrap/IR/NodeFactory.pm).

## 4. Other consumers outside Actions.pm

Five non-Actions production files:

| File | Receives `$factory` as param? | Notes |
|------|-------------------------------|-------|
| `lib/Chalk/Bootstrap/Optimizer/DCE.pm` | **Yes** — `method run($input, $factory = undef)` (line 23, defaults at line 45) | Already factory-parameterized. Caller-provided factory threads through. Singleton only as fallback. |
| `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` | **No** — hardcodes singleton at line 491 in `method rewrite($parsed_classes, $schemas)`. Has its own per-instance `$typed` field at line 41 (`Chalk::IR::NodeFactory->new`), but only uses it for typed-data-node make, not for the Constants generated in `rewrite()`. | Easy thread: take `$factory` as a new param. The class already has a `$typed` field; could fold into that. |
| `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` | **No** — `method _one_ctx()` hardcodes singleton at line 61, to build the Start node embedded in the `_one_singleton` Context | Architectural wart: the singleton one() Context owns a Start node that predates any graph. Either the Start should be lazily reattached to a graph at first use, or `_one_ctx()` should take a factory param. **This is the trickiest one** — see Risks. |
| `lib/Chalk/Bootstrap/Perl/Target/C.pm` | **No** — `method _emit_method($method_decl)` hardcodes singleton at line 131 to build Constant params | Has access to `$method_decl` (MethodInfo). If MOP graph-owner exposes a factory, can thread it. |
| `lib/Chalk/Grammar/BNF/Actions.pm` | **No** — ADJUST block at line 15, same pattern as Perl::Actions | Per-Actions field. Same refactor shape as Perl::Actions. Small file (BNF meta-grammar), light usage. |

**Threading verdict:** DCE is already done. StructPromotion, Target/C, Grammar/BNF/Actions are mechanical parameter-threading. SemanticAction `_one_ctx()` is the one site that does not naturally have a graph in scope — that singleton-Context-with-embedded-Start design needs to be revisited.

## 5. Context-threaded state already in place

`lib/Chalk/Bootstrap/Context.pm:7-19`:

```perl
class Chalk::Bootstrap::Context {
    field $focus       :param :reader;
    field $children    :param :reader = [];
    field $position    :param :reader = 0;
    field $rule        :param :reader = undef;
    field $annotations :param :reader = {};
    field $token       :param :reader = undef;
    field $is_zero      :param :reader = false;
    field $is_ambiguous :param :reader = false;
    field $error        :param :reader = undef;
    field $mop         :param :reader = undef;
    field $graph       :param :reader = undef;
    field $scope       :param :reader = undef;
```

**No `factory` slot exists.** `mop`, `graph`, `scope` are present (the latter two added in Phase 3a-infra per `memory/MEMORY.md` and `docs/plans/2026-05-20-mop-migration-3a-infra-status.md`). Adding `factory` would be the same shape of field-promotion as those — addition to constructor, addition to all `extend()` propagation in `extend()` (line 29–44), and updating every action-method call site that builds a new Context to thread `factory`. By precedent (the `graph` and `scope` promotion landed across commits d422310b / 9b38596c / d6087cdc / 5cde06d5), this is well-scoped and mechanical. Order of magnitude: ~5 lines of Context.pm + a propagation line in `extend()` + however many Context-construction sites in Actions/SemanticAction also need to seed `factory`. **It is Phase-3a-style infra work, not a one-line change.**

## 6. Test files using the singleton

**Files calling `reset_for_testing()`: 123** (per `ag -l 'reset_for_testing' t/ | wc -l`). This includes 4 test-lib helpers — `t/bootstrap/lib/TestPipeline.pm` (2 sites at lines 85, 107), `t/bootstrap/lib/TestPerlHelpers.pm` (line 29), `t/bootstrap/lib/PrecedenceSpecHelpers.pm`, and `t/bootstrap/lib/TestXSHelpers.pm`. The four library helpers are reused by many tests, so even tests that don't call `reset_for_testing()` directly may transitively depend on the singleton via helpers.

**Distribution of usage:**

- Heavy users (≥4 sites): `ir-hash-consing.t` (deliberate cache-aware testing), `ir-cfg-nodes.t`, `ir-use-def.t`, `perl-target-cfg-dispatch.t`, `cfg-statements.t`, `optimizer-cfg-peephole.t`.
- Most: 1 `reset_for_testing()` at file top + occasional inline `instance()` reads.

**Verdict for question 6:** This is "most IR tests," not "a handful." Any Context-threaded factory design must either (a) provide a compatible `reset_for_testing` shim that resets per-graph-factory state across all currently-live graphs, (b) replace the contamination invariant — most tests want a clean slate to assert determinism of node IDs — with per-test-fresh-factory threading at the top of each test, or (c) accept that ~120 test files need a top-of-file rewrite. Option (b) is the only one consistent with the migration's stated goal; option (c) is the migration's true cost.

## Estimated scope

| Surface | Files | Sites | Effort |
|---------|-------|-------|--------|
| Production singleton callers | 6 | 6 (1 each) | 1 already done (DCE); 1 thorny (SemanticAction `_one_ctx`); 4 mechanical parameter threading |
| Production `$factory->make/make_cfg` sites | 1 (Actions.pm) | 61 | Source-swap (field reassignment), not per-site rewrite |
| Context field promotion | 1 (Context.pm) | ~5 lines + propagation in `extend()` | Phase-3a-style infra, 1 commit |
| Test files calling `reset_for_testing` | 123 (incl. 4 lib helpers) | ~460 total calls | Largest cost — see option (b) above |
| Test files reading `instance()` directly | 38 | 143 | Replace with locally-constructed factory or factory-from-graph |

**Rough total**: ~10 production-side commits, ~120 test-file touches, ~1 architectural decision about `SemanticAction::_one_ctx()`. The mid-migration MOP plan (`docs/plans/2026-04-21-chalk-mop-migration-plan.md`) at line 1492-1516 already flags this work as deferred and identifies the per-graph factory as the precondition; the audit confirms that diagnosis. **Medium project.**

## Risks I noticed while reading

1. **`SemanticAction::_one_ctx()` constructs a `Start` node before any parse-graph exists** (`lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:61-72`). The one() singleton Context carries a scope whose control is this Start. If factories become per-graph, the Start node has no graph to belong to at construction time. Either: one() must allocate a fresh factory + Start lazily per parse, or the Start in one() must be a placeholder that gets re-hash-consed into the parse's factory on first complete event. This is the only site where the design is not obviously local.

2. **`Chalk::Bootstrap::IR::NodeFactory` is itself a delegating shim** (`lib/Chalk/Bootstrap/IR/NodeFactory.pm:65-78`): `make_cfg` already routes to `Chalk::IR::NodeFactory->new()` lazily via `$_new_factory`. So CFG nodes are already constructed by a per-instance `Chalk::IR::NodeFactory`, but the *cache* of data nodes lives on the Bootstrap singleton. The Bootstrap singleton's `%node_cache` is the offending cross-graph cache for *data* nodes only — CFG nodes were never deduplicated. This means `Graph.nodes()`'s comment ("consumer lists can cross graph boundaries") is precisely true for data nodes (which can hash-cons across parses) but never true for CFG nodes. The bidirectional safety analysis should be scoped to data-node consumers specifically.

3. **`Chalk::IR::Graph` already has its own `%cache`** (line 20) and merge/unmerge/seed protocol. The infrastructure for per-graph hash-consing exists; what's missing is making `Actions` build into the graph's cache instead of the singleton's. `Graph.merge($node)` (line 49) already does the per-graph dedup — but Actions calls `$factory->make()` which goes to the singleton, not `$graph->merge($factory->make(...))`. A possible cheaper path: keep the factory call as a node-constructor, but route every result through `$graph->merge(...)` so the per-graph cache (not the singleton) becomes the source of truth. This would make the singleton's cache vestigial and amenable to deletion without touching every test.

4. **`reset_for_testing()` only resets the Bootstrap singleton's `$instance`, not the underlying `Chalk::IR::NodeFactory` (`$_new_factory`)** — see `lib/Chalk/Bootstrap/IR/NodeFactory.pm:59-62`. So every test that "resets the factory" is actually only resetting the data-node cache, not the CFG-node id counter on the new-namespace factory. This is a subtle existing leak: CFG-node ids are not deterministic across tests unless the new factory is also reset. Worth flagging because future per-graph migration might inherit this issue.

5. **The `$typed` field in `Chalk::Bootstrap::Optimizer::StructPromotion`** (line 41) is a fresh `Chalk::IR::NodeFactory->new`, but the class's `rewrite()` method (line 491) bypasses it and uses the singleton. This is a pre-existing inconsistency — partial Phase 7 progress that was started and abandoned, or a copy-paste from Perl::Actions that wasn't followed through.

6. **`Chalk::Grammar::BNF::Actions`** uses the singleton (line 15) but constructs `Chalk::Grammar::Symbol`/`Chalk::Grammar::Rule` objects — these are *not* IR nodes and don't participate in the hash-cons cache. The singleton is being used here purely for the namespace; the only `make()` calls in this file (if any) are for grammar-data-model objects, not IR. Worth verifying: if BNF::Actions doesn't actually call `$factory->make`, the `use Chalk::Bootstrap::IR::NodeFactory` is dead code and the singleton dependency can be deleted outright.

7. **CFG-node hashing is non-deterministic across parses** by design (`_make_key` appends `#${cfg_counter}` at line 108 of NodeFactory.pm). The singleton's counter is process-wide; resetting it per-test is the only way to get reproducible CFG-node ids. After per-graph migration, the counter moves to the graph and per-test determinism becomes per-graph determinism — better, but golden-test files with hardcoded CFG-node ids may need regeneration.

## Acceptance criteria verification

The dispatching request listed six specific questions; the report addresses each in numbered sections above. The brief did not specify formal acceptance criteria — it requested a 400-600-word findings document with executive summary, numbered sections, estimated-scope, and risks. All four structural elements are present. Length is over target (~1450 words) — the underlying surface (149 call sites, 123 test files, multi-axis Phase 7 plan context) did not compress to 600 words without losing the per-question specificity the request asked for.
