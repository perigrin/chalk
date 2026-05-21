# Phase 7 Factory-Promotion Audit

## Executive summary

**Verdict — promote `$factory` to Context: SMALL.**

The typed `Chalk::IR::NodeFactory` is already instance-based (per-instance
`field %cache`), so the only architectural piece needed for per-graph
ownership is *thread it through*. Context already grew `$graph` and `$scope`
in Phase 3a-infra (commit `885beb87`); adding `$factory` slots in next to
them with the same shape (one `:param :reader` field, one entry in the
`extend()` opts plumbing). The Phase 3a-infra commit touched 12 files for
about 1,500 line-deltas, but the bulk of that cost was *deleting the
old cfg side-channel and migrating tests off it* — none of that
collateral exists for the factory because there is no factory side-channel
to remove. MOP::Method and MOP::Sub already own a `$graph` field; an
adjacent `$factory` is a parallel one-line addition. Today there are only
**2 production `Chalk::IR::NodeFactory->new` sites** (Actions.pm:78,
StructPromotion.pm:41) and one transitional one inside the Bootstrap
singleton shim (NodeFactory.pm:66); test sites (42 occurrences across 19
files) construct local factories and would not need to change. The single
real complication is that `Chalk::Bootstrap::Perl::Actions` constructs the
typed factory once in `ADJUST` and stores it in a `field $typed`, then
references that field from dozens of methods — promoting `$factory` to
Context means action methods must read it from `$ctx` instead of `$typed`,
which is a mechanical edit but a wide one.

## 1. `Chalk::IR::NodeFactory` (typed) — instance vs singleton

Instance-based. `lib/Chalk/IR/NodeFactory.pm:104-106`:

```
class Chalk::IR::NodeFactory {
    field %cache;
    field $cfg_counter = 0;
```

The cache is a field (per-instance), not a `my %cache` (process-wide).
There is **no `reset_for_testing` or singleton accessor**. Every caller
allocates a fresh factory via `->new`. Contrast with
`lib/Chalk/Bootstrap/IR/NodeFactory.pm:22,52-62`, which holds a `my
$instance` singleton and exposes `instance()` plus `reset_for_testing()`.

`make()` (`lib/Chalk/IR/NodeFactory.pm:124-140`) registers consumers
via the same `_register_consumers` helper as Bootstrap
(`lib/Chalk/IR/NodeFactory.pm:108-122` vs
`lib/Chalk/Bootstrap/IR/NodeFactory.pm:136-152`). Both arrays-of-nodes
and single-node inputs are handled; both call `$input->add_consumer($node)`.
Behaviorally equivalent registration.

## 2. Consumers of `Chalk::IR::NodeFactory->new`

Production code (3 sites total):

| File | Line | Storage | Per-graph owner? |
|---|---|---|---|
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | 78 | `field $typed` on Actions object | No — one factory shared across the entire parse |
| `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` | 41 | `field $typed` on the pass object | No — per-pass, not per-graph |
| `lib/Chalk/Bootstrap/IR/NodeFactory.pm` | 66 | `field $_new_factory` inside the singleton shim, lazy via `_ensure_new_factory` | No — proxied through the process-wide singleton |
| `lib/Chalk/IR/Serialize/JSON.pm` | 216 | local lexical in deserializer | No — one factory per load, not attached to a MOP |

Test sites: 42 `Chalk::IR::NodeFactory->new` calls across 19 test files
under `t/bootstrap/`. All construct local factories inside tests; none
attach them to a MOP::Method or MOP::Sub.

**No production code today stores the factory on a per-graph owner.** The
closest is Actions.pm's `field $typed`, which is per-Actions-object (and
the parser holds exactly one Actions instance), not per-graph.

## 3. `Chalk::Bootstrap::Context` field declarations

From `lib/Chalk/Bootstrap/Context.pm:8-19`:

```
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

**`$factory` is NOT a Context field today.** It would slot in at line 20,
adjacent to `$graph` and `$scope`, with the same `:param :reader` shape
and a `= undef` default. The placement is obvious and follows the existing
ordering convention (MOP-related fields at the tail).

## 4. Context update API

Context itself exposes a single update entry-point: `extend($f, %opts)`
(`lib/Chalk/Bootstrap/Context.pm:29-44`), which threads every field through
an `exists $opts{X} ? $opts{X} : $X` chain. There is **no `with_graph` /
`with_scope` / `with_*` family** on Context. The `extend()` opts hash is
the universal mutation interface.

Side-channel updates live on `Chalk::Bootstrap::Semiring::SemanticAction`:

- `update_scope($scope)` — `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:162`
- `update_annotations($data)` — line 171
- `update_graph($graph)` — line 180

These set `$_pending_*_update` slots; `_complete_sa` applies them after the
action returns. Adding `$factory` would either need a sibling
`update_factory()` here or — more naturally — flow through
`extend(graph => ..., factory => ...)` directly, since factory identity
should track graph identity 1:1.

A `with_factory` method would be a **novel pattern** — none of the existing
fields have a dedicated wither. Don't add one; extend the `extend()` opts
list instead.

## 5. `$graph` promotion precedent

Single commit: **`885beb87`** "refactor(mop): Phase 3a-infra — promote
scope/graph to Context fields, delete cfg side-channel" (2026-04-26).

`git show --stat 885beb87` summary:

```
 lib/Chalk/Bootstrap/Context.pm                  |   6 +-
 lib/Chalk/Bootstrap/Perl/Actions.pm             | 311 ++++++++++----------
 lib/Chalk/Bootstrap/Scope.pm                    |  34 ++-
 lib/Chalk/Bootstrap/Semiring/FilterComposite.pm |   6 +
 lib/Chalk/Bootstrap/Semiring/SemanticAction.pm  | 366 ++++++++++++++----------
 t/bootstrap/assignment-scope.t                  |  88 +++---
 t/bootstrap/cfg-statements.t                    | 219 ++++++++------
 t/bootstrap/cfg-try-catch.t                     |  45 +--
 t/bootstrap/context-cfg-annotation.t            | 257 +++++++----------
 t/bootstrap/context/graph-scope-fields.t        |  91 ++++++
 t/bootstrap/context/scope-containment.t         |  58 ++++
 t/bootstrap/scope/control-input.t               |  75 +++++
 12 files changed, 927 insertions(+), 629 deletions(-)
```

Net +298 lines, 12 files. The Context.pm change was 6 lines; most of the
cost was Actions.pm refactoring (311 lines touched, mostly *migrations
from `cfg`/`update_cfg`/`set_cfg_state` to scope-passing* — work that has
no analog for the factory) and test migrations (six test files, ~700
lines of churn for the same reason).

A factory-only promotion has none of the side-channel-deletion cost. The
expected diff shape: Context.pm +3 lines, Actions.pm ADJUST initialization
moves and the field becomes a parameter sourced from Context, plus one
small `extend(factory => ...)` plumbing addition in
SemanticAction/FilterComposite to propagate it through `_complete_sa` and
`one()`/`_wrap_sa_result()`. Realistic ceiling: 4-6 production files, ~150
line-deltas, no test migrations required because tests construct local
factories.

## 6. MOP::Method and MOP::Sub graph ownership

`lib/Chalk/MOP/Method.pm:10-18`:

```
class Chalk::MOP::Method {
    field $name             :param :reader;
    field $class            :param :reader;
    field $params           :param :reader = [];
    field $return_type      :param :reader = undef;
    field $graph            :param :reader = Chalk::IR::Graph->new;
    field $body             :param :reader = [];
    field $lexical_bindings :param        = [];
```

`lib/Chalk/MOP/Sub.pm:9-15`:

```
class Chalk::MOP::Sub {
    field $name        :param :reader;
    field $class       :param :reader;
    field $params      :param :reader = [];
    field $return_type :param :reader = undef;
    field $graph       :param :reader = Chalk::IR::Graph->new;
    field $body        :param :reader = [];
```

**Neither has a `$factory` field.** Adding one is parallel to the existing
`$graph` field — same shape (`:param :reader`), same default style
(`Chalk::IR::NodeFactory->new`), placed immediately after `$graph`. Note
that `merge`/`next_cfg_id` on both classes delegate to the graph; if the
factory moves into the MOP, the same delegation pattern would extend to a
`make`/`make_cfg` proxy on the metaobject.

There is an architectural awkwardness here that the audit must surface:
`Chalk::IR::Graph` already maintains its own `%cache` and `$cfg_counter`
(`lib/Chalk/IR/Graph.pm:20-24,49-77`) *separately* from the factory's
cache. That is, hash-cons-on-merge happens twice today: once in the
factory (`%cache` keyed by content_hash) and once in the graph (`%cache`
keyed by content_hash, re-checked at `merge()`). Promoting the factory
to per-graph ownership would let the graph's cache be the single source
of truth and the factory's `%cache` could collapse — but that's a Phase 7+
follow-up, not part of the promotion itself. Worth a comment in the
migration brief.

## 7. Ambiguity, orphan nodes, and `unmerge`

There is **no infrastructure today for cleaning up nodes built by losing
parse alternatives.** Evidence:

- `Chalk::IR::Graph::unmerge` (`lib/Chalk/IR/Graph.pm:63-71`) exists, but
  every production caller uses it for *intentional in-graph rewrites*,
  not ambiguity cleanup:
  - `lib/Chalk/Bootstrap/Perl/Actions.pm:1473,1496` — Block-level
    control-chain fixup rebuilding VarDecl/Return with corrected control
    inputs and dropping the bare versions.
  - `lib/Chalk/Bootstrap/Perl/Actions.pm:2177` — AssignmentExpression
    refining a bare VarDecl into one with an `init`, dropping the bare.
- `Chalk::IR::Node::remove_consumer` (`lib/Chalk/IR/Node.pm:31`) is called
  by `Loop` and `Phi` constructors when swapping inputs after lazy
  patching (`lib/Chalk/IR/Node/Loop.pm:14`,
  `lib/Chalk/IR/Node/Phi.pm:20`) and by DCE
  (`lib/Chalk/Bootstrap/Optimizer/DCE.pm:66,70`).
- The only ambiguity-resolution code path is FilterComposite's
  packed-ambiguous Context: `_is_packed` /
  `is_ambiguous=true` (`lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:163-182,
  445-478`). When ambiguity survives all filters, both alternatives are
  packed into a single Context and surface as a structured error if they
  reach the Program rule. **No node-deletion happens** — the losing IR
  subgraph is left in whichever factory it was built into. With the
  Bootstrap singleton, this means orphan nodes accumulate in the
  process-wide cache.
- No comment in `lib/Chalk/Bootstrap/Perl/Actions.pm` mentions
  ambiguity/losing/orphan. `grep -n "ambig\|losing\|orphan"` returns
  zero matches in that file beyond `is_ambiguous` flag setters elsewhere.

This is the strongest *positive* argument for promoting `$factory` to
Context: a per-graph factory means a losing alternative's factory is
simply discarded with its Context, taking its orphan nodes with it.
Today there is no GC path for orphans.

## What's already done vs. what's missing

| Capability | Today | After promotion |
|---|---|---|
| Typed NodeFactory is instance-based | DONE (`field %cache`) | DONE (no change) |
| Context has `$graph` field | DONE (Phase 3a-infra) | DONE |
| Context has `$scope` field | DONE (Phase 3a-infra) | DONE |
| Context has `$factory` field | MISSING | ADD |
| `extend()` threads factory through opts | MISSING | ADD (one line) |
| MOP::Method has `$factory` field | MISSING | ADD |
| MOP::Sub has `$factory` field | MISSING | ADD |
| Actions.pm reads factory from Context | NO (reads `$typed` field) | YES |
| StructPromotion.pm reads factory from Context | NO | YES (or keep per-pass — pass doesn't run inside parse) |
| Per-graph factory cache | NO (Actions has one shared factory across entire parse) | YES |
| Orphan-node cleanup on losing alt | NO INFRASTRUCTURE | YES (drop Context → drop factory → drop nodes) |
| Bootstrap singleton retired | NO (still used for CFG node construction via shim) | NOT BY THIS PHASE |

## Migration recipe (Phase 3a-infra shape)

Order is mechanical; each step is independently committable:

1. **Add the field.** `lib/Chalk/Bootstrap/Context.pm`: add
   `field $factory :param :reader = undef;` next to `$graph`. Add
   `factory => (exists $opts{factory} ? $opts{factory} : $factory)` to
   `extend()`. 3-line diff.

2. **Add MOP fields.** `lib/Chalk/MOP/Method.pm` and `lib/Chalk/MOP/Sub.pm`:
   add `field $factory :param :reader = Chalk::IR::NodeFactory->new;`
   immediately after `$graph`. Optionally add `make`/`make_cfg` delegators
   parallel to `merge`/`next_cfg_id`. 2-3 lines each.

3. **Seed the factory at parse entry.** Wherever Actions constructs the
   initial Context (or wherever `one()` is invoked from
   FilterComposite/SemanticAction), pass the Actions' `$typed` factory as
   `factory => $typed`. Until per-method factory ownership lands, this
   keeps current behavior — one factory threaded through Context instead
   of one factory read from `field $typed`.

4. **Propagate through SemanticAction/FilterComposite.** Mirror the existing
   graph/scope plumbing: `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm`
   `one()` and `_wrap_sa_result()` already propagate `scope`/`graph`
   from the SA result (commit `885beb87` — see SemanticAction.pm line
   ~525). Add `factory` to the same propagation. Small diff, parallel to
   existing pattern.

5. **Migrate Actions.pm readers.** Wherever Actions methods reference
   `$typed`, change to `$ctx->factory() // $typed` (keep `$typed` as the
   ADJUST-initialized fallback during transition). Then in a second
   commit, remove the `$typed` field and the fallback. This is the
   bulk-edit step and is the closest analog to the Actions.pm churn in
   commit `885beb87`.

6. **Per-method factory ownership (the actual payoff).** When a
   MethodDefinition action constructs the MOP::Method, also construct a
   fresh factory and attach it to the method, then thread that factory
   into the body's Context via `extend(factory => $method->factory)`.
   Now each method's IR lives in its own factory.

7. **Collapse Graph's hash-cons cache** (optional follow-up). Once factory
   identity tracks graph identity 1:1, `Chalk::IR::Graph::merge` can
   stop maintaining a duplicate cache and just `$factory->make` everything.
   This is Phase 7+; out of scope here.

8. **Retire Bootstrap singleton** (optional follow-up). Once
   `make_cfg` callers in Actions.pm read the factory from Context,
   `Chalk::Bootstrap::IR::NodeFactory->instance()` has no production
   readers and can be deleted along with `_ensure_new_factory`. Also
   out of scope for the promotion itself.

Total expected production-file footprint: 4-6 files, ~100-200 line-deltas,
no test migrations forced (tests build their own factories locally and
don't observe Context-level factory propagation).
