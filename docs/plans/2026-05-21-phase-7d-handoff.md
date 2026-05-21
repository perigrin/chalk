# Phase 7d Handoff — for the next session

**Date:** 2026-05-21
**HEAD on `pu`:** `e521f127`
**Status:** Phase 7d complete. Bootstrap singleton retired. Bidirectional
`Graph::nodes()` shipping. Per-parse factory ownership is the architecture.

## What just landed (Phases 7 → 7b → 7c → 7d)

Spans commits `5df4f5f4..e521f127` on `pu`. The migration arc closed a
14-day investigation into why bidirectional traversal in
`Chalk::IR::Graph::nodes()` couldn't ship.

**Root cause traced:** the Bootstrap singleton's process-wide
`%node_cache` made hash-consed nodes' `consumers` lists cross graph
boundaries. Bidirectional walking would pull in foreign-graph nodes.

**Solution shipped:**
1. **Phase 7b** — transitive seed of `_finalize_body_graph` makes the
   graph's own `%cache` the membership authority; `Graph::nodes()`
   walks both inputs and consumers with a cache-membership filter.
2. **Phase 7c #1** — typed `Chalk::IR::NodeFactory::make()` becomes
   Bootstrap-API-compatible (accepts every op, translates named
   keywords to inputs via `%INPUT_SPECS`).
3. **Phase 7d Step 1** — `SemanticAction::set_factory($f)` injects
   Actions's typed factory into `_one_ctx`; `$ctx->factory`, Actions's
   `$typed`, `$factory`, and `_one_ctx`'s Start are all the same
   instance per parse.
4. **Phase 7d Steps 2-3** — Actions.pm hot path off the singleton.
   `$factory = $typed` in ADJUST; `_one_ctx`'s Start built via the
   parse factory.
5. **Phase 7d Step 4** — four production consumers migrated in parallel
   (DCE, StructPromotion, Target/C, BNF/Actions). 127 test files
   migrated in three parallel agents.
6. **Phase 7d Step 4.8 finale** — `lib/Chalk/Bootstrap/IR/NodeFactory.pm`
   deleted entirely. Zero singleton references anywhere in lib/, t/,
   script/.

## Verification

- 593 tests across `t/bootstrap/{ir,mop,context,optimizer,struct-promotion}/`
  green
- Pre-existing baseline failures unchanged (assignment-scope 11+26,
  c-self-call-optimization 5-8, comonad-threading 5,
  codegen-builtin-hash-arg 4, c-direct-cross-class 21-23,
  codegen-pipeline)
- The `method foo() { return 42; }` Phase 7c #2 regression test now
  passes (1 Return, not 3)
- Byte-compatibility goldens (`t/fixtures/codegen-goldens/`) intact

## Architectural facts now load-bearing

- **`Chalk::IR::NodeFactory` is THE factory.** Per-instance, hash-cons
  by `content_hash`, CFG-counter for fresh-allocate ops. Permissive
  `make()` accepts every op with `%INPUT_SPECS` keyword translation.
- **`SemanticAction::set_factory`** is how Actions injects its factory
  into the parse. Called from Actions's ADJUST. Mirrors `set_mop`.
- **`MOP::Method` and `MOP::Sub`** each own a `$factory` field parallel
  to `$graph`. `make`/`make_cfg` delegators provided.
- **`Graph::nodes()` is bidirectional** with cache-membership filter on
  consumer-following. Inputs followed unconditionally; consumers
  followed only when `$n->id` or `$n->content_hash` is in `%cache`.

## What's NOT in scope yet — Phase 8+ territory

Per `docs/plans/2026-04-21-chalk-mop-migration-plan.md` (updated at
the bottom of this work):

- **Phase 8: Documentation.** Update `ARCHITECTURE.md` and
  `CONTRIBUTING.md` to reflect the MOP as a first-class layer.
  The plan section is at the end of the master plan; no detailed
  work yet.
- **Codegen reads MOP directly.** Currently `Target/Perl.pm` and
  others still consume metadata-struct `->body()` arrayrefs.
  Migrating to `$mop->classes->methods->graph->nodes` walking is
  Phase 9 / superseded plan territory.
- **`compat_class` final removal.** Field still on
  `Chalk::IR::Node` for legacy `->class()` test reads. Production
  setters stripped.
- **Info struct deletion.** `ClassInfo`/`MethodInfo`/`SubInfo`/
  `UseInfo`/`Program` still exist; codegen reads them.

## Pre-existing baseline failures (not Phase 7d's responsibility)

These have been carried through unchanged across the entire 14-day arc:

- `t/bootstrap/assignment-scope.t` tests 11, 26 — BinaryExpr→Assign
  class mismatch in SA pipeline (pre-Phase-7d)
- `t/bootstrap/comonad-threading.t` test 5 — pre-Phase-7d
- `t/bootstrap/codegen-builtin-hash-arg.t` test 4 — pre-Phase-7d
- `t/bootstrap/c-self-call-optimization.t` tests 5-8 — pre-Phase-7d
- `t/bootstrap/c-direct-cross-class.t` tests 21-23 — pre-Phase-7d
- `t/bootstrap/codegen-pipeline.t` — exits 255 (no plan output)

Each is a real failure but unrelated to Phase 7d's factory work.

## Suggested next-session prompt

See bottom of this file.

---

## Kickoff prompt for next session

```
We just closed Phase 7d on `pu` at e521f127. Bootstrap singleton retired,
bidirectional Graph::nodes() ships, per-parse factory ownership is the
architecture. Memory entries written at
~/.claude/projects/-home-perigrin-dev-chalk/memory/phase_7d_factory_unification_complete.md
and feedback_parallel_agents_for_bulk_migration.md.

Read docs/plans/2026-05-21-phase-7d-handoff.md for the full context dump.

Pick the next move. Options I'm considering:

(A) Phase 8 documentation. ARCHITECTURE.md and CONTRIBUTING.md are stale
    on factory/Bootstrap-singleton material. Produce a punch list at
    docs/plans/2026-05-22-phase-8-docs-punchlist.md before writing any
    docs — I want to see what needs to change before committing to the
    update.

(B) Triage the pre-existing baseline failures. Seven test failures
    (assignment-scope 11+26, c-self-call-optimization 5-8,
    comonad-threading 5, codegen-builtin-hash-arg 4,
    c-direct-cross-class 21-23, codegen-pipeline) have been carried
    through unchanged for two weeks. Each is real but unrelated to
    the factory work. Triage: categorize each as bug-fix /
    test-update / known-deferred-with-issue-link. Output an
    issue-list at docs/plans/2026-05-22-baseline-failure-triage.md.

(C) Codegen reads MOP directly. The blocking item between Phase 7d
    and a full MOP-as-first-class architecture is migrating
    Target/Perl and friends off metadata-struct ->body() reads.
    Audit the surface (probably another parallel-agent dispatch
    candidate) before committing scope.

Start by running `git log --oneline 5df4f5f4..e521f127` to see what
shipped, then pick a path and execute. Default to (A) — docs drift
is the most likely casualty of all this work.
```
