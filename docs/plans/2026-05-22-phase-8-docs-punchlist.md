# Phase 8 Documentation Punch List

**Date:** 2026-05-22
**HEAD on `pu` at writing:** `e521f127`
**Purpose:** Catalog every documentation site that drifted during the
Phase 7→7d factory-unification arc, so the Phase 8 doc update is
scoped before any prose lands.

This is a **read-only audit**. No documentation files are modified by
this document. Each entry below names a file, what it currently
claims, what is now true, and the smallest change that resolves the
drift.

The April-19 ARCHITECTURE.md and the April-20 architecture subdocs
predate the MOP-as-first-class work. They describe an IR that lives
under metadata structs (`MethodInfo->body`, `ClassInfo`, `SubInfo`)
hash-consed through what was effectively a process-wide factory.
That picture is no longer accurate.

The post-Phase-7d reality:

- `Chalk::IR::NodeFactory` is a **per-parse, per-instance** object,
  not a singleton.
- `Chalk::Bootstrap::IR::NodeFactory` is **deleted**.
- `SemanticAction::set_factory($f)` is the canonical injection point
  (parallel to `set_mop`).
- `Chalk::MOP::{Class,Method,Sub,Field}` is the canonical container
  for code; each `MOP::Method` and `MOP::Sub` owns a `$factory` and a
  `$graph`.
- `Chalk::Bootstrap::Context` carries `factory` and `mop` fields and
  threads them upward through `extend()`.
- `Chalk::IR::Graph::nodes()` is **bidirectional** with a
  cache-membership filter on consumer edges.
- Per-parse factory ownership means tests no longer need a singleton
  reset; each parse gets a fresh factory.

What is NOT yet true (and Phase 8 should not pretend otherwise):

- Codegen still reads `MethodInfo->body` arrayrefs, not
  `$mop->classes->methods->graph->nodes`. Migrating this is Phase 9
  / "codegen reads MOP directly" — separate scope.
- `Chalk::IR::Node->compat_class` still exists as a field; only
  setters were stripped.
- `ClassInfo`/`MethodInfo`/`SubInfo`/`UseInfo`/`Program` metadata
  structs still exist; codegen consumes them.

So Phase 8 documents the **factory/MOP/Context layer** as it now is,
and leaves the codegen-reads-MOP migration to its own future plan.

---

## Sites to update

### 1. `ARCHITECTURE.md` (top-level)

**Currently:**

- Diagram shows Parser → SoN IR → Target Lowering; no mention of MOP.
- "File Map" lists `lib/Chalk/IR/NodeFactory.pm` (correct) but does
  not list `lib/Chalk/MOP/{Class,Method,Sub,Field,Phaser}.pm`.
- "Key Design Principles" describes immutability, determinism,
  progressive filtering — but does not mention per-parse factory
  ownership as a principle.
- No mention of `Chalk::Bootstrap::Context` carrying factory/MOP.

**Now true:**

- The MOP is a first-class layer between SemanticAction and Target.
  SemanticAction builds `MOP::Class` / `MOP::Method` / `MOP::Sub` /
  `MOP::Field` instances; each method/sub owns a `Graph` and a
  `NodeFactory`. Target backends consume the MOP (eventually
  directly; today still via metadata-struct shims).
- Per-parse factory ownership is a load-bearing correctness property
  (the singleton's process-wide cache was the root cause of the
  14-day bidirectional-`nodes()` blocker).

**Smallest fix:**

- Add a MOP row to the system-overview diagram between "Sea of
  Nodes IR" and "Target Lowering". Wording suggestion:
  `SoN IR (owned by MOP::Method / MOP::Sub graphs)`.
- Add to "Key Design Principles" a bullet:
  *Per-parse ownership.* The NodeFactory and IR Graph are
  per-parse instances. Identity of nodes is meaningful only
  within a single parse; cross-parse comparison is by
  `content_hash`, not refaddr.
- Extend the "File Map" with rows for:
  - `lib/Chalk/MOP/Class.pm`
  - `lib/Chalk/MOP/Method.pm`
  - `lib/Chalk/MOP/Sub.pm`
  - `lib/Chalk/MOP/Field.pm`
  - `lib/Chalk/MOP/Phaser.pm`
  - `lib/Chalk/IR/Graph.pm` already listed — confirm.
- Add a new "Detailed Architecture Documents" row:
  `[MOP Layer](docs/architecture/mop-layer.md)` — this doc does
  not exist yet (item 7 below).

### 2. `CONTRIBUTING.md`

**Currently:**

- "Where to Put Fixes" table ends at `Target emitter (Target/Perl.pm,
  Target/XS.pm)`. No row for fixes that belong in the MOP layer
  (e.g., "method has wrong signature in generated code" → MOP).
- No mention of how/where to add a new IR op (would touch
  `NodeFactory`'s `%INPUT_SPECS` keyword translation, which is new
  surface from Phase 7c).

**Now true:**

- A fix that says "the method exists but its body is wrong" usually
  belongs in SemanticAction → MOP::Method construction. A fix that
  says "the class is missing a field" belongs in MOP::Class
  construction. Codegen is downstream of MOP.
- Adding a new IR op now requires registering it in `%INPUT_SPECS`
  if it should accept named-keyword construction (which is how
  Actions builds nodes via `$typed->make`).

**Smallest fix:**

- Add a row to the "Where to Put Fixes" table:
  `Method/class structure wrong in generated output` →
  `MOP construction in SemanticAction (Actions.pm + MOP::*)`.
- Add a row: `IR op exists but Actions can't construct it via make()`
  → `%INPUT_SPECS in Chalk::IR::NodeFactory`.

### 3. `docs/architecture/sea-of-nodes-ir.md`

**Currently (line 175 onwards, "NodeFactory: Hash Consing Protocol"):**

- "`Chalk::IR::NodeFactory` is the single factory through which all
  nodes must be created."
- "The factory is a regular Perl object; tests that need a clean
  cache simply instantiate a new `Chalk::IR::NodeFactory` object.
  There is no global singleton to reset."

The second sentence was aspirationally true in April but operationally
false for most of the codebase until Phase 7d. It is now actually true
end-to-end. Good news: this section needs less work than expected.

**Drift:**

- Section 5 (lines ~248 onwards) introduces "metadata structs" as
  the canonical representation of program structure: `Program`,
  `ClassInfo`, `MethodInfo`, `SubInfo`, `UseInfo`, `FieldInfo`.
  This is still **partially** accurate — those structs exist and
  codegen still reads them — but the canonical container of code is
  now the MOP layer. Each `ClassInfo` is mirrored by a `MOP::Class`;
  each `MethodInfo` has a corresponding `MOP::Method` whose
  `$graph` is the source of truth for the method body.
- Specifically, the table at line ~270 ("`MethodInfo` has `body`,
  `params`, `signature`...") doesn't mention that `MOP::Method` is
  the parallel structure that *also* holds `$graph` and `$factory`.
- "`Graph.nodes()` traversal follows only `inputs` edges in its DFS"
  (line 399) — **this is now false.** Post-Phase-7b, `Graph::nodes()`
  is bidirectional with a cache-membership filter. The
  serializer's `_all_nodes_topo()` workaround for `Phi.region` may
  still be needed (separate concern) but the base behavior changed.

**Smallest fix:**

- Add a new subsection after "NodeFactory: Hash Consing Protocol"
  titled "Per-parse Ownership" describing how the factory is
  created in `Actions::ADJUST`, injected into SemanticAction via
  `set_factory`, propagated into `_one_ctx` and via the Context
  `factory` field. One paragraph.
- Update the section on metadata structs (line ~248+) to add a
  paragraph distinguishing the **metadata struct** layer
  (`MethodInfo`, etc., still read by codegen today) from the **MOP**
  layer (`MOP::Method`, etc., the post-Phase-7d canonical container
  of code). State that codegen migration to the MOP is future work
  (link to Phase 9 plan once it exists).
- Rewrite line 399's "follows only `inputs` edges" to describe the
  current bidirectional walk with cache-membership filter. The
  `Phi.region` concern is a separate point about the serializer's
  topological ordering and stays.

### 4. `docs/architecture/context-comonad.md`

**Currently:**

- Describes Context as the parse-history data structure with
  `extract`/`extend`/`duplicate`.
- Says "A single shared Context tree flows through every semiring"
  (line ~18).
- No mention of `factory` field, no mention of `mop` field, no
  mention of `extend` propagating these fields.

**Now true:**

- `Chalk::Bootstrap::Context` carries `factory` and `mop` fields.
  `_one_ctx` seeds the per-parse factory; `extend()` carries it
  upward. This is how Actions code reachable only through Context
  (no direct `$self->factory` access) still gets at the right
  factory instance.

**Smallest fix:**

- Add a new section "Field Threading" describing how `factory` and
  `mop` are carried by Context. Explain the rule: these fields are
  set at parse start (in `_one_ctx`) and inherited unchanged by
  every `extend()` call. Semiring code reads them via
  `$ctx->factory` and `$ctx->mop`.

### 5. `docs/architecture/ir-lowering.md`

**Currently (line 62):**

- Already flags that codegen reads `MethodInfo->body` and that this
  needs to move to `Graph`. Calls out the polymorphic-migration
  plan as the tracking doc.

**Drift:**

- The "polymorphic-migration plan" reference (line 63) points to
  `2026-04-04-son-ir-polymorphic-migration.md`, which has been
  superseded by `2026-04-21-chalk-mop-migration-plan.md`. The
  citation is stale.
- Line ~281: "Per-method CFG schedules (from
  `MethodInfo->graph()->schedule()`) are merged additively" —
  `MethodInfo->graph()` is still present as a delegating accessor,
  but the canonical owner is now `MOP::Method->graph`. Worth a
  parenthetical clarifying that `MethodInfo->graph()` reads from
  the MOP-side graph.
- Line ~341 and ~602: references to `NodeFactory->make(...)`. These
  are still correct in API surface but pre-date the per-parse
  ownership story. Could note that callers retrieve the factory via
  `$ctx->factory` or `$self->factory`.

**Smallest fix:**

- Update line 63's citation to
  `docs/plans/2026-04-21-chalk-mop-migration-plan.md`.
- Add a one-sentence parenthetical at line ~281 noting that
  `MethodInfo->graph()` reads from the MOP-side `MOP::Method->graph`.
- Optionally: at first mention of `NodeFactory->make`, add a
  parenthetical: "(typically retrieved as `$ctx->factory` in
  semiring code or `$self->factory` in Actions/MOP code)".

### 6. `docs/architecture/parsing-pipeline.md`

**Status: not read yet — needs scan during Phase 8 execution.**

**Expected drift:** The pipeline doc covers the 5 semirings and
FilterComposite. It is unlikely to mention factory or MOP at all,
which is correct for that layer's scope. The one likely site of
drift is any mention of how SemanticAction produces output — if it
says "produces IR" without mentioning that the IR is owned by the
per-parse factory and built into MOP::Method/Sub graphs, a one-line
addition fixes it.

**Action:** Read the file during execution; add at most one
paragraph at the end of the SemanticAction section pointing to
`mop-layer.md` (item 7) for what SA's output actually goes into.

### 7. `docs/architecture/mop-layer.md` — **NEW FILE**

**Currently:** Does not exist.

**Now true:** The MOP is a layer that:

- Lives between SemanticAction and codegen.
- Provides `Class`, `Method`, `Sub`, `Field`, `Phaser` containers.
- Each `Method` and `Sub` owns a `$graph` (Chalk::IR::Graph) and a
  `$factory` (Chalk::IR::NodeFactory).
- Is constructed during the SemanticAction pass via Actions code
  calling MOP constructors.
- Is exposed to semirings via `Chalk::Bootstrap::Context.mop`.
- Is set on SemanticAction via `set_mop($m)` mirroring `set_factory`.

**Smallest fix:**

- Create the file with these sections:
  1. Overview — what the MOP is, why it exists.
  2. Class structure — `MOP::Class`, fields, methods, subs, phasers,
     imports.
  3. Method/Sub structure — `MOP::Method` and `MOP::Sub`, including
     their `$graph` and `$factory` fields and the
     `make`/`make_cfg` delegators.
  4. Field structure — `MOP::Field`, signature, default expr.
  5. Phaser structure — `MOP::Phaser` (ADJUST, etc.).
  6. Per-parse ownership — how the MOP and its child factories are
     created at parse start and torn down at parse end. Reference
     `Actions::ADJUST` and `SemanticAction::set_mop` / `set_factory`.
  7. Relationship to metadata structs — `ClassInfo`/`MethodInfo` etc.
     still exist for legacy codegen consumption; MOP is canonical
     going forward.
  8. What's not yet migrated — codegen still reads metadata struct
     `body` arrayrefs; this is Phase 9 work.

**Estimated size:** 200-300 lines, comparable to
`context-comonad.md` (560 lines is the upper bound for the
ambitious version).

### 8. `docs/architecture/ambiguity-classes.md` line 305

**Currently:** "for incomplete MOP/introspection. The proper
resolution is MOP-aware..."

**Status:** This is the only MOP mention in any architecture subdoc.
Likely consistent with reality but worth a re-read during Phase 8 to
confirm the cross-reference still makes sense.

---

## Out-of-scope (do NOT touch in Phase 8)

- **Plan docs in `docs/plans/`.** These are historical records of
  the work that landed. Audit docs and phase-by-phase migration
  plans are by definition tied to a moment in time. Updating them
  destroys their value as a record.
- **Historical plan docs that were consolidated into `docs/plans/`
  on 2026-05-25 (previously under `docs/superpowers/plans/` and
  `docs/superpowers/specs/`).** Same reasoning — historical.
- **Memory docs in `memory/`.** Memory is updated by the
  conversation that writes it, not by a phase doc update pass.
- **`CLAUDE.md`.** Project-level instructions; the relevant entries
  (MOP migration status, prototype commit warning) are still
  accurate as of Phase 7d. If anything, they may need expansion in
  a future pass — but not as part of Phase 8 doc-drift cleanup.
- **`README.md`.** Not yet reviewed. Confirm during execution it
  doesn't make MOP-ignorant claims; otherwise leave alone.
- **Codegen-reads-MOP migration.** This is Phase 9. Touching it
  here would conflate two scopes.
- **`compat_class` field removal.** Same — separate cleanup.

## Recommended execution order

1. Create the new `docs/architecture/mop-layer.md` (item 7). It is
   the structural prerequisite for the cross-references the other
   doc updates want to add.
2. Update `ARCHITECTURE.md` (item 1). Adds the MOP row to the
   table, the file-map rows, and the new principle.
3. Update `docs/architecture/sea-of-nodes-ir.md` (item 3). The
   `Graph::nodes()` correction at line 399 is the most
   user-impacting fix.
4. Update `docs/architecture/context-comonad.md` (item 4). Add the
   Field Threading section.
5. Update `docs/architecture/ir-lowering.md` (item 5). Citation
   fix and parentheticals.
6. Update `CONTRIBUTING.md` (item 2). Add the two table rows.
7. Read `docs/architecture/parsing-pipeline.md` (item 6) and
   `docs/architecture/ambiguity-classes.md` line 305 (item 8).
   Add at most one paragraph each if drift is confirmed.

## Verification

- After each file change, grep the repo for any remaining
  references to the changed claim. E.g., after changing
  `Graph::nodes()` description, `ag "follows only.*inputs"`
  should return nothing.
- After landing the MOP layer doc, `ag -l "MOP::Method|MOP::Sub"
  docs/architecture/` should return at least
  `mop-layer.md` and `sea-of-nodes-ir.md`.
- After all changes, no architecture doc should contain
  `Chalk::Bootstrap::IR::NodeFactory` (the deleted singleton).
  Check: `ag "Chalk::Bootstrap::IR::NodeFactory" docs/architecture/`
  returns empty.

## Notes for the doc-update session

- The Phase 7d arc was driven by the singleton's process-wide cache
  causing `Graph::nodes()` to leak cross-graph nodes. The
  architecture docs should not just remove the singleton mention —
  they should explain *why* per-parse ownership matters
  (membership-correctness for bidirectional traversal). One
  sentence in the new "Per-parse Ownership" subsection of
  `sea-of-nodes-ir.md` is the right place.
- The MOP layer was built incrementally across Phase 4-7. The new
  `mop-layer.md` doc should describe the architecture as it now
  stands, not the history of how it got there.
- ABOUTME comments at the top of new doc files: two lines, each
  starting with `<!-- ABOUTME: ` (matching existing
  `context-comonad.md` convention).
