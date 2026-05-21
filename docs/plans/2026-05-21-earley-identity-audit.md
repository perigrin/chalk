# Earley Identity / Dedup Audit — Phase 7c #2 Regression

**Date:** 2026-05-21
**Context:** Read-only audit dispatched by perigrin to characterize how
Earley's chart-merge step decides whether two derivations are "the same"
ahead of the Phase 7c #2 factory flip.

## Executive summary

The hypothesis is **substantially correct but mis-attributed**. Earley
itself has no identity opinion at all — `lib/Chalk/Bootstrap/Earley.pm`
contains zero `refaddr` calls and uses no `==`/`eq` on semiring values.
Every chart merge delegates to `$semiring->add($existing, $new_value)`
(Earley.pm:992, 1287, 1342, 1422, 1559). The identity behavior is
expressed entirely inside the semiring stack.

The semiring stack *does* use `refaddr` identity, in two distinct
places: (a) `SemanticAction::add` collapses identical refaddrs into a
single survivor (`SemanticAction.pm:414`), and (b) FilterComposite's
`_same_value` and the post-`add` classification use `refaddr` to decide
whether a component semiring abstained or had a preference
(`FilterComposite.pm:190-200`, `:334-339`). Both rely on the *Context*
refaddr, not the IR-node refaddr. So the singleton's hash-cons cache
matters because it makes the *Contexts produced by `_complete_sa`*
share refaddrs when their inputs are identical — not because IR nodes
themselves are compared.

Minimum-viable fix scope: **make the parse use a single typed factory
end-to-end**, by either (1) having `_one_ctx` lazy-seed its factory
from the Actions instance once both are alive, or (2) seeding the
Actions factory into `_one_ctx` via `set_mop`/an analogous setter
before parse start. Option 2 is the smaller change. The Earley dedup
machinery does not need to be touched.

## 1. Earley parse-graph identity

Earley.pm has **no `refaddr` calls and no direct value comparisons.**
The chart merge protocol is exactly:

    if ($self->_chart_has($chart, $pos, $new_cid, $origin)) {
        my $existing_val = $self->_chart_get(...);
        my $merged_value;
        try { $merged_value = $semiring->add($existing_val, $new_value); }
        catch ($e) { die "Ambiguity in ..." }
        $self->_chart_set($chart, $pos, $new_cid, $origin, $merged_value);
    } else {
        $self->_chart_set($chart, $pos, $new_cid, $origin, $new_value);
    }

This pattern is identical at all four sites: `_scan`-time merge
(Earley.pm:1282-1304), Leo resolution (Earley.pm:1338-1351), normal
`_complete` (Earley.pm:1416-1433), and `_advance_from_completed`
(Earley.pm:1555-1571). The Ruby-Slippers EOF path (Earley.pm:990-996)
is the same shape. Earley does not "merge two SA results" itself; it
*hands them to the semiring* and stores the result.

The `_chart_set` writer (Earley.pm:321-331) overwrites whatever was at
that slot. There is no de-dup gate, no comparison; identity collapse,
ambiguity packing, and tie-break all live in the semiring.

## 2. Semiring `add()` semantics

**`SemanticAction::add`** (`SemanticAction.pm:408-425`):

    method add($left, $right) {
        return [$right] if $left->is_zero();
        return [$left]  if $right->is_zero();
        return [$left] if refaddr($left) == refaddr($right);
        return [$left, $right];
    }

This is the only refaddr equality test in the SA layer's `add`. It is
on the **outer Context** values produced by `multiply`, not on the IR
focus inside them. The dedup gate fires when both Earley paths land
the *same Context object*, which happens when:

- `_mul_ctx` (`SemanticAction.pm:119-146`) hash-conses by
  `"mul:" . refaddr($left) . ":" . refaddr($right)`, returning the
  cached Context for identical input children — so identical multiply
  trees collapse.
- `_complete_sa` (`SemanticAction.pm:256-402`) is *not* hash-consed.
  Every call produces a fresh Context. **This is the load-bearing
  asymmetry.**

For `multiply` paths that share input refaddrs, the cache makes
`add()` collapse via the refaddr branch. For paths that go through a
semantic action (any `complete`-annotated multiply), each invocation
allocates a new outer Context — so `add()` falls into
`[$left, $right]` and FilterComposite must disambiguate.

**`FilterComposite::add`** (`FilterComposite.pm:512-549`) dispatches
to `_add_unpacked`, which calls `_filter_compare` and uses `_same_value`
(refaddr or scalar `==`) per-slot. The boolean slot is short-circuited
to `identity_skip` (`FilterComposite.pm:321-325`); the `type` slot is
also skipped. For SA's slot (the focus), the comparison again is on the
**Context** layer's annotations, not on the IR node.

## 3. `add()` callers

Five call sites in Earley.pm, all on `$semiring->add(...)`. The semiring
here is `Chalk::Bootstrap::Semiring::FilterComposite` in production
(see `Chalk::Bootstrap::Earley` constructor; tested via `parse_method`
in `t/bootstrap/mop/method-implicit-return.t`). FilterComposite's
`add` invokes `SemanticAction::add` only for the SA-slot question —
all other answers come from the annotation-layer semirings
(`Boolean`/`Precedence`/`TypeInference`/`Structural`).

The verdict from Earley's perspective: when `add()` returns a single
Context, that Context replaces the chart slot (identity has been
resolved). When it returns a packed-ambiguous Context (children =
both survivors), the chart slot holds the packed Context and
subsequent `multiply` calls distribute over it
(`FilterComposite.pm:226-238`).

Earley itself treats two non-equal Context refaddrs as a single
opaque "merged value." Identity matters only through the lens of the
semiring layer.

## 4. The specific regression case

`method foo() { return 42; }`:

The grammar in `docs/chalk-bootstrap.bnf:34-39` has one
`ReturnStatement` alternative (`/return\b/ WS Expression`). There is
no ambiguity at the `ReturnStatement` rule level. The action
(`Perl/Actions.pm:340-361`) calls
`$factory->make_cfg('Return', inputs => [$control, $value])`.

Why "3 invocations" baseline vs "2 surviving Returns expected, 3
distinct survivors observed" post-flip: **the action method is called
once per `_complete_sa` invocation**, and `_complete_sa` is *not*
hash-consed by design (`SemanticAction.pm:251-254` comments). So if
the same ReturnStatement span gets re-completed by two distinct
Earley waiting items (e.g. via `WS` nullable expansion, or via
`SimpleStatement` ambiguity at the outer Block — `SimpleStatement`
has two alternatives at `docs/chalk-bootstrap.bnf:34-35`), the
action fires once per completion.

Under the singleton: both `make_cfg('Return', ...)` calls go through
the same `Chalk::IR::NodeFactory` instance (Bootstrap's `_new_factory`,
`Bootstrap/IR/NodeFactory.pm:65-78` delegating to one shared
`Chalk::IR::NodeFactory`). That factory's `cfg_counter` is shared.
Per `IR/NodeFactory.pm:207-216`, `make_cfg` allocates a fresh node
with a monotonically incremented id every time. So even under the
singleton the two Returns *are* distinct objects — `Return#1` and
`Return#2` say. The "2 vs 3" claim therefore is **not about
factory-level dedup**. Earley's chart already collapsed two of three
upstream Contexts before the action fired again, via the `_mul_ctx`
cache (`SemanticAction.pm:119-146`).

After the flip, the per-Actions `$typed` factory has its own
`cfg_counter` and its own `%cache`. Each method invocation still
allocates a fresh Return (counters now per-factory). The difference is
**not the IR node identity** — those are always distinct refaddrs —
but the *Context* identities, because:

- `_complete_sa`'s result Context wraps the IR focus.
- The focus is now from a different factory than the surrounding
  control inputs (which come via `_ctx_control` — see point 5).
- `_mul_ctx` hash-cons keys (`SemanticAction.pm:120`) are based on
  child refaddrs, so any divergence in how the children's focuses
  were built propagates up.

The "extra invocation" likely comes from one of:

(a) An Earley waiting item that previously found a cached SA Context
in its add() dedup path now sees a non-equal Context (different
refaddr because a downstream `_complete_sa` re-allocated), so add()
falls into `[$left, $right]` and FilterComposite packs both. The
distribute-over-pack rule in `FilterComposite::multiply:226-238`
then causes the action to fire **once per unpacked left** — three
times instead of two.

(b) `_one_ctx`'s factory (allocated at SA.pm:82) being a *different*
`Chalk::IR::NodeFactory` instance than Actions's `$typed`. Action
methods don't read `$ctx->factory()` today, so this is currently
inert — but after the flip, the `Start` made at SA.pm:73 still
comes from the Bootstrap singleton, while `make_cfg('Return', ...)`
would come from `$typed`. Their CFG counters are independent,
giving an `Start#1`, but the Start refaddr is stable across
re-uses (it's stored in the one() Context's scope), so this is
not the dominant factor.

The probable dominant factor is (a): action result Contexts that
*used to be* refaddr-equal across two completion paths are now
refaddr-distinct, because `make_cfg` allocates from a different
factory and `_complete_sa` builds a new outer Context per call.

## 5. `_one_ctx`'s factory and Actions's factory

Two distinct `Chalk::IR::NodeFactory` instances are live during a
parse today:

- `_one_ctx`'s `factory => Chalk::IR::NodeFactory->new()`
  (`SemanticAction.pm:82`), threaded into every Context as it bubbles
  up through `_mul_ctx` and `_complete_sa`.
- Actions's `field $typed = Chalk::IR::NodeFactory->new()`
  (`Perl/Actions.pm:78`), used directly for ~20 node-construction
  sites (Call, VarDecl, AnonSub, TryCatch, ExpressionList, …).
- Plus the Bootstrap singleton, used by `$factory->make` /
  `$factory->make_cfg` for Start/Return/Constant — its internal
  `_new_factory` is also a `Chalk::IR::NodeFactory`, a **third**
  distinct instance.

No code path reads `$ctx->factory()` today. The field is plumbed but
inert (search confirms only `SemanticAction.pm` and
`FilterComposite.pm` reference it — and they only propagate it).

The Bootstrap singleton's `_new_factory` field is the *only* factory
that all `$factory->make_cfg('Return', ...)` calls share, because
`Bootstrap::IR::NodeFactory::instance()` is a class-level singleton
(`Bootstrap/IR/NodeFactory.pm:22, 52-55`). Two Actions instances in
the same process therefore share that `_new_factory` instance. After
the Phase 7c #2 flip, each Actions instance points `$factory` at
its **own** `$typed`, breaking that sharing.

Cross-factory cache visibility: there is none. Each
`Chalk::IR::NodeFactory` has a private `field %cache`
(`IR/NodeFactory.pm:119`). Looking up a node by `content_hash` in
factory A will never find a node constructed via factory B. The
graph-level `%cache` (`Graph.pm:20`) is the only cross-factory dedup
surface, and it only sees nodes that have been explicitly
`$graph->merge()`'d.

## 6. Cross-factory identity expectations

`Perl/Actions.pm` uses `refaddr` in three places:

- `_finalize_body_graph` (`Actions.pm:879, 882`): keys
  `$schedule` by `refaddr` of IR nodes for control-flow annotations.
  This requires the **same refaddr** to be reachable both from the
  Context (during finalize) and from the graph walk (during codegen).
  After the flip, both sides go through `$typed`, so as long as the
  same `$typed` instance is used throughout, this stays correct.
- `_fix_postfix_chain` etc. (`Actions.pm:1437, 1442, 1503, 1520`):
  refaddr comparisons on control nodes to detect chain identity. Same
  invariant: requires factory-local consistency.

None of these compare IR nodes from *different* factories. They all
expect "the factory I built this from is the factory the graph
walks." The singleton happened to satisfy this trivially. Per-Actions
factory satisfies it too — *if* there's just one per parse, and *if*
all node construction paths route through it.

Semiring-layer code (`SemanticAction.pm`, `FilterComposite.pm`)
contains `refaddr` comparisons on **Context** objects, not IR nodes
(`SA.pm:120, 414`; `FC.pm:194, 334, 337`). These are sensitive to
Context identity, which is in turn sensitive to focus identity
(through `_mul_ctx`'s refaddr-keyed cache).

## 7. Earley merge protocol for completions

When the same rule completes at the same `(pos, core_id, origin)` via
two different waiting items, Earley:

1. Re-runs `multiply(waiting_value, completed_value)` per waiter
   (`Earley.pm:1407, 1547`).
2. Each multiply produces a new Context. The action fires inside
   `_complete_sa` if `right` has `complete=true` — see
   `SemanticAction::multiply:242-246`.
3. Earley calls `$semiring->add($existing, $new_value)` to merge them
   into the chart slot (`Earley.pm:1422, 1559`).

Whether `add()` dedups them depends on the SA-Context refaddr (via
`SemanticAction::add:414`) — same Context → collapse; different
Contexts → ambiguity-pack via FilterComposite. With `_complete_sa`
non-hash-consed by design, each action invocation produces a distinct
Context, and Earley therefore sees them as different unless the
upstream multiply tree gave them refaddr-equal positions through
`_mul_ctx`'s cache.

So the dedup is **based on the Earley-item's stored Context value,
not the item's state**. Two waiting items that completed via the
same rule at the same span will yield two refaddr-different
Contexts, unless the multiply tree was already cached.

## What fix scope looks like

**Option A — Single per-parse typed factory, seeded into `_one_ctx`.**
Add a class-method setter to `SemanticAction` analogous to `set_mop`
(SA.pm:209): `set_factory($factory)`. Have the parser entry point
(`Chalk::Bootstrap::Earley::parse` or its caller) inject the
Actions's `$typed` into the SA before parsing starts. `_one_ctx`
reads this stash instead of allocating a fresh one (SA.pm:82). Cost:
~10 lines. Trade-off: keeps Stage 2c's promise that `_one_ctx`
carries a factory, just makes it the same one Actions holds.

**Option B — Actions reads `$ctx->factory()` everywhere.** Bulk-edit
Actions.pm: every `$factory->make(...)` and `$factory->make_cfg(...)`
becomes `$ctx->factory()->make(...)`. Then the factory is whatever
`_one_ctx` seeded. Cost: ~60+ sites in Actions.pm. Trade-off:
matches the Phase 7b plan's Stage 2d (line 154-157 of the phase 7b
plan), but is the larger change. Also: `_finalize_body_graph` and
the action methods that pass `$factory` to helpers
(e.g. `_make_const($factory, ...)`) need refactoring.

**Option C — Change Earley to use content equality.** Replace the
refaddr branch in `SemanticAction::add:414` with content-based
equality on the focus IR node (content_hash for IR nodes, recursive
for non-leaf Contexts). This is invasive and breaks the
"Contexts are opaque to Earley" abstraction. Not recommended; the
identity-via-hash-cons design is correct, the problem is just that
the hash-cons spans different factories.

**Option D — Have `_finalize_body_graph` dedup ambiguous Returns.**
After collecting `@returns`, run them through `$graph->merge` (which
keys by `content_hash`, `Graph.pm:49-57`). Two `Return#1` and
`Return#2` nodes with identical inputs would collapse to one cache
entry. This is **the surgical fix that doesn't touch Earley or the
semiring**, but it papers over the Earley-level duplication; it
leaves the chart carrying two ambiguity-packed Contexts even though
they encode the same Return. Acceptable as a stopgap; not a clean
resolution of the underlying identity question.

**Recommended:** Option A. It's small, it preserves the Phase 7b/c
architecture, and it makes the "one parse, one typed factory"
invariant explicit. Option D is a defensible safety net to layer on
top.

## Risks I noticed

1. **`_one_ctx` is a class-method singleton.** `$_one_singleton` is a
   class lexical (`SA.pm:45`) shared across all `SemanticAction`
   instances. If two parses run concurrently (testing or threading),
   they share the same singleton. `reset_cache` (SA.pm:170-174) clears
   it. After Option A, `set_factory` would need to invalidate the
   singleton too (mirroring how `set_mop` does at SA.pm:209).

2. **`_one_ctx`'s Start node is built via the Bootstrap singleton**
   (`SA.pm:72-73`). After the flip, the Start passed into Scope and
   thence into action methods' `_ctx_control` fallback (`Actions.pm:357,
   905, 1263, …`) is from the Bootstrap singleton, while Returns
   constructed by Actions are from `$typed`. Two factories' nodes
   coexist in the same graph. `Graph::merge` will dedup by
   `content_hash` (`Graph.pm:49-57`), so identical-content Starts
   collapse — but consumer pointers added at construction
   (`IR/NodeFactory.pm:202` via `_register_consumers`) attach to the
   *original* node, not the merged-into representative. Bidirectional
   walk's membership filter (`Graph.pm:119-125`) is designed for this
   case, but the cross-factory consumer-pointer pattern wasn't part of
   Phase 7b's safety argument. Worth verifying with a targeted probe.

3. **Schedule annotations key by refaddr** (`Actions.pm:879, 882`).
   If Option D collapses two Returns into one via `Graph::merge`, the
   schedule entry pointing at the *replaced* refaddr becomes stale.
   `_finalize_body_graph` doesn't currently re-key the schedule after
   merge.

4. **`reset_for_testing`** (`Bootstrap/IR/NodeFactory.pm:59-62`) is
   still referenced by ~120 test files per the Phase 7b plan
   (line 180-185). Whatever fix lands must not break those callers
   until the bulk-edit happens.

5. **`_complete_sa` is intentionally not hash-consed** (`SA.pm:251-254`
   comment). Any "minimum-viable fix" that introduces hash-cons there
   risks side-effect actions (`update_scope`, `update_graph`,
   `update_annotations`) sharing pending-state across logically
   distinct invocations. Do not pursue that route.

6. **Counter divergence under Option A.** With one shared `$typed`
   for the whole parse, `cfg_counter` is monotonic across all methods
   in the file. Today (per Phase 7b plan risk #5, line 339-346) the
   singleton already behaves this way, so no behavioral change. But
   the per-Actions factory style (with `reset_for_testing` clearing
   state) would have given each test a per-test counter. Worth a
   sanity sweep on golden files that hardcode CFG ids.
