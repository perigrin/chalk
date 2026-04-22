# Chalk::MOP Migration Plan

## Overview

This plan sequences the implementation of `Chalk::MOP` — Chalk's
compile-time Meta Object Protocol — and absorbs the remaining work
from the polymorphic SoN IR migration and the target interface
redesign into a single unified cutover.

The target shape is specified in
[docs/plans/2026-04-20-program-graph-of-graphs-design.md](2026-04-20-program-graph-of-graphs-design.md).
Read that first for the *what*. This document describes the *how*.

## Supersedes

This plan consolidates and replaces three previously separate plans
into one coherent migration. The superseded plans describe work that
is all, viewed from different angles, the same cutover:

- [`2026-04-04-son-ir-polymorphic-migration.md`](2026-04-04-son-ir-polymorphic-migration.md)
  — SoN IR polymorphic migration. Its infrastructure (typed nodes,
  NodeFactory, Graph, metadata structs) is complete; its cutover
  (remove Shim, migrate Actions.pm, finish SSA, migrate codegen) is
  0/9 acceptance criteria met as of 2026-04-21. The cutover work
  lands through MOP phases rather than as separate direct migration.

- [`2026-04-04-phase4-structural-split.md`](2026-04-04-phase4-structural-split.md)
  — Phase 4 (SSA scope + structural split). Phase 4b (structural
  types to metadata) is complete. Phase 4a (SSA scope with Phi
  insertion) remains outstanding and is absorbed into this plan's
  Phase 3.

- [`2026-04-21-target-interface-design.md`](2026-04-21-target-interface-design.md)
  — Target interface redesign (`generate($mop) → HashRef[Str]`). The
  interface becomes testable only once a MOP exists; its migration is
  this plan's Phase 4.

The D3 design spec
([`2026-04-20-program-graph-of-graphs-design.md`](2026-04-20-program-graph-of-graphs-design.md))
is **not** superseded — it is the target shape this plan implements.

## Guiding principles

### One migration, not three sequential ones

The polymorphic migration, the target interface redesign, and the MOP
introduction all touch the same call sites: Actions.pm's 61
`make('Constructor', ...)` sites, the 18 `->body()` reader sites, the
`($sa, $ctx)` backchannel. Migrating through intermediate states
(ClassInfo->new directly, then later to $mop->declare_class) means
migrating the same sites twice. This plan routes all construction
through the MOP from the start, so each site is touched once.

### Structural separation preserved

Phase 4b of the polymorphic migration deliberately moved structural
types (Program, ClassInfo, MethodInfo, FieldInfo, SubInfo, UseInfo)
out of the IR graph, following Cliff Click's Sea of Nodes design.
This plan preserves that separation. The MOP wraps and owns the
metadata structs; it does not make them graph nodes.

### Graph construction belongs to the graph-owner

The SSA construction algorithm currently lives as `_build_method_graph`
in Actions.pm. This is a historical accident — the method does
method-scoped work (building a method's graph) but was placed in the
semantic-action class because `MethodDefinition()` calls it. This
plan moves graph construction to its structural home:
`Chalk::IR::Graph::build(...)`, invoked via each graph-owner's
`$self->graph->build(...)` delegation.

### AMOP tradition, not wrapper layer

Chalk::MOP is in the AMOP tradition (Kiczales, Stevan Little).
Metaobjects are live objects in the language's own object system.
Meta-circularity — the MOP describing itself — is a correctness
property of self-hosting: when Chalk compiles `lib/Chalk/MOP/Class.pm`,
the resulting MOP describes `Chalk::MOP::Class`. After self-hosting,
Chalk's runtime IS a target runtime; the MOP is the object system,
not a compile-time wrapper that gets discarded.

For the Perl target, this is free — Perl IS the runtime and MOP
objects ARE Perl objects. For the C target, emitting a runtime
implementation of the MOP protocol in C is downstream work tracked
separately from this migration. The MOP's protocol is designed to
support both paths without change.

### Per-graph hash-cons scope

> **AMENDED** — originally "Per-class hash-cons scope" with a
> class-owned factory. Revised to per-graph-owner scope. See Phase 2
> amendment for rationale.

Each graph-owner (Method, Sub, Phaser::Adjust) owns a
`Chalk::IR::Graph` with its own hash-cons cache and CFG id
allocator. Nodes constructed via `$graph->merge($node)` are
deduplicated within the graph; identical content across graphs
yields distinct objects. Consumer lists are bounded to the graph
scope, structurally fixing the `Graph.nodes()` consumer-
contamination problem that required the `body_stmts` BFS workaround
and inputs-only traversal.

Hash-consing scope is per-graph-owner, not per-class. Two methods
within the same class each have their own cache. This is the
correct granularity for the consumer-contamination fix — per-class
would still share nodes across methods within a class.

### Composition over inheritance for graph-owners

> **AMENDED** — originally "GraphOwner as shared role" implemented
> as an abstract parent class. Revised to composition.

`Chalk::MOP::Method`, `Chalk::MOP::Sub`, and `Chalk::MOP::Phaser`
(inherited by `Phaser::Adjust`) each have a
`field $graph = Chalk::IR::Graph->new` and delegation methods
`merge($node)` / `next_cfg_id()` routing to their graph. No
`Chalk::MOP::GraphOwner` abstract parent class — Perl 5.42
`feature class` lacks roles, and `Phaser::Adjust :isa(Phaser)`
already occupies the single-inheritance slot. Composition (has-a
graph) avoids the conflict and expresses the relationship correctly:
a Method is not a kind of graph — it has a graph.

## Current state

As of 2026-04-21:

**Exists and stable:**
- Typed IR nodes under `Chalk::IR::Node::*` (79 classes)
- `Chalk::IR::NodeFactory` (shared singleton-style factory)
- `Chalk::IR::Graph` with `body_stmts` BFS-seed workaround
- Metadata structs: `Program`, `ClassInfo`, `MethodInfo`, `FieldInfo`,
  `SubInfo`, `UseInfo`
- `Chalk::IR::Shim` translating `make('Constructor', class => X, ...)`
  to typed nodes
- 5-ary FilterComposite semiring
- Context comonad (now with `error` slot from X1)

**Missing (this plan delivers):**
- `Chalk::MOP` and its metaobject family
- Per-class hash-cons scope
- Full SSA construction (`build_graph`)
- Resolved MOP-handle references on Call nodes
- `generate($mop) → HashRef[Str]` target interface

**Blocking residue (this plan removes):**
- 61 `make('Constructor', ...)` sites in Actions.pm
- `Chalk::IR::Shim` (227 lines)
- `compat_class` field on `Chalk::IR::Node`
- `body` field on `Chalk::IR::MethodInfo`
- `body` field on `Chalk::IR::ClassInfo`
- 18 `->body()` reader sites across Target/Perl, Target/C,
  EmitHelpers, StructPromotion
- `generate_with_cfg($ir, $sa, $ctx)` and `generate_c_files($ir, $sa, $ctx)`
  backchannel signatures
- `body_stmts` BFS seeding in `Chalk::IR::Graph`
- Consumer-traversal exclusion in `Graph::nodes()`

## Test strategy

Testing is architectural for a migration of this scope. Without
explicit test commitments, phase boundaries become subjective.

### TDD ordering

Every phase follows TDD per `CLAUDE.md`. For each scope item in a
phase: write a failing test, observe the failure, implement the
minimal change, observe the pass, commit. Phase scope sections below
list the *behaviors* each phase delivers; each behavior becomes one
or more failing tests before implementation begins.

### Regression invariant

Across all phases, the **existing test suite at HEAD passes**. Any
test that currently passes must continue to pass through every
phase's work. This is the hard invariant — a phase that breaks
existing behavior is not done, regardless of what it added.

Specifically, the following test families are load-bearing and
regress-quickly under architectural change:

- `t/self-hosting.t` — self-hosting validation
- `t/perl-base-tests.t`, `t/perl-class-tests.t` — core Perl subset
- `t/bootstrap/*.t` minus the currently-broken set (enumerated at
  Phase 0 time; the 2026-04-21 audit found `ir-program-pipeline.t`
  and `ir-sub-info-pipeline.t` already crashing)

The broken-at-HEAD set is frozen during Phase 0 by running `./prove`
and committing a snapshot of which tests pass. That snapshot is the
regression line for subsequent phases — any test green at Phase 0
entry must be green at every subsequent phase exit.

### Per-phase new-test requirements

Each phase's *Scope* section lists specific test additions. In
summary:

- **Phase 0:** unit tests for every MOP metaobject (construction,
  accessors, direct-declared enumeration, resolution walks, implicit
  `main` class).
- **Phase 1:** integration tests that parse a Perl file and assert
  the resulting MOP's shape (classes, methods, fields, imports,
  ADJUST blocks present and correct).
- **Phase 2:** hash-cons isolation test — two classes constructing
  identical `Constant 0` nodes get distinct identities with disjoint
  `consumers` lists.
- **Phase 3** (split into 3a/3b/3c — see *Phases* below):
  - **3a:** control-chain threading tests (linear code reachability)
  - **3b:** if/else Phi insertion tests (merge, trivial-Phi
    elimination, nested if/else, unchanged-vars no-Phi)
  - **3c:** loop Phi insertion tests (loop header, backedge wiring,
    nested loops, loop-inside-if, unused-vars no-Phi); revive
    `ir-program-pipeline.t` and `ir-sub-info-pipeline.t`; general
    reachability assertion for any valid body
- **Phase 4:** byte-compatibility golden tests — see below.
- **Phase 5:** optimizer pass signature tests (DCE takes and returns
  a Graph; StructPromotion takes and returns a MOP).
- **Phase 6:** no new tests; deletion verified by the regression
  invariant and by `grep` searches for removed identifiers.
- **Phase 7:** `Graph.nodes()` bidirectional traversal tests;
  assertion that `body_stmts`-less graphs are fully reachable.
- **Phase 8:** doc-presence tests if feasible (e.g., a CI check that
  `docs/architecture/mop.md` exists and references known
  metaobjects).

### Byte-compatibility golden for Phase 4

Phase 4 changes the codegen entry point but must not change codegen
output for programs Chalk successfully compiles today. Mitigation:

1. At Phase 3c exit (before Phase 4 begins), run all Target/Perl and
   Target/C generation over the green-eval file set and commit the
   output to `t/fixtures/codegen-goldens/` as the reference set.
2. Phase 4's acceptance includes: running generation post-migration,
   diffing against the golden, reporting zero byte differences.
3. If a diff is detected, it is a Phase 4 regression — either the
   change is genuinely behavior-altering (stop and investigate) or
   the determinism guarantee broke (stop and investigate).

The golden set is a forensic tool, preserved through Phase 7 and
deleted at Phase 8 exit. Its purpose is diagnostic: if a byte-diff
surfaces in any later phase (5, 6, or 7), the golden pinpoints when
the divergence started. The bug is fixed forward in whichever phase
is current; the golden is not a rollback target. See *Roll-forward
discipline* for the broader stance.

### Test-fixture migration

~22 test files currently construct `Chalk::IR::Program`,
`ClassInfo`, `MethodInfo`, etc. directly. As each phase replaces
metadata-struct APIs with MOP APIs, the tests that exercise those
APIs migrate with them. Each phase owns the test-fixture migration
for the structs it replaces — tests are not deferred to a separate
phase.

### Test infrastructure invariants

- Tests use the real Chalk grammar and parser, not toy inline
  grammars. This is the 2026-04-19 alignment-review finding — the
  299-test regression suite reached that count without parsing the
  actual BNF meta-grammar. Every test added by this migration parses
  real input.
- No mocks of the MOP, Graph, or factory. Construct real metaobjects
  with real test inputs.
- Test output must be pristine (per `CLAUDE.md`). Any test producing
  unexpected diagnostic output is failing, regardless of TAP status.

## Roll-forward discipline

This migration does not roll back. The MOP architecture is *more
correct* than the pre-migration state, which is itself residue from
an incomplete polymorphic migration. Rolling back to residue is
worse than pushing forward through a bug. Every phase lands and
stays landed.

Three mechanisms support this:

### Strict phase-exit gates

A phase does not exit until its acceptance criteria are met. That
includes the regression invariant (every test green at entry is
green at exit), the phase's new tests (all passing, no TODO
markers), and the phase's documented scope (no "we'll finish this
in the next phase" carryovers).

If a phase cannot reach its exit criteria, the phase is not done.
Extend the phase — add scope, add tests, add commits — until it is.
Do not merge a phase whose acceptance is incomplete on the premise
that a later phase will clean it up. This is the 80%-done-is-done
failure mode `CLAUDE.md`'s Plan Discipline section flags.

### Bug triage documents itself

When a bug surfaces during a phase, the response is one of:

1. **Fix within the current phase.** Add tests, add code, commit as
   part of the phase's delivery. No separate bookkeeping needed.
2. **Defer forward with explicit tracking.** If the bug is genuinely
   out of the phase's scope (surfaces during Phase 4 but is actually
   a Phase 5 concern), file an issue or add to the task list with
   the phase number it belongs in. The phase you're in does not
   carry it; the phase that owns it does.
3. **Stop the migration.** If the bug reveals a design flaw in the
   plan itself (e.g., per-class hash-cons is wrong, the GraphOwner
   role doesn't fit), stop, document the finding, revise the plan,
   then resume. Do not push through a design problem with tactical
   patches.

In-code workarounds ("FIXME: Phase 6 should remove this") are
acceptable during phase work but must be cleaned up by the phase
that owns the real fix. FIXME comments without an owning phase are
technical debt, which is what this migration exists to eliminate,
not add to.

### Forensic tooling, not rollback tooling

Phase 4 captures a byte-compat golden for the green-eval codegen
output. The golden is preserved **until Phase 8 exit**, not Phase 4
exit. Its purpose is diagnostic: if a byte-diff surfaces in Phase 5,
6, or 7, the golden lets us locate *when* the divergence started.
The bug gets fixed in whatever phase is current; the golden is
deleted at Phase 8 exit along with the rest of the migration's
transitional scaffolding.

The same principle applies to any other phase-boundary artifacts
(test baselines, reference fixtures): they are diagnostic, not
reversion points. Phase 0's test-pass baseline, for example, is
useful for proving the regression invariant held through Phase 3's
SSA work. It is not a "state we can revert to."

### What this plan does NOT promise

- That individual commits within a phase are revertible. They may
  or may not be, depending on whether scope items within the phase
  have internal dependencies. We commit frequently but don't
  guarantee per-commit revertibility.
- That a phase that has already exited can be re-opened. Once Phase
  3 is done, the pre-SSA state is gone. If a Phase 5 regression
  reveals a Phase 3 bug, the fix lands forward, not backward.
- That mid-phase abandonment is supported. If a phase starts and
  the approach turns out to be wrong, the abandoned work gets
  squashed into history — not reverted, just not merged. The next
  attempt starts fresh from the phase entry point.

## Phases

Phase numbering starts at 0 (scaffolding). Each phase has explicit
entry conditions, exit conditions, and acceptance criteria.

### Phase 0: Scaffold the MOP

**Goal:** introduce `Chalk::MOP` and its metaobject classes as new
code alongside existing metadata structs. No renames, no behavior
changes. Existing consumers continue to use the metadata structs
directly.

**Entry:** polymorphic migration infrastructure complete (it is).

**Scope:**

- Archive-banner the superseded plans:
  - Add `> **ARCHIVED** — superseded by 2026-04-21-chalk-mop-migration-plan.md`
    to the three files named in *Supersedes* above.
- Create `lib/Chalk/MOP.pm` with:
  - `declare_class`, `classes`, `for_class`
  - Constructor seeds implicit `main` class
- Create `lib/Chalk/MOP/Class.pm` with:
  - Identity accessors (`name`, `superclass`, `mop`)
  - Direct-declared list accessors (`fields`, `methods`, `subs`,
    `imports`, `adjust_blocks`)
  - Construction methods (`declare_field`, `declare_method`,
    `declare_sub`, `declare_import`, `declare_adjust`)
  - Resolution methods (`find_method`, `ancestors`, `resolve_adjust_blocks`)
- Create `lib/Chalk/MOP/Field.pm`, `Method.pm`, `Sub.pm`, `Import.pm`.
- Create `lib/Chalk/MOP/Phaser.pm` (abstract base).
- Create `lib/Chalk/MOP/Phaser/Adjust.pm`.
- Add `mop :param :reader = undef` field to
  `Chalk::Bootstrap::Context`. The MOP is a coordination surface for
  all compile-time layers, not just SemanticAction; a Context-
  accessible reference makes any semiring able to reach metaobjects
  at parse time. The `mop` reference is excluded from content-hash
  computation in `TypeInference._tag_key` and elsewhere so it
  doesn't defeat Context hash-consing. Add `mop` to the opts-
  override list in `Context::extend` following the existing
  `is_zero`/`token`/`error` pattern.
- Unit tests in `t/bootstrap/mop/` for construction, enumeration,
  resolution, direct-declared-vs-inherited semantics.
- **Tests (TDD, before implementation):**
  - `t/bootstrap/mop/mop.t` — `declare_class`, `classes()`,
    `for_class()`, implicit `main` seeding
  - `t/bootstrap/mop/class.t` — accessors; `declare_field`,
    `declare_method`, `declare_sub`, `declare_import`,
    `declare_adjust`; direct-declared enumeration
  - `t/bootstrap/mop/field.t` — accessors (`name`, `sigil`,
    `fieldix`, `param_name`, `has_default`, `attributes`)
  - `t/bootstrap/mop/method.t` — accessors (`name`, `class`,
    `params`, `return_type`); `graph()` present
  - `t/bootstrap/mop/sub.t`, `import.t`, `phaser-adjust.t` —
    accessor coverage
  - `t/bootstrap/mop/resolution.t` — `find_method` walks ancestors;
    `ancestors()` returns the chain; `resolve_adjust_blocks`
    orders base-first-source-order
  - `t/bootstrap/context-unified-fields.t` — add coverage for the
    new `mop` field alongside existing `error` slot tests (default
    undef; passes through extend; opts override works)
  - `t/bootstrap/mop/hand-constructed.t` — construct a MOP entirely
    without parsing: `Chalk::MOP->new`, `declare_class`,
    `declare_field`, `declare_method` (with a hand-built
    `Chalk::IR::Graph`), assert the resulting structure is internally
    consistent. This is the smoke test for the frontend-agnostic
    property over Chalk's subset: the MOP's public API is
    self-contained and does not require Chalk's parser to exercise.
- Capture the test-pass baseline: run `./prove` at phase exit and
  commit the passing/failing split as
  `docs/plans/2026-04-21-phase0-test-baseline.md` (superseded at
  Phase 3 exit when the `ir-program-pipeline` / `ir-sub-info-pipeline`
  tests are revived).

**Implementation notes:**
- MOP metaobjects *are* the metadata — they own the fields directly,
  not via delegation to `ClassInfo` et al. Phase 0 builds them in
  isolation (no integration with Actions.pm yet).
- No graph construction surface yet (`make`/`make_cfg` come in Phase 2).
- No `build_graph` yet (comes in Phase 3).
- No integration with Actions.pm yet (comes in Phase 1).

**Exit criteria:**
- All MOP classes exist and are unit-tested in isolation.
- `$mop->declare_class('Foo')->declare_field('$x', sigil => '$')` and
  equivalent constructions work.
- `$mop->for_class('main')` returns the implicit main class.
- Existing test suite unchanged (no regressions).

**Polymorphic-migration criteria addressed:** none directly. Phase 0
is pure foundation.

---

### Phase 1: Actions.pm builds the MOP

**Goal:** route all 61 `make('Constructor', ...)` sites in
`lib/Chalk/Bootstrap/Perl/Actions.pm` through the MOP's
`declare_*` API. The MOP is threaded through semantic actions via
the Context comonad.

**Entry:** Phase 0 complete.

**Scope:**

- Thread the `Chalk::MOP` instance through parsing by placing it on
  the root Context (the Context passed into `parse_value`) and
  propagating it through every `extend` / `multiply` / `duplicate`.
  Semantic actions reach it via `$ctx->mop()`. Other semirings that
  want to enrich metaobjects at parse time (TypeInference recording
  inferred types onto `Chalk::MOP::Method::return_type`, for example)
  reach it the same way. The MOP is not a SemanticAction-private
  concern; it is a compile-time coordination surface.
- Migrate each of the 8 direct construction sites in Actions.pm:
  - `ClassBlock()` → `$mop->declare_class(...)`
  - `MethodDefinition()` → `$class->declare_method(...)`
  - `SubroutineDefinition()` → `$class->declare_sub(...)` (in-class)
    or `$main->declare_sub(...)` (top-level)
  - `FieldDeclaration()` → `$class->declare_field(...)`
  - `UseDeclaration()` → `$class->declare_import(...)`
  - ADJUST blocks → `$class->declare_adjust(...)`
  - `Program()` → returns the MOP itself
  - `_flatten_use_groups` → emits imports via the class
- Migrate the 17 Constructor-class sites that flow through Shim for
  computation nodes (MethodCallExpr, BuiltinCall, etc.) to construct
  typed nodes directly via the factory. At this phase, call-node
  targets are still strings — resolved-reference migration is
  Phase 4.
- MOP metaobjects *are* the metadata, not wrappers. `Chalk::MOP::Class`
  has fields for name, superclass, fields, methods, etc. directly —
  there is no internal `ClassInfo` delegate. During this phase,
  `Chalk::IR::ClassInfo` and siblings are still alive for consumers
  that haven't migrated, but the MOP is the primary construction
  target. Phase 6 deletes the old struct classes.
- **Tests (TDD, before implementation):**
  - `t/bootstrap/mop/parse-integration.t` — parse a small Perl
    source containing a class with a method, a field, an ADJUST
    block, and a `use`; assert the resulting MOP has the correct
    shape (classes, methods, fields, imports, ADJUST blocks at
    their owning scope)
  - `t/bootstrap/mop/parse-top-level.t` — parse a source with a
    top-level `sub`; assert it lives on the implicit `main` class
  - Per construction site in Actions.pm, add a focused test
    asserting the MOP outcome before migrating the site
  - The regression invariant applies: every existing test passing
    at Phase 0 exit must pass at Phase 1 exit.

**Exit criteria:**
- Zero `make('Constructor', ...)` sites in Actions.pm.
- Existing test suite passes (parse output shape unchanged — still
  produces ClassInfo/MethodInfo, now owned by the MOP).
- `$mop->classes` returns the parsed program's classes after a
  successful parse.

**Polymorphic-migration criteria addressed:** #1 (zero Constructor
sites).

---

### Phase 2: Per-graph hash-cons scope

> **AMENDED** — original spec called for per-class factory via
> `Chalk::MOP::GraphOwner` abstract parent class. During
> implementation (2026-04-21), design review concluded:
>
> 1. Per-class scoping doesn't actually fix the consumer-contamination
>    bug (`Graph.nodes()` can't follow consumers because methods
>    within the same class still share nodes). Per-graph-owner
>    scoping does — each Method/Sub/Phaser gets its own cache, so
>    consumer lists are bounded to a single graph.
>
> 2. `GraphOwner` as a parent class conflicts with `Phaser::Adjust
>    :isa(Phaser)` (Perl 5.42 `feature class` lacks roles/multiple
>    inheritance). Composition (has-a graph) replaces inheritance.
>
> 3. The factory pattern (`$factory->make('TypedOp', ...)` with
>    string-dispatch) was unnecessary — callers construct typed node
>    classes directly (`Chalk::IR::Node::Call->new(...)`) and the
>    graph hash-conses via `merge()`.
>
> 4. Migrating Actions.pm call sites from `$factory->make(...)` to
>    `$graph_owner->merge(...)` requires solving the Earley
>    bottom-up ordering problem (body nodes are constructed before
>    the graph-owner metaobject exists). This migration is deferred
>    to Phase 3, where `build_graph` rewrites the construction flow.

**Goal:** give each graph-owner (`Method`, `Sub`, `Phaser::Adjust`)
its own `Chalk::IR::Graph` with per-graph hash-cons scope. Nodes
constructed via `$graph->merge($node)` are deduplicated within the
graph; identical content across graphs yields distinct objects with
bounded consumer lists.

**Entry:** Phase 1 complete.

**Scope:**

- Add `merge($node)` and `next_cfg_id()` to `Chalk::IR::Graph`.
  `merge` hash-conses by `content_hash`; `next_cfg_id` allocates
  unique CFG node ids. `nodes()` returns the cache contents directly
  when the cache is populated (no BFS needed). Legacy constructor
  params (`start`, `returns`, `body_stmts`) remain for backward
  compatibility; `start()` and `returns()` derive from the cache
  when legacy params aren't provided.
- Add `field $graph = Chalk::IR::Graph->new` to `Method`, `Sub`,
  and `Phaser` (abstract base — `Phaser::Adjust` inherits). Each
  graph-owner constructs a fresh graph at instantiation.
- Add `merge($node)` and `next_cfg_id()` delegation methods on each
  graph-owner, routing to `$self->graph->...`.
- No `Chalk::MOP::GraphOwner` abstract parent class. Composition
  (has-a graph) replaces inheritance, avoiding the `:isa` conflict
  with the Phaser hierarchy.
- No Actions.pm migration in this phase. Body-node construction
  stays on `$factory` / `$typed` (Phase 1B's typed factory). Phase 3
  rewrites body construction to use the graph-owner's `merge()`.
- Verify per-graph hash-cons isolation: a test constructs two
  methods each merging `Constant 0`, asserts the resulting nodes
  have distinct identities.
- Remove `current_class` from `Chalk::MOP` (Phase 1 design
  mistake — was always `main`). Move UseDeclaration MOP registration
  into ClassBlock/Program body iteration, matching the pattern used
  for fields/methods/subs/ADJUST.
- **Tests (TDD, before implementation):**
  - `t/bootstrap/mop/graph-merge.t` — `merge()` deduplicates
    within a graph; per-graph isolation (identical content across
    graphs yields distinct objects); `next_cfg_id()` allocates
    independently per graph
  - `t/bootstrap/mop/per-graph-hash-cons.t` — end-to-end isolation
    through MOP metaobjects: Method/Sub/Phaser::Adjust each own
    their own cache, across classes
  - Regression invariant: every existing test green at Phase 1
    exit remains green at Phase 2 exit.

**Implementation notes:**
- `Chalk::IR::NodeFactory` continues to exist for any remaining
  direct-call consumers (tests, Actions.pm body construction, etc.)
  but is no longer the long-term construction path.
- `Chalk::IR::Graph` BFS legacy path still uses inputs-only
  traversal as a fallback for pre-Phase 2 callers (restored to
  bidirectional in Phase 7 once all graphs are constructed via
  `merge()`).
- Call sites construct typed node classes directly (e.g.,
  `Chalk::IR::Node::Constant->new(value => 0)`) and pass them to
  `$graph->merge(...)`. No string-dispatch factory pattern.

**Exit criteria:**
- Per-graph hash-cons isolation verified by test.
- Every graph-owner metaobject (Method, Sub, Phaser::Adjust)
  constructs a fresh `Chalk::IR::Graph` on instantiation.
- `current_class` removed from `Chalk::MOP`.
- Existing test suite passes.

**Polymorphic-migration criteria addressed:** partial — foundation
for #7 (full SSA). Per-graph isolation structurally enables
bidirectional consumer traversal within a graph (Phase 7).

---

### Phase 3: Graph::build (full SSA)

> **AMENDED** — original spec referenced `Chalk::MOP::GraphOwner::build_graph`.
> Phase 2 eliminated GraphOwner (see Phase 2 amendment). `build_graph`
> lives on `Chalk::IR::Graph` instead — graph-owners delegate via
> `$self->graph->build(...)`. This also absorbs the Actions.pm
> migration deferred from Phase 2: body-node construction moves from
> `$factory->make(...)` to `$graph->merge(Node::Foo->new(...))` as
> part of the `build` rewrite.

Phase 3 is the largest single piece of compiler work in the plan —
SSA construction algorithm implementation. It is split into three
sub-phases (3a, 3b, 3c), each with independent acceptance criteria.
Each sub-phase is a stopping point: if migration is interrupted
after 3a completes, the codebase is in a defined, testable state.

**Shared implementation notes:**

- The algorithm design is sketched in
  `2026-04-04-phase4-structural-split.md` §"Hybrid Phi Strategy";
  these sub-phases implement it in three staged layers.
- The `Scope` class (`Chalk::Bootstrap::Scope`) already has the
  `fork_for_loop`, `resolve_sentinel`, `merge_with_phis`,
  `merge_for_loop` machinery. Each sub-phase invokes the relevant
  pieces.
- The Context tree holds `cfg_state` annotations per-node; the
  builder extracts the ones belonging to the current method via
  refaddr-keyed walk.
- `Chalk::IR::Graph::build(...)` is introduced in 3a with a minimal
  implementation; 3b and 3c extend it with Phi insertion paths.
  Graph-owners (Method, Sub, Phaser::Adjust) delegate via
  `$self->graph->build(...)`.
- Call sites within `build` construct typed node classes directly
  (`Chalk::IR::Node::Start->new(...)`) and merge them into the graph
  via `$self->merge(...)` — no factory string-dispatch.

---

#### Phase 3a: Control-chain threading

**Goal:** every side-effect statement in a graph-owner's body has a
control input chaining back to `start`. No Phi insertion. Works for
linear code (no if/else, no loops).

**Entry:** Phase 2 complete.

**Scope:**

- Implement `Chalk::IR::Graph::build($body_stmts, $cfg_state,
  $start_ctrl)` with the control-chain layer:
  - Construct typed node objects directly
    (`Chalk::IR::Node::Start->new(...)`) and `merge()` them into
    the graph — no factory string-dispatch.
  - Thread a linear control chain through side-effect statements
    (VarDecl, Assign, Call, etc.).
  - Each side-effect node's control input is the previous side-
    effect node (or `start` for the first).
  - After `build` completes, `$graph->nodes()` reaches every
    linear-code statement from `start` via the cache (no
    `body_stmts` BFS needed).
  - If/else and loop bodies produce graphs but without Phi nodes at
    merge points yet — that's 3b and 3c.
- Migrate `MethodDefinition()`, `SubroutineDefinition()`, and ADJUST
  block actions to call `$method->graph->build(...)` instead of
  Actions.pm's `_build_method_graph`.
- Delete `_build_method_graph` from Actions.pm.
- **Tests (TDD, before implementation):**
  - `t/bootstrap/mop/build-graph-control-chain.t` — side-effect
    statements (VarDecl, Assign, Call) have control inputs chaining
    back to Start in a purely-linear method body
  - `t/bootstrap/mop/build-graph-linear-reachability.t` — for a
    linear method body, `$method->graph->nodes()` reaches every
    statement from `start` via inputs alone (no `body_stmts` needed)
  - Regression invariant: every existing test green at Phase 2
    exit remains green at Phase 3a exit.

**Exit criteria:**
- `_build_method_graph` is deleted from Actions.pm.
- Linear-code graphs are fully reachable from `start` through
  inputs alone.
- Branching and looping code still works (uses older scope logic
  without Phis at merge points) — not regressing the existing
  behavior, but not yet producing proper SSA either.

**Polymorphic-migration criteria addressed:** partial on #7 (linear
case of full SSA).

---

#### Phase 3b: If/else Phi insertion

**Goal:** if/else merge points produce Phi nodes for variables that
differ between branches, via eager Click-style merging.

**Entry:** Phase 3a complete.

**Scope:**

- Extend `Graph::build` with if/else Phi insertion:
  - At Region merge (after both branches complete), diff the branch
    scopes against the pre-if scope.
  - For each variable that differs between the two branches, emit a
    Phi node at the Region with the branch-final values as operands.
  - Apply trivial-Phi elimination inline: if both Phi operands are
    identical, replace the Phi with the common value.
  - Handle nested if/else correctly (Phi inside a branch produces
    the branch-final value feeding the outer merge).
- **Tests (TDD, before implementation):**
  - `t/bootstrap/mop/build-graph-ifelse-phi.t` — if/else merge
    creates Phi for variables that differ between branches
  - `t/bootstrap/mop/build-graph-ifelse-trivial-phi.t` — trivial
    Phi (both operands identical) is eliminated inline
  - `t/bootstrap/mop/build-graph-ifelse-nested.t` — nested
    if/else produces correct Phi at each merge point
  - `t/bootstrap/mop/build-graph-ifelse-unchanged-vars.t` —
    variables unchanged in both branches get no Phi
  - Regression invariant: every existing test green at Phase 3a
    exit remains green at Phase 3b exit.

**Exit criteria:**
- If/else constructs in method bodies produce correct Phi nodes at
  merge points.
- Trivial Phis are eliminated (not left in the graph).
- Loop constructs still work via old scope mechanics (3c completes
  them).

**Polymorphic-migration criteria addressed:** partial on #7.

---

#### Phase 3c: Loop Phi insertion

**Goal:** loop headers produce Phi nodes for loop-carried variables
via lazy sentinel-based resolution. Backedges are wired after the
loop body completes.

**Entry:** Phase 3b complete.

**Scope:**

- Extend `Graph::build` with loop Phi insertion:
  - At loop entry, fork the scope into sentinels via
    `Scope::fork_for_loop` (already implemented).
  - When a variable is read inside the loop body, resolve its
    sentinel into a Phi on demand via `Scope::resolve_sentinel`
    (already implemented).
  - At loop exit, wire backedges: for each loop-carried Phi, set
    its second operand to the body-final value via
    `Scope::merge_for_loop`.
  - Handle iterator variables (foreach loops) — the iterator itself
    is not a loop-carried Phi.
- Revive `t/bootstrap/ir-program-pipeline.t` and
  `t/bootstrap/ir-sub-info-pipeline.t` (currently crashing per the
  2026-04-21 audit); they should pass once full SSA is in place.
- **Tests (TDD, before implementation):**
  - `t/bootstrap/mop/build-graph-loop-phi.t` — loop header Phi
    creation via sentinel; backedge wiring at loop exit
  - `t/bootstrap/mop/build-graph-loop-unused-vars.t` — variables
    only read in loops (not modified) don't get Phis
  - `t/bootstrap/mop/build-graph-loop-nested.t` — nested loops
    produce correct Phis at each loop header
  - `t/bootstrap/mop/build-graph-loop-if.t` — if-inside-loop and
    loop-inside-if produce correct Phi placement
  - `t/bootstrap/mop/build-graph-reachability.t` — for *any* valid
    method body, `$method->graph->nodes()` reaches every statement
    from `start` via inputs alone (no `body_stmts` needed); this
    generalizes the linear-only check from 3a
  - `t/bootstrap/ir-program-pipeline.t` and
    `t/bootstrap/ir-sub-info-pipeline.t` — revived and passing
  - Regression invariant: every existing test green at Phase 3b
    exit remains green at Phase 3c exit.

**Exit criteria:**
- Loops in method bodies produce correct Phi nodes at loop headers.
- Every graph-owner's graph is fully reachable from `start` through
  inputs alone, regardless of control-flow shape.
- `ir-program-pipeline.t` and `ir-sub-info-pipeline.t` pass.

**Polymorphic-migration criteria addressed:** #7 (full SSA), #8
(pipeline tests) — both satisfied at Phase 3c exit.

---

### Phase 4: Codegen reads the MOP

**Goal:** migrate code generation targets to `generate($mop) →
HashRef[Str]`. The `($sa, $ctx)` backchannel is removed.

**Entry:** Phase 3c complete.

**Scope:**

- Add `generate($mop)` to `Chalk::Bootstrap::Perl::Target::Perl` and
  `Chalk::Bootstrap::Perl::Target::C`, alongside the existing
  signatures, initially delegating to the old path.
- Migrate the 18 `->body()` reader sites to walk method graphs via
  `$method->graph()`:
  - `Target/Perl.pm` (4 sites)
  - `Target/C.pm` (6 sites)
  - `Target/EmitHelpers.pm` (2 sites)
  - `Optimizer/StructPromotion.pm` (6 sites)
- Migrate `CallNode` target references from symbolic name strings to
  resolved `Chalk::MOP::Method` handles. Resolution happens in
  `MethodDefinition()` / `CallExpression()` semantic actions via
  `$mop->find_method(...)`.
- Remove `generate_with_cfg($ir, $sa, $ctx)` from Target/Perl.
- Remove `generate_c_files($ir, $sa, $ctx)` from Target/C; the
  public entry point becomes `generate($mop)`, which internally
  emits `.c` files and XS wrappers as a `HashRef[Str]`.
- Update the Target base class (`Chalk::Bootstrap::Target`) to define
  `generate($mop) → HashRef[Str]` and `generate_distribution($mop) →
  ...` as the abstract contract (packaging remains a higher-layer
  concern; `generate_distribution` may be deferred).
- **Tests (TDD, before implementation):**
  - Capture byte-compatibility golden **before** migration starts:
    at Phase 3 exit, run Target/Perl and Target/C over the
    green-eval file set and commit the output to
    `t/fixtures/codegen-goldens/` as the reference
  - `t/bootstrap/mop/codegen-perl-signature.t` — `Target::Perl` has
    `generate($mop)` and it returns `HashRef[Str]`
  - `t/bootstrap/mop/codegen-c-signature.t` — `Target::C` has
    `generate($mop)` and it returns `HashRef[Str]` with both `.c`
    and `.xs` entries
  - `t/bootstrap/mop/codegen-byte-compat.t` — generation output
    for the green-eval file set is byte-identical to the golden
  - `t/bootstrap/mop/call-node-resolved-handle.t` — a Call node's
    target is a `Chalk::MOP::Method` reference, not a string
  - `t/bootstrap/mop/codegen-no-backchannel.t` — `Target::Perl`
    and `Target::C` have no method taking `($sa, $ctx)` arguments
  - `t/bootstrap/mop/codegen-hand-constructed-mop.t` — codegen
    consumes a hand-constructed MOP (built without Chalk's parser,
    following the Phase 0 smoke test pattern) and produces valid
    output. This verifies the end-to-end frontend-agnostic property
    over Chalk's subset: codegen reads only through the MOP's
    public API, with no parser-specific coupling.
  - Regression invariant: every existing test green at Phase 3
    exit remains green at Phase 4 exit.
- Keep `t/fixtures/codegen-goldens/` alive through Phase 7 as a
  forensic tool (see *Roll-forward discipline* above). It is deleted
  at Phase 8 exit along with other migration scaffolding.

**Exit criteria:**
- All codegen reads from the MOP. No `->body()` readers remain in
  `lib/`.
- No `($sa, $ctx)` arguments on any target method.
- Existing end-to-end test suite passes.
- Output byte-compatible with pre-migration output for the green-
  eval file set (determinism preserved).

**Polymorphic-migration criteria addressed:** #4 (body readers), #6
(codegen walks graph), #9 (no backchannel).

---

### Phase 5: Optimizer passes take the MOP

**Goal:** reshape optimizer passes so they conform to the
`run($input) → $input` contract described in `docs/optimization.md`.

**Entry:** Phase 4 complete.

**Scope:**

- DCE: `Chalk::Bootstrap::Optimizer::DCE::run($graph) → $graph`.
  Operates per-method; invoked from a MOP-level iterator that walks
  classes → methods → graph.
- StructPromotion:
  `Chalk::Bootstrap::Optimizer::StructPromotion::run($mop) → $mop`.
  The schemas table currently returned as a tuple becomes an
  annotation on the MOP (or a side structure owned by the MOP).
- Update `Chalk::Bootstrap::Optimizer::Pass` abstract base to define
  the uniform contract.
- Migrate the optimizer pipeline orchestrator (if any) to the new
  signatures.
- **Tests (TDD, before implementation):**
  - `t/bootstrap/optimizer/dce-graph-signature.t` — `DCE::run($graph)`
    takes and returns a `Chalk::IR::Graph`
  - `t/bootstrap/optimizer/structpromotion-mop-signature.t` —
    `StructPromotion::run($mop)` takes and returns a `Chalk::MOP`
  - `t/bootstrap/optimizer/pass-contract.t` — the abstract
    `Chalk::Bootstrap::Optimizer::Pass` defines the `run($X) → $X`
    contract
  - Existing optimizer behavior tests continue passing (DCE still
    eliminates dead nodes; StructPromotion still promotes
    recognizable schemas). These become the real acceptance
    because the behavior, not the signature, is what matters.
  - Regression invariant: every existing test green at Phase 4
    exit remains green at Phase 5 exit.

**Exit criteria:**
- All optimizer passes conform to `run($X) → $X` for their scope
  level (per-method or program).
- Tasks X6 (DCE) and X8 (StructPromotion) are closed.

**Polymorphic-migration criteria addressed:** none directly; this
phase lands pass-interface redesign that was scoped separately.

---

### Phase 6: Delete residue

**Goal:** remove the dead code from the old world.

**Entry:** Phase 5 complete.

**Scope:**

- Delete `lib/Chalk/IR/Shim.pm`.
- Remove `compat_class` field from `lib/Chalk/IR/Node.pm`.
- Remove the Shim-translation path from
  `lib/Chalk/Bootstrap/IR/NodeFactory.pm`.
- Remove `body` field from `lib/Chalk/IR/MethodInfo.pm`.
- Remove `body` field from `lib/Chalk/IR/ClassInfo.pm`.
- Delete Shim-specific tests:
  - `t/bootstrap/ir-shim.t`
  - `t/bootstrap/ir-shim-activation.t`
  - `t/bootstrap/ir-factory-shim-integration.t`
- Delete `lib/Chalk/IR/Program.pm`. Its role is absorbed by
  `Chalk::MOP`: the MOP itself is the compilation-unit object (what
  Actions.pm returns from `Program()`), and what Program used to
  store distributes as:
  - `$program->classes` → `$mop->classes()`
  - `$program->top_level_subs` → `$mop->for_class('main')->subs()`
  - `$program->use_decls` → `$mop->for_class('main')->imports()`
    (plus each class's own `$class->imports()`)
  - `$program->other_stmts` (bare top-level IR nodes, appears only
    in test snippets) → handled at call sites that touch those
    tests, not at the MOP level
- Delete the metadata struct classes: `Chalk::IR::ClassInfo`,
  `Chalk::IR::MethodInfo`, `Chalk::IR::FieldInfo`,
  `Chalk::IR::SubInfo`, `Chalk::IR::UseInfo`. The MOP metaobjects
  *are* the metadata (not wrappers); these classes are dead code
  once all consumers are migrated.
- **Tests (verification rather than new tests):**
  - `grep -r "Chalk::IR::Shim" lib t` returns zero results
  - `grep -r "compat_class" lib` returns zero results
  - `grep -rn "->body()" lib` returns zero matches for MethodInfo
    or ClassInfo (the existing cfg_state `->{loop}` style accesses
    are a different thing — distinguish them)
  - Regression invariant: every existing test green at Phase 5
    exit remains green at Phase 6 exit.

**Exit criteria:**
- Shim is deleted.
- `compat_class` is gone from Node.
- `body` fields are gone from MethodInfo and ClassInfo.
- Test suite passes.

**Polymorphic-migration criteria addressed:** #2 (Shim deleted),
#3 (compat_class removed), #4 (MethodInfo.body removed), #5
(ClassInfo.body resolved).

---

### Phase 7: Restore bidirectional graph traversal

**Goal:** re-enable `Chalk::IR::Graph::nodes()` consumer traversal
and delete the `body_stmts` BFS seeding.

**Entry:** Phase 6 complete.

**Scope:**

- Restore bidirectional traversal in `Graph::nodes()` — follows both
  `inputs()` and `consumers()`. Safe now because per-graph hash-cons
  scope (Phase 2) guarantees consumer lists are graph-local.
- Delete the `body_stmts` field from `Chalk::IR::Graph` and the
  seeding logic. Safe now because Phase 3's full SSA reaches every
  node from `start`.
- Add `Chalk::MOP::Class::all_nodes()` for whole-class traversal
  that walks every graph-owner's graph. This is the right entry
  point for class-level analysis passes.
- Update `Chalk::IR::Graph`'s doc comment to reflect the model.
- **Tests (TDD, before implementation):**
  - `t/bootstrap/ir/graph-bidirectional-traversal.t` —
    `$graph->nodes()` follows both `inputs()` and `consumers()`
    without pulling in foreign-class nodes (per-class scope makes
    this safe)
  - `t/bootstrap/mop/class-all-nodes.t` —
    `$class->all_nodes()` walks every graph-owner in the class
  - `t/bootstrap/ir/graph-no-body-stmts.t` — reachability from
    `start` alone is complete (no `body_stmts` seed needed)
  - Regression invariant: every existing test green at Phase 6
    exit remains green at Phase 7 exit.

**Exit criteria:**
- `Graph::nodes()` follows both `inputs()` and `consumers()`.
- `body_stmts` field and its seeding logic are gone.
- No regression in node reachability (graph-scoped tests still pass).

**Polymorphic-migration criteria addressed:** none directly;
deferred technical debt from `Graph::nodes()` consumer exclusion
(commit 33e1b6f3).

---

### Phase 8: Documentation

**Goal:** update architecture and user-facing documentation to
reflect the MOP as a first-class layer of Chalk. Without this phase,
the docs drift out of sync the day Phase 7 lands.

**Entry:** Phase 7 complete.

**Scope:**

- **New doc:** `docs/architecture/mop.md` — canonical reference for
  Chalk::MOP. Structure:
  - Overview: what the MOP is and why it exists
  - Metaobject family (Class, Field, Method, Sub, Import,
    Phaser::Adjust) with accessor tables
  - Construction protocol (responsibility-distributed declare_*
    methods)
  - Resolution protocol (find_method, ancestors,
    resolve_adjust_blocks)
  - Graph-owner composition pattern and `Graph::build` algorithm summary
  - Per-graph hash-cons scope
  - Prior art references (B::MOP, HotSpot ci-layer, Graal
    HostedUniverse, TurboFan JSHeapBroker)

- **Update `ARCHITECTURE.md`:**
  - Add the MOP as a load-bearing architectural layer alongside
    Graph and semirings.
  - Update the "Three-Layer Compilation Pipeline" description to
    reflect that the parser emits the MOP, not a raw IR tree.
  - Update the Design Principles section if needed.

- **Update `docs/architecture/parsing-pipeline.md`:**
  - Semantic actions build the MOP (not independent metadata
    structs).
  - The MOP is the output of parsing.
  - Update examples that show `$factory->make(...)` to show
    `$method->merge(Node::Foo->new(...))` or
    `$method->graph->merge(...)`.

- **Update `docs/architecture/ir-lowering.md`:**
  - Codegen reads the MOP. `generate($mop)` is the entry point.
  - Per-method graphs are owned by MOP::Method.
  - `->body()` reader pattern is replaced by `$method->graph()`
    walks.

- **Update `CONTRIBUTING.md`:**
  - New "where do fixes belong" entries: MOP construction on the
    scope that owns the thing; graph construction on the graph-
    owner; resolution on Class.
  - Reference the MOP architecture doc for new contributors.

- **Update the D3 spec
  ([`2026-04-20-program-graph-of-graphs-design.md`](2026-04-20-program-graph-of-graphs-design.md)):**
  - Mark resolved open questions (namespace = Chalk::MOP, per-class
    hash-cons committed, etc.).
  - Update the closing sentence from "implementation sequencing ...
    is the subject of a follow-up plan document, to be written
    after this design is accepted" to point at this plan by name.

- **Update `docs/optimization.md`:**
  - Optimizer pass contract is `run($X) → $X` for the scope level.
  - MOP is the program-scope input type for whole-program passes.

- **Memory file maintenance:**
  - Review the project-state memories listed in
    `/home/perigrin/.claude/projects/-home-perigrin-dev-chalk/memory/MEMORY.md`
    for pre-MOP references that need updating.
- **Scaffolding cleanup:**
  - Delete `t/fixtures/codegen-goldens/` — the byte-compat golden
    from Phase 4 has served its forensic purpose across Phases 5–7
    and is no longer needed now that the new codegen is the
    canonical reference.
  - Delete `docs/plans/2026-04-21-phase0-test-baseline.md` if it
    exists as a standalone doc. If it was a commit rather than a
    doc, nothing to delete.
- **Tests (doc-verification):**
  - `t/docs/mop-architecture-exists.t` — asserts
    `docs/architecture/mop.md` exists and references each
    metaobject type by name (`Chalk::MOP::Class`,
    `Chalk::MOP::Method`, etc.). Small, cheap regression against
    doc decay.
  - Regression invariant: every existing test green at Phase 7
    exit remains green at Phase 8 exit.

**Exit criteria:**
- `docs/architecture/mop.md` exists and is complete.
- No doc in `docs/` references the pre-MOP world except in explicit
  historical context (e.g., this plan's *Supersedes* section).
- D3 spec's open questions section reflects what was decided during
  migration.
- CONTRIBUTING.md points new contributors at the MOP architecture
  doc.

**Polymorphic-migration criteria addressed:** none directly;
doc alignment for the full migration.

## Definition of done

This migration earns its weight by replacing ad-hoc patches with
principled solutions and by reducing coupling across compiler
layers. It does not ship a user-facing feature — Chalk is still
pre-user — but it establishes the IR contract that all subsequent
codegen, optimization, and self-hosting work depends on.

### What success means

**The MOP is the compilation-IR contract for Chalk's Perl subset.**
Chalk's subset is a strict subset of Perl
(`docs/chalk-grammar-spec.md`). The MOP describes what Chalk can
compile today — no more. Within the subset, any frontend that
parses correctly produces an equivalent MOP; Chalk's backend
consumes any conforming MOP to produce equivalent output.

- Chalk's Earley parser is the primary frontend.
- A hand-constructed MOP (via `$mop->declare_class(...)->declare_method(...)`
  etc., with no parser involved) is a valid input to codegen. This
  is the minimum verifiable form of the frontend-agnostic property.
- No phase of this migration introduces coupling that a different
  frontend over the same subset couldn't accommodate. The MOP's
  public API is the contract; its internals are implementation.

**What this migration does NOT claim:**

- The MOP does not describe all of Perl. Features excluded from
  Chalk's subset (`require`, string `eval`, symbolic references,
  `bless`, `@INC` hooks, `AUTOLOAD`, runtime class mutation) are
  not representable and are not meant to be.
- The MOP is not committed to compatibility with any specific
  second frontend. `perl5-son` + `B::MOP` + `B::SON` is a
  *plausible* second frontend — the equivalence is
  `Chalk = Earley + MOP + Graph + codegen`,
  `perl5-son-over-same-subset = B + MOP + Graph + codegen`. But
  that integration is future scope, contingent on perl5-son's own
  timeline and on Chalk's subset-compiler being working first.

**Why name perl5-son at all then?** Because it grounds the design
intent. The MOP is deliberately not Chalk-private; it's the IR for
Chalk's Perl subset. Keeping that horizon visible during the
migration prevents inadvertent coupling to the Earley frontend, even
though no other frontend is plugged in today.

**Later scope, not this migration:** once Chalk-the-subset is
working end-to-end, extending the MOP to cover additional Perl
features (while keeping closed-world exclusions) may become
valuable — Perl's own compiler then serves as an oracle for
correctness. That is a future project, not a commitment of this
plan.

### Coupling reductions delivered

- **Codegen no longer reads parse-time state.** The `($sa, $ctx)`
  backchannel on `generate_c_files` and `generate_with_cfg` is
  eliminated (Phase 4). Codegen consumes a fully-resolved MOP
  without reaching into the parser's machinery.
- **Optimizer passes take typed inputs.** Ad-hoc bundle hashes
  (`{class_name, ir, ...}`) are replaced by `run($mop) → $mop` and
  `run($graph) → $graph` (Phase 5). Passes compose by contract, not
  by convention.
- **Shim dispatch eliminated.** Runtime translation of Constructor
  classes via `Chalk::IR::Shim` is replaced by direct MOP
  construction at the call site (Phases 1 and 6). No runtime type
  dispatch for structural declarations.
- **Metadata structs collapse into MOP metaobjects.**
  `Chalk::IR::ClassInfo` and siblings are deleted (Phase 6); the
  MOP *is* the metadata, not a wrapper over it.

### Ad-hoc patches replaced with grounded solutions

- **`body_stmts` BFS seeding** (prototype workaround for incomplete
  SSA) → **Click's SSA construction algorithm** implemented in
  `Graph::build` (Phase 3). The graph is reachable from `start`
  through the cache, the way SoN graphs are supposed to be.
- **`Graph::nodes()` consumer-traversal exclusion** (workaround for
  shared hash-cons scope) → **per-graph hash-cons scope** (Phase
  2). Consumers are graph-local by construction; bidirectional
  traversal is restored safely (Phase 7). Precedent: HotSpot's
  `Compile` scope, `PhaseGVN` table.
- **Symbolic name strings on Call nodes** (resolved later by name
  lookup) → **resolved `Chalk::MOP::Method` handles** at
  construction time (Phase 4). Precedent: HotSpot `ciMethod*`,
  Graal `HostedMethod`, TurboFan `SharedFunctionInfoRef`.
- **Class-body placement enforcement as "planned Structural semiring
  work"** → **structurally impossible to construct a field without
  a `$class` handle** (already delivered in D2). The API shape is
  the invariant.
- **`_build_method_graph` as a helper on Actions.pm** (graph
  construction scattered across the SemanticAction class) → **a
  `Graph::build` method on the graph that the metaobject owns**
  (Phase 3). The algorithm lives with the thing it builds.

### Invariants structurally enforced

- **"Field only inside class"** — `Class::declare_field` requires a
  class handle; no other API path exists.
- **"Methods belong to classes, subs belong to packages"** — both
  declared on `Class`; top-level subs live on the implicit `main`
  class.
- **"Imports are class-scoped"** — `declare_import` is on `Class`,
  matching Perl's per-package `use` semantics.
- **"Cross-method references are resolved handles"** — Call nodes
  carry `Chalk::MOP::Method` objects, not strings; resolution
  failures fail at parse time, not at codegen.

### Foundation enabled for subsequent work

- **Self-hosting validation** can run end-to-end (Phase 3c revives
  the currently-crashing pipeline tests). Actual self-hosting is
  downstream work, but this migration stops being the blocker.
- **Whole-program optimizer passes** (inlining, call-graph analysis,
  cross-method escape analysis) become expressible — they take
  `$mop` and walk classes/methods directly.
- **Semiring-level MOP enrichment** (TypeInference writing inferred
  return types onto `Method::return_type`, etc.) becomes possible
  via the Context-accessible MOP reference.
- **Downward MOP extension** — `Chalk::MOP::LocalVar`,
  `Chalk::MOP::Scope`, per-expression type metaobjects — becomes
  feasible without another architectural migration.

## Acceptance criteria (rollup)

The migration is complete when:

- All 9 criteria from the polymorphic-migration plan
  ([`2026-04-04-son-ir-polymorphic-migration.md`](2026-04-04-son-ir-polymorphic-migration.md))
  are met, as mapped across Phases 1–7.
- `Chalk::MOP` is the primary construction and consumption API for
  program structure.
- Targets conform to `generate($mop) → HashRef[Str]`.
- Optimizer passes conform to `run($X) → $X`.
- `docs/architecture/mop.md` exists.
- No reference to `Chalk::IR::Shim`, `compat_class`,
  `MethodInfo.body`, `ClassInfo.body`, `body_stmts` (in Graph), or
  `($sa, $ctx)` backchannel anywhere in `lib/` or `docs/`.

## Risks

### Full SSA is the hardest phase

Phase 3 is the only phase that is genuinely new compiler work rather
than plumbing redirection. The algorithm design exists (Click's
Phase 4a, sketched in the phase4 plan doc) and the Scope class
already has the sentinel machinery, but writing a correct SSA
construction pass is non-trivial. If Phase 3 stalls, Phases 4–7
stall with it.

Mitigation: Phase 3 is split into three sub-phases (3a, 3b, 3c),
each with independent acceptance criteria and its own test set. A
migration interrupted between sub-phases is in a defined, testable
state — not in a half-built SSA pass. 3a delivers control-chain
threading for linear code; 3b adds if/else Phi insertion; 3c adds
loop Phi insertion.

### Per-class hash-cons boundaries

Phase 2 introduces per-class scope. Some nodes that are genuinely
program-wide (literal `0`, literal empty string) get duplicated
across classes. This is a space cost, not a correctness risk, but
if profiling shows it matters, a constant-lifting optimization can
promote shared constants to a MOP-level factory. That's optional
future work, not blocking.

### Phase 1 threading of MOP through Context

Phase 0 adds `mop` as a Context field; Phase 1 threads the MOP
instance through the root Context at parse start. The primary risk
is missing a propagation site — if some `extend` or `multiply` path
forgets to propagate `mop`, downstream Contexts will have `mop` undef
and semirings will silently fail to enrich metaobjects. Mitigation:
the `Context::extend` method already has a uniform opts-handling
pattern for every field (token, is_zero, error); `mop` joins that
pattern. Tests assert `mop` propagation across several Context-
chain depths.

### Codegen byte-compatibility

Phase 4 must preserve deterministic output for the existing
green-eval test set. Regression would mean a real behavior change,
not just a plumbing swap. Mitigation: run the full self-hosting
validation after Phase 4 lands and before Phase 5 begins; diff
outputs against a pre-migration golden.

## Not in scope

- **D2** — class-body context enforcement beyond what the
  construction API structurally provides. Closed as resolved; no
  further work needed.
- **Multi-unit compilation** — the MOP owns one compilation unit.
  Cross-unit inheritance is future scope.
- **Non-ADJUST phasers** — BEGIN/END/CHECK/INIT/UNITCHECK are out of
  scope.
- **Roles** — namespace reserved in the MOP; no implementation.
- **X3 (DepChaser)** — deferred; becomes trivial after the MOP
  exists, but not part of the migration itself.
- **X5 (regex-vs-division)** — orthogonal to the MOP; tracked
  separately.
- **X9 (semirings to Context → Context)** — architectural surgery on
  a different axis; tracked separately.
- **A packaging layer for `generate_distribution`** — Phase 4 focuses
  on code emission; CPAN-shape packaging is separate future work.

## Future extensions enabled by this migration

This migration lands the MOP at class scope (`Chalk::MOP::Class`,
`Method`, `Field`, `Sub`, `Import`, `Phaser::Adjust`) and makes it
Context-accessible for all semirings. Two downstream extensions are
structurally enabled by that foundation but deliberately out of this
migration's scope:

### Downward extension of the MOP

The MOP could extend below class scope to include compile-time
entities that multiple layers coordinate on but that currently
communicate through transient `Context.annotations`:

- `Chalk::MOP::LocalVar` — named variables within a method scope,
  with inferred type, lifetime information, and liveness analysis
  results. Currently tracked implicitly through `Chalk::Bootstrap::Scope`
  bindings and TypeInference annotations; a metaobject would make
  the information durable post-parse.
- `Chalk::MOP::Scope` — lexical scope boundaries as first-class
  metaobjects. `Chalk::Bootstrap::Scope` today is closer to a
  functional-scope runtime than a compile-time metaobject; the
  latter is a reasonable evolution.
- Per-expression type annotations attached to graph nodes via the
  MOP rather than to Context annotations.

Each would need its own design spec. The Context-accessible MOP
reference introduced in Phase 0 makes the extension feasible without
another architectural migration — any future `MOP::LocalVar` slots
onto the existing MOP, and semirings already know how to reach it.

Whether downward extension is worth doing is a separate question
from *whether it's possible*. The MOP's role as a compile-time
coordination surface suggests the answer is "yes for entities that
multiple layers need to talk about, no for entities that live
entirely within one layer." LocalVars satisfy the "multiple layers"
test (TypeInference, Structural, codegen, optimizer); statements
don't.

### Richer semiring-to-MOP enrichment

Within this migration, the obvious MOP-enrichment points are:

- SemanticAction builds the class/method/field structure (Phases 1–4).
- Codegen and optimizer passes consume the MOP (Phases 4–5).

Other semirings have enrichment opportunities that are out of scope
but become trivial follow-ups once the MOP is Context-accessible:

- TypeInference could write inferred `Method::return_type` values
  and `Field::type` values onto metaobjects directly, replacing the
  post-parse Context walk codegen currently needs.
- Structural could annotate methods with side-effect classifications
  (pure, effectful, may-throw) onto the Method metaobject.
- Precedence has no obvious MOP target today, but that door is open.

These are small local improvements, not a migration. They would land
as focused per-semiring PRs post-migration.
