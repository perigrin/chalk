# Phase 7b — Factory Promotion and Bidirectional Traversal

**Status:** PLANNED, 2026-05-21
**Entry:** Phase 7 complete (commit `a2939b43` on `pu`).
**Exit:** Bidirectional `Graph::nodes()` shipping, singleton Bootstrap
factory retired, each MOP graph-owner owning its own factory.

## Background

Phase 7 (`docs/plans/2026-04-21-chalk-mop-migration-plan.md` §Phase 7)
intended to restore bidirectional traversal in
`Chalk::IR::Graph::nodes()`. The safety argument — per-graph hash-cons
scope keeps consumer lists graph-local — does not hold in the current
codebase: `Chalk::Bootstrap::IR::NodeFactory->instance()` is a
process-wide singleton, and its `%node_cache` accumulates every data
node constructed during a parse. Consumer pointers on those shared
nodes cross method/class boundaries. Implementing bidirectional
walking pulled trivial Phis and Earley-orphan CFG nodes from
ambiguous action invocations, breaking five reachability tests, and
was reverted.

Two audits dated 2026-05-21 establish what it takes to remove that
constraint:

- `docs/plans/2026-05-21-phase-7-bidirectional-audit.md` — singleton
  call-site map, test-suite contact surface.
- `docs/plans/2026-05-21-phase-7-factory-promotion-audit.md` —
  Context-promotion recipe, MOP graph-owner ownership shape.

## Goal

Make consumer-direction graph traversal safe by giving each
graph its own per-graph factory, and route node construction through
the graph's own hash-cons cache so consumer pointers cannot cross
graph boundaries. Then restore bidirectional traversal in
`Chalk::IR::Graph::nodes()` and delete the Bootstrap singleton's
data-node cache.

## Approach — two stages, single phase

The audits suggested splitting into Stage 1 (route construction
through the graph's cache, keep singleton as a vestigial back-compat
shim) and Stage 2 (full Context-promotion of `$factory`). This plan
bundles both. Stage 1 is the cheaper, narrower change that
unblocks bidirectional traversal; Stage 2 is the proper end state
that retires the singleton. Bundling avoids leaving the codebase in
the intermediate state where the graph cache is authoritative but the
singleton is still allocated and referenced.

### Stage 1 — graph-merge becomes the hash-cons authority

**Today:** `Actions.pm` calls `$factory->make($op, %args)`, which
dedupes against the *singleton's* `%node_cache`. Then sometimes
calls `$graph->merge($node)` separately, which has its own `%cache`
keyed by content_hash. Two caches in tension. Consumer pointers on
shared nodes can therefore reach nodes from a different parse
through the singleton's cache.

**After Stage 1:** every node-construction site in Actions.pm gets a
mandatory `$graph->merge(...)` wrapper. The graph's `%cache` becomes
the source-of-truth for hash-cons identity. If the singleton hands
back a node that's already in the graph's cache (because the same
content_hash was used elsewhere), `$graph->merge` returns the
graph's representative and the singleton's copy is dropped on the
floor for this graph's purposes.

This means: every consumer pointer that the graph's `nodes()` walks
is on a node *in this graph's cache*. The bidirectional safety
argument holds, even with the singleton still in place.

### Stage 2 — Context owns the factory, MOP owns per-graph factories

**Today:** `Actions.pm` `ADJUST`-initializes one `$factory` (the
Bootstrap singleton) and one `$typed` (a per-Actions
`Chalk::IR::NodeFactory->new`). Every action method reads from these
fields. The singleton is shared across all methods/classes in the
parse.

**After Stage 2:**
- `Chalk::Bootstrap::Context` gains a `$factory` field next to
  `$graph` and `$scope` (see Audit 2 §3, §5).
- `Chalk::MOP::Method` and `Chalk::MOP::Sub` gain a `$factory`
  field alongside their existing `$graph` field (Audit 2 §6).
- The MethodDefinition / SubDeclaration / NamedSub action attaches
  a fresh factory to the new MOP::Method/Sub and threads it into
  the body's Context via `extend(factory => $method->factory)`.
- Actions.pm methods read `$ctx->factory` instead of the
  ADJUST-initialized field. The field becomes a fallback for the
  pre-method-body part of the parse, then is removed.
- `Chalk::Bootstrap::IR::NodeFactory->instance()` and its
  `%node_cache` are deleted. `_ensure_new_factory` and the
  `make_cfg` shim go with them.

### Decisions made explicit

**`SemanticAction::_one_ctx()` — the one()-singleton Start node.**
`lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:61` builds a Start
node for the singleton one() Context. This is the only call site
where there is no natural graph in scope. Decision: change the one()
Context's Start to a *placeholder* — a sentinel object that is
re-hash-consed into the parse's factory on the first `extend()` that
provides a factory. The Start is never the same object across parses
today (it's per-Actions-instance via the singleton's lifetime), so
this is not a behavioral regression; it's a small architectural
formalization. Alternative considered: allocate a fresh factory in
`_one_ctx()`. Rejected because it makes one() stateful in a way the
comonad axioms don't permit. The placeholder approach is the
narrower change.

**Graph cache vs factory cache after Stage 2.** Audit 2 §6 flagged
that the graph already maintains its own `%cache` separate from the
factory's. Stage 1 makes the graph cache authoritative. Stage 2 then
makes the factory's cache *also* per-graph (since one factory per
graph). The two caches are still separate but now both per-graph; the
factory cache is the construction-time dedup, the graph cache is the
membership-time dedup. They are not collapsed in this phase. That
collapse is Phase 7c material.

## Scope

### In scope

1. **Stage 1a:** every `$factory->make(...)` and `$factory->make_cfg(...)`
   call site in `lib/Chalk/Bootstrap/Perl/Actions.pm` gets a
   `$graph->merge(...)` wrapper. 56 + 5 = 61 sites per the audit,
   but the work is mechanical — wrap-don't-rewrite.
2. **Stage 1b:** same wrapping in
   `lib/Chalk/Bootstrap/Perl/Target/C.pm` (1 site, `_emit_method`),
   `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm::rewrite`
   (1 site), and `lib/Chalk/Grammar/BNF/Actions.pm` if it actually
   constructs IR nodes (Audit 1 risk #6 — needs verification).
3. **Stage 1c:** TDD test that demonstrates bidirectional traversal
   is now safe. Re-enable bidirectional in `Graph::nodes()`. The
   pre-Phase-7 test `t/bootstrap/ir/graph-bidirectional-traversal.t`
   gets rewritten from "documents what nodes() does NOT do" to
   "verifies nodes() follows both inputs() and consumers()."
4. **Stage 2a:** add `$factory :param :reader` to
   `Chalk::Bootstrap::Context`; thread through `extend()`.
5. **Stage 2b:** add `$factory :param :reader = Chalk::IR::NodeFactory->new`
   to `Chalk::MOP::Method` and `Chalk::MOP::Sub`. Add `make` /
   `make_cfg` proxies parallel to existing `merge` / `next_cfg_id`.
6. **Stage 2c:** at MethodDefinition / SubDeclaration / NamedSub
   action sites, seed the body Context's `factory` from the
   MOP-owned factory.
7. **Stage 2d:** flip Actions.pm readers from `$factory` field
   (Bootstrap singleton) to `$ctx->factory()`. Then a second commit
   removes the `$factory` field and the ADJUST initialization.
   `$typed` stays for now — its consumers don't need Context
   threading because they always run inside a method body.
8. **Stage 2e:** `_one_ctx()` placeholder-Start fix.
9. **Stage 2f:** delete `Chalk::Bootstrap::IR::NodeFactory->instance()`,
   the singleton `$instance` field, the `reset_for_testing` accessor
   that resets it, and the `_ensure_new_factory`/`make_cfg` shim.
10. **Stage 2g:** clean up `StructPromotion.pm` — its existing
    abandoned `$typed` field gets put to use, and the `rewrite()`
    method takes the factory from its caller per audit 1 §4 risk #5.
11. **Stage 2h:** `Chalk::IR::Serialize::JSON::from_json` (audit 2 §2,
    Serialize/JSON.pm:216) — the deserializer constructs a fresh
    factory per load. After Stage 2 it should accept an optional
    factory parameter and default to a fresh one (no behavioral
    change, just removes the implicit dependency).

### Out of scope (explicitly)

- **`compat_class` field removal** on `Chalk::IR::Node`. Still
  deferred — many tests read legacy class names via `->class()`.
- **`Chalk::IR::Program` deletion** and ClassInfo/MethodInfo/SubInfo
  retirement. Separate migration.
- **Collapsing graph cache + factory cache into one structure.**
  Phase 7c. After Stage 2 both caches are per-graph but separate.
- **Test files calling `reset_for_testing`.** Audit 1 counts 123
  files. Stage 2f deletes the method, so all 123 become compile
  errors. But these are local test concerns; each test that breaks
  gets a fresh `Chalk::IR::NodeFactory->new` at the top of the file.
  The bulk-edit happens at Stage 2f. **This is the largest single
  cost of the phase.** Mechanical, but not zero.
- **CFG-node id determinism across tests.** Audit 1 risk #4 — today
  `reset_for_testing` doesn't reset the typed factory's CFG counter.
  After Stage 2f, each test allocates its own factory, so the
  counter is per-test by default. No action required, but golden
  files with hardcoded CFG node ids may need a one-time refresh.

## TDD test plan

Write tests before implementation, as usual.

**Stage 1 tests:**

- `t/bootstrap/ir/graph-merge-is-authority.t` — construct two graphs
  with the same factory, build identical-content nodes into each
  via `$factory->make` then `$graph->merge`. Assert: each graph's
  `nodes()` returns its own representative, consumers on
  `$graph_a`'s node list nothing from `$graph_b`. This test
  currently *fails* with the singleton because hash-cons collapses
  identical content across graphs.
- Rewrite `t/bootstrap/ir/graph-bidirectional-traversal.t` to
  verify (not document the absence of) consumer-following.

**Stage 2 tests:**

- `t/bootstrap/context/factory-field.t` — Context has a `factory`
  field, accessible via `->factory()`. `extend(factory => ...)`
  propagates it. Two siblings can carry different factories.
- `t/bootstrap/mop/method-owns-factory.t` — MOP::Method's `$factory`
  default is a fresh `Chalk::IR::NodeFactory`. Two methods have
  distinct factories.
- `t/bootstrap/mop/per-method-factory-isolation.t` — parse a class
  with two methods that have body-identical IR (same shape, same
  variable names). Assert: each method's graph has its own nodes
  by identity; `refaddr($m1->graph->nodes->[0]) !=
  refaddr($m2->graph->nodes->[0])` for hash-consed Constants. This
  is the test that proves we've fixed the cross-graph contamination
  problem.

**Regression guard:**

- Every test green at Phase 7 exit (`a2939b43`) must be green at
  Phase 7b exit. The trivial-phi and ifelse-reachability tests that
  broke during Phase 7's bidirectional attempt are the canaries.

## Migration recipe

Order matters; each numbered step is independently committable.

1. Add `Stage 1` tests — failing because Actions doesn't merge into
   graph yet.
2. Add `$graph->merge` wrappers in Actions.pm. Verify Stage 1 tests
   pass and the trivial-phi test stays green.
3. Re-enable bidirectional traversal in `Graph::nodes()`. Rewrite
   the bidirectional-traversal test. All regression-guard tests
   green.
4. Verify other production singleton consumers (Target/C,
   StructPromotion, BNF/Actions) — add `$graph->merge` wrappers
   where they construct IR. Some may not actually construct IR
   nodes (Audit 1 risk #6); those just need their singleton
   import removed at Stage 2f.
5. Add Stage 2 tests for Context.factory and MOP.factory — failing.
6. Add `$factory` field to Context, thread through `extend()`.
   Stage 2a test passes.
7. Add `$factory` field to MOP::Method and MOP::Sub. Add
   `make`/`make_cfg` proxies. Stage 2b test passes.
8. At MethodDefinition action site, thread `factory => $method->factory`
   into the body's Context. Stage 2c test passes.
9. Bulk-swap Actions.pm readers from `$factory` field to
   `$ctx->factory()`. Verify all tests still green.
10. Fix `SemanticAction::_one_ctx()` placeholder-Start (Stage 2e).
11. Delete Bootstrap singleton (Stage 2f). This compile-fails the
    123 test files. Run the bulk-fix: each test gets a top-of-file
    `my $factory = Chalk::IR::NodeFactory->new;` and the
    `reset_for_testing` call goes away.
12. Clean up StructPromotion (Stage 2g) and Serialize::JSON
    (Stage 2h).

## Acceptance criteria

- `Chalk::IR::Graph::nodes()` follows both `inputs()` and
  `consumers()`.
- `Chalk::Bootstrap::IR::NodeFactory->instance()` does not exist.
- `Chalk::MOP::Method` and `Chalk::MOP::Sub` have `$factory` fields.
- `Chalk::Bootstrap::Context` has a `$factory` field.
- Trivial-phi, ifelse-reachability, and all Phase-7 regression
  tests stay green.
- `t/bootstrap/mop/per-method-factory-isolation.t` passes:
  hash-cons-identical content in two methods produces distinct
  node identities.

## Risks and open questions

1. **`SemanticAction::_one_ctx()` placeholder-Start design.** The
   sketch above (one() carries a sentinel that re-hash-conses into
   the parse's factory on first extend-with-factory) is plausible
   but not specified down to the line. May need a small spike before
   committing to Stage 2.

2. **Sibling Contexts in `ExpressionList` / `ArgumentList`** share
   a parent Context but extend independently. The factory must
   propagate from parent to child; verify this works under both
   `_complete_sa` and `one()` plumbing in `FilterComposite`.

3. **`StructPromotion::rewrite()`** is a post-parse pass that runs
   after the MOP exists. It doesn't have a Context. Question: does
   it take the factory from a ClassInfo, from a MOP::Method, or
   construct its own? Decision deferred to Stage 2g but worth a
   note.

4. **Test-file bulk edit** — 123 files is a lot of mechanical churn.
   Worth scripting (a one-shot Perl script that does the substitution
   per file, run once, reviewed in chunks). Consider doing the bulk
   edit in a single commit titled "chore(tests): drop
   reset_for_testing, use local factories" to keep the diff
   reviewable.

5. **CFG node id collisions.** Today the singleton's `$cfg_counter`
   is monotonic across an entire parse. After Stage 2, each
   factory has its own counter starting at zero. CFG node ids
   like `If#1`, `If#2` from different methods are distinct objects
   today (the singleton increments globally) but become same-id
   in different graphs. If any test or code path keys on CFG id
   string globally, it will now collide. Audit needed — flagged
   for Stage 2f testing.

## Estimated effort

Per the audits:

- **Stage 1:** 4-5 production files, ~60 line-deltas, 2-3 commits.
  Unblocks bidirectional traversal alone.
- **Stage 2:** 4-6 additional production files, ~150 line-deltas,
  4-5 commits, plus ~120 test files in one bulk-edit commit.
- **Total:** medium phase — comparable to Phase 3a-infra
  (commit `885beb87`, 12 files / +927/-629). The test-file bulk
  edit is the volume-cost driver; the production diff is small.

## References

- `docs/plans/2026-04-21-chalk-mop-migration-plan.md` §Phase 7
  (updated with bidirectional-deferral note in commit `13f350d3`)
- `docs/plans/2026-05-21-phase-7-bidirectional-audit.md` (singleton
  call-site map, test contact surface)
- `docs/plans/2026-05-21-phase-7-factory-promotion-audit.md`
  (Context-promotion recipe, MOP graph-owner shape)
- Phase 3a-infra commit `885beb87` — `$graph` / `$scope`
  promotion precedent.
