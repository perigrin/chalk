# Phase 7d — Factory Unification and Singleton Retirement

**Status:** PLANNED, 2026-05-21
**Entry:** Phase 7c #1 complete (commit `e8b51201` on `pu`).
**Exit:** Bootstrap singleton retired, one typed factory per parse.

## Background

Phase 7c #2 attempted to repoint Actions.pm's `$factory` at the typed
factory and ran into an Earley dedup regression: identical-content
ReturnStatement invocations from ambiguous parse paths produced 3
distinct Return objects where baseline produced 2.

Two audits dated 2026-05-21 characterize the issue:

- `docs/plans/2026-05-21-earley-identity-audit.md` — the regression is
  *not* about IR-node identity (those are always distinct refaddrs);
  it's about **Context** identity. `_mul_ctx` hash-cons keys by child
  refaddrs (SA.pm:120), so factory divergence propagates upward.
  `_complete_sa` is non-hash-consed by design (SA.pm:251-254), so two
  ambiguous completion paths always produce distinct outer Contexts,
  and `SemanticAction::add`'s refaddr branch (SA.pm:414) can't collapse
  them.
- `docs/plans/2026-05-21-factory-unification-audit.md` — three typed
  factories live during a parse today: `_one_ctx`'s, Actions's `$typed`,
  and Bootstrap singleton's `_new_factory`. None share state. No
  Actions site reads `$ctx->factory()`; Stage 2c's plumbing is inert.

## Goal

Unify the parse to use a single typed factory end-to-end. With one
factory:
- `$ctx->factory()` returns the same instance Actions reads as
  `$typed`.
- Bootstrap singleton's `_new_factory` becomes unused.
- IR node refaddrs are deterministic across the parse (no cross-factory
  divergence).
- `SemanticAction::add`'s refaddr branch collapses ambiguous completion
  paths that previously diverged.
- The Earley regression observed in Phase 7c #2 resolves naturally.

## Approach — four steps

### Step 1: Connect the factories (Option A from Earley audit)

Add a class-method setter `SemanticAction::set_factory($f)`, analogous
to `set_mop` (SA.pm:209). Have the parser-build wiring inject Actions's
`$typed` into the SA *before* parse start. `_one_ctx` reads the
stashed factory instead of allocating its own (SA.pm:82).

**Net effect:** `$ctx->factory()` now IS Actions's `$typed` instance.
Stage 2c's plumbing becomes live — but no Actions code reads it yet.

**Files touched:**
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — add
  `$_factory` class lexical, `set_factory($f)` setter, modify
  `_one_ctx` to read `$_factory` or allocate.
- `lib/Chalk/Bootstrap/Perl/Actions.pm` (or test pipeline) — call
  `SA::set_factory($typed)` at parser-build time.

**TDD:** test that `$ctx->factory()` and Actions's `$typed` are
the SAME refaddr after parser setup.

**Cost:** ~15-20 lines.

### Step 2: Bulk-flip Actions.pm to `$ctx->factory()` (Path b from
unification audit)

With Step 1 guaranteeing `$ctx->factory() == $typed`, every
`$typed->make(...)` site can read `$ctx->factory()->make(...)` and
get the same factory instance. Bulk-edit the 33 typed sites.

**Net effect:** Actions reads its factory from Context. The `$typed`
field becomes redundant; `field $typed` can be removed (or kept as a
fallback during transition).

**TDD:** existing tests pass; no regression. The
`per-parse-factory-thread.t` test continues to assert factory threading.

**Cost:** ~35 line edits.

### Step 3: Flip the `$factory` field (Path b extended)

For the 61 `$factory->make(...)`/`$factory->make_cfg(...)` sites in
Actions.pm currently using the Bootstrap singleton, route through
`$ctx->factory()` too. Since the typed factory now accepts every op
Bootstrap's make() accepted (Phase 7c #1), this is type-compatible.

**Critical check:** verify the Phase 7c #2 regression does NOT recur.
With Step 1 unifying factories, the Earley dedup should collapse
ambiguous paths via Context identity as it did with the singleton.

**Net effect:** Actions no longer reads the Bootstrap singleton at all.

**TDD:** specifically test `method foo() { return 42; }` produces 1
Return (the test that failed Phase 7c #2).

**Cost:** ~60 line edits.

### Step 4: Retire the Bootstrap singleton

Once Steps 1-3 land cleanly and no Actions site reads
`Chalk::Bootstrap::IR::NodeFactory->instance()`, delete the singleton
class.

**Other singleton consumers** (per Phase 7c audits):
- `Target/C.pm:131` — accept factory parameter
- `StructPromotion.pm:491` — accept factory parameter (Stage 2g)
- `BNF/Actions.pm:15` — verify or migrate
- `DCE.pm:45` — already accepts factory, just remove fallback
- `Serialize/JSON.pm:216` — accept factory parameter (Stage 2h)
- `SemanticAction.pm:73` — `_one_ctx` Start placeholder (Stage 2e from
  Phase 7b plan)

Plus the ~123 test files calling `reset_for_testing` (Phase 7b plan
§Out of scope, line 180-185).

**Cost:** large — ~5 production files plus ~120 test edits. Defer
the test bulk-edit to a final cleanup commit.

## Acceptance criteria

- `$ctx->factory()` and Actions's typed factory are the same instance.
- Actions.pm contains no references to
  `Chalk::Bootstrap::IR::NodeFactory->instance()`.
- `method foo() { return 42; }` parses to one Return in the method's
  graph.
- All 513 tests across `t/bootstrap/{ir,mop,context,optimizer}/` stay
  green.
- Phase 7b's bidirectional-traversal regression-guard tests
  (trivial-phi, ifelse-reachability, control-chain) stay green.

## Risks

1. **`_one_ctx`'s class-level singleton state.** `$_one_singleton`
   is a class lexical. After Step 1's `set_factory`, the singleton
   must be invalidated (mirroring `set_mop`'s behavior at SA.pm:209).

2. **Bootstrap singleton's `Start` at SA.pm:73** is still constructed
   in `_one_ctx` post-Step 1. The Earley audit flags this: after
   Steps 1-3, Returns from Actions and the Start from `_one_ctx`
   coexist in the same graph from different factories. `Graph::merge`
   handles content-hash dedup, but consumer-pointer registration
   happens at construction time on the original node, not the
   merged-into representative. Phase 7b §Stage 2e's placeholder-Start
   sentinel is the proper fix; defer until needed.

3. **Schedule annotations key by refaddr** (Actions.pm:879, 882).
   If any deduplication happens between schedule-key creation and
   schedule-consumer reading, the refaddr can become stale. Steps
   1-3 don't introduce new dedup; just factory unification. Should
   be safe but worth verifying.

4. **123 test files calling `reset_for_testing`.** Step 4 deletes
   the method, breaking compilation. Bulk-edit recipe: script all
   test files at once, one commit, easy to review.

5. **CFG counter determinism.** With one shared `$typed` for the
   whole parse, `cfg_counter` is monotonic across all methods in
   the file. Today's singleton already behaves this way; no
   behavioral change. But golden files with hardcoded CFG ids
   should be spot-checked.

## References

- `docs/plans/2026-05-21-phase-7b-factory-promotion.md` — parent
  plan; Stages 2d/2e/2f were the original singleton-retirement
  scope, now superseded by this plan.
- `docs/plans/2026-05-21-earley-identity-audit.md` — Earley dedup
  semantics, "Option A" recommendation.
- `docs/plans/2026-05-21-factory-unification-audit.md` — three-factory
  divergence, "Path b" recommendation.
- Phase 7c #1 commits: `aefdb0fe` (Start/Return in DATA_CLASSES),
  `ed3aa4a0` (If/Proj/Region/Loop/Phi in permissive make()).
