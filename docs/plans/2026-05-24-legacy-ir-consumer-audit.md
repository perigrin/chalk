# Legacy IR Consumer Audit

**Date:** 2026-05-24
**For:** Phase 6 scope planning — identifies production code that
must migrate before `Chalk::IR::Program` and the Info-struct types
can be deleted.
**Status:** Read-only audit. No code modified.

## Scope

Files audited: all `lib/` files referencing any of `Chalk::IR::Program`,
`Chalk::IR::ClassInfo`, `Chalk::IR::MethodInfo`, `Chalk::IR::SubInfo`,
`Chalk::IR::FieldInfo`, `Chalk::IR::UseInfo`, or reading `->body` on
either a legacy Info struct or a `MOP::Method` / `MOP::Sub`.

**Production-code modules with legacy consumers: 5**

(plus the 6 legacy type definitions themselves, which are passively
"consumed" only as type definitions and are inert — they ship no code
that would itself need migration; their deletion is the goal, not a
migration target.)

The 5 production-code consumers are:

| Module | Role |
|---|---|
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | parser actions that **construct** the legacy types |
| `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` | Perl emit target — owns `_generate_from_mop`, `_emit_*_decl`, `_emit_program` |
| `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` | shared helpers (Target::C base) — walks `ClassInfo.body` for analysis |
| `lib/Chalk/Bootstrap/Perl/Target/C.pm` | C/XS emit target — consumes the Info-struct body directly |
| `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` | Phase 5 IR optimizer — synthesizes `ClassInfo` from MOP then walks legacy |

Most-consumed types (legacy-reference count across all 5 modules):
`MethodInfo` (~27 refs), `SubInfo` (~24), `ClassInfo` (~23),
`FieldInfo` (~13), `Program` (~14), `UseInfo` (~9).

Most-consumed field: `->body` (26 total reads across the 5 modules).

## Summary table

| Module | Legacy-type refs | `->body` reads | Patterns present | Migration estimate |
|---|---|---|---|---|
| `Chalk::Bootstrap::Perl::Actions` | 44 | 3 | construction (source of truth), accessor reads, type checks | large (>500 LOC affected) |
| `Chalk::Bootstrap::Perl::Target::Perl` | 34 | 7 | synthesis (MOP→legacy), construction, accessor reads, type checks, isa | large |
| `Chalk::Bootstrap::Perl::Target::EmitHelpers` | 13 | 2 | accessor reads on `ClassInfo.body`, type-check dispatch | medium |
| `Chalk::Bootstrap::Perl::Target::C` | 15 | 6 | accessor reads, isa-dispatch, dual-path with `Constructor` fallback | medium |
| `Chalk::Bootstrap::Optimizer::StructPromotion` | 26 | 8 | **synthesis** (MOP→legacy), construction (rebuild Program), accessor reads | medium |

## Per-module findings

### `lib/Chalk/Bootstrap/Perl/Actions.pm`

**Role in production:** parser semantic-action methods. Every parsed
Perl source file produces a `Chalk::IR::Program` rooted at `Program()`,
populated by `ClassInfo`/`MethodInfo`/`SubInfo`/`FieldInfo`/`UseInfo`
constructed bottom-up in their respective action methods. Actions
*also* populate the MOP (see `ClassBlock` lines 660-744), so the
parser currently produces **both** legacy IR and MOP for every parse —
the legacy IR is the duplicate.

**Legacy types consumed:** all six (Program, ClassInfo, MethodInfo,
SubInfo, FieldInfo, UseInfo).

**Patterns:**

- **Construction sites** (the canonical sources of these objects):
  - `Actions.pm:278` — `Chalk::IR::Program->new(...)` in `Program($ctx)`
  - `Actions.pm:564` — `Chalk::IR::UseInfo->new(...)` in `UseDeclaration($ctx)`
  - `Actions.pm:747` — `Chalk::IR::ClassInfo->new(...)` in `ClassBlock($ctx)`
  - `Actions.pm:821` — `Chalk::IR::MethodInfo->new(...)` in `MethodDefinition($ctx)`
  - `Actions.pm:896` — `Chalk::IR::SubInfo->new(...)` in `SubroutineDefinition($ctx)`
  - `Actions.pm:1733` — `Chalk::IR::FieldInfo->new(...)` in `VariableDeclaration($ctx)`
  - `Actions.pm:2264` — `Chalk::IR::FieldInfo->new(...)` (default-value path) in `AssignmentExpression($ctx)`

- **Body-field population** (writes `body => $fixed_body` into MethodInfo / SubInfo):
  - `Actions.pm:825` — `body => $fixed_body` on MethodInfo
  - `Actions.pm:899` — `body => $fixed_body` on SubInfo
  - The body arrayref is also passed through to the MOP at
    `Actions.pm:702`, `Actions.pm:711` (`body => $item->body()`) when
    populating MOP::Method / MOP::Sub. This is the parser-side
    population of `MOP::Method->body` and `MOP::Sub->body` referenced
    in the design doc Phase 6 deletion list.

- **`_finalize_body_graph`** (Actions.pm:819, 894, 914) — builds the
  per-method/per-sub graph and is the same machinery that populates
  `MethodInfo.graph` and `SubInfo.graph`. It also populates the
  per-graph schedule (lines 920-944) which is consumed by the Perl
  target via `_emit_method_decl`/`_emit_sub_decl` (Perl.pm:983,
  Perl.pm:1006). The schedule itself is *not* a legacy artifact, but
  the indirection where the schedule rides on `MethodInfo.graph`
  rather than on `MOP::Method.graph` is.

- **Type checks** (used to route values into the Program / class
  body): `Actions.pm:227-232`, `294-299`, `339-344`, `386-388`,
  `648-654`, `671-720`, `2234`, `2263` — at least 7 distinct
  `isa Chalk::IR::*` dispatch sites.

- **MOP population reads from legacy struct** (Actions.pm:695-720):
  inside `ClassBlock`, after constructing each `MethodInfo`/`SubInfo`/
  `FieldInfo` item, the action immediately reads it back out
  (`$item->name()`, `$item->params()`, `$item->body()`,
  `$item->graph()`, `$item->attributes()`, `$item->default_value()`)
  to feed `$mop_class->declare_method/declare_sub/declare_field`.
  This is the same data being threaded through two parallel
  containers; the legacy struct exists only to be read in this block
  and by downstream consumers.

**Migration scope:**

Two orthogonal changes:

1. **Body population.** Either (a) populate `MOP::Method.body` /
   `MOP::Sub.body` from the same `_finalize_body_graph` machinery
   that produces the graph today, and stop populating Info-struct
   `body` fields; or (b) delete `MOP::Method.body` / `MOP::Sub.body`
   entirely and rely on the graph alone, with all consumers walking
   the graph. The design doc commits to (b) but flags that
   `_body_from_graph` currently misses non-VarDecl side-effects
   (Perl.pm:139-141), which means option (b) requires the
   Block-level control-chain fixup to cover all side-effect kinds
   before the body field can go.

2. **Stop constructing legacy Info-structs.** Once consumers
   downstream (Target::Perl `_generate_from_mop`, StructPromotion's
   `_class_info_from_mop_class`, Target::C, EmitHelpers) no longer
   require Info-structs, the construction sites in Actions.pm
   become dead code and can be deleted. `Program()` similarly
   becomes a no-op (or returns the MOP directly) once no consumer
   reads `Chalk::IR::Program` as the parse root.

The `ClassBlock` action's MOP population (lines 660-744) is the
template for what the parser will eventually do exclusively — it
already feeds the MOP. The legacy struct is the leftover.

**Blockers for deletion of legacy types:**

- `MethodInfo`, `SubInfo`, `FieldInfo`, `ClassInfo`, `UseInfo`,
  `Program`: all blocked. Actions.pm is the **producer** of all of
  these. Until consumers stop reading them, the producer must stay.

### `lib/Chalk/Bootstrap/Perl/Target/Perl.pm`

**Role in production:** the Perl emit target. Production calls
`generate($mop)` (line 86) which routes to `_generate_from_schedule`
for Chalk::MOP inputs. Legacy `Chalk::IR::Program` inputs route to
`_emit_program`. `_generate_from_mop` is **still defined** (line 96)
but the design doc states it has zero production callers since the
Phase 5b HANDOFF commit `2f35121f`; it remains alive only as the
byte-compat reference path for the golden corpus.

**Legacy types consumed:** Program, UseInfo, ClassInfo, FieldInfo,
MethodInfo, SubInfo.

**Patterns:**

- **Synthesis (MOP → legacy)** in `_generate_from_mop`:
  - Perl.pm:109 — `Chalk::IR::UseInfo->new` from `$import->module/args`
  - Perl.pm:127 — `Chalk::IR::FieldInfo->new` from `$cls->fields`
  - Perl.pm:146 — `Chalk::IR::MethodInfo->new` from `$cls->methods`
  - Perl.pm:159 — `Chalk::IR::SubInfo->new` from `$cls->subs` (class-scope subs)
  - Perl.pm:174 — `Chalk::IR::ClassInfo->new` aggregating the above
  - Perl.pm:192 — `Chalk::IR::SubInfo->new` for top-level subs
  - At each of those sites the synthesizer reads `$method->body` /
    `$sub->body` from MOP (Perl.pm:142, 155, 188) and falls back to
    `_body_from_graph` (Perl.pm:145, 158, 191) when body is absent.

- **`_body_from_graph`** (Perl.pm:623): graph-walking helper that
  reconstructs the body arrayref. Called only from
  `_generate_from_mop`. Self-contained but produces the same legacy
  arrayref shape.

- **Construction in `_generate_with_cfg` path:** the legacy
  Program path doesn't *construct* legacy types, it *requires* them
  as input (Perl.pm:91, 679 — `die ... unless $input isa Chalk::IR::Program`).

- **Accessor reads** on legacy types in emit helpers:
  - Perl.pm:748 — `$node->body()` on Program/ClassInfo in
    `_scan_aggregate_vars`
  - Perl.pm:742-745 — `$node->use_decls/classes/top_level_subs/other_stmts`
    in `_scan_aggregate_vars` (Program walker)
  - Perl.pm:949, 975, 1002 — `$node->body()` in `_emit_class_decl`,
    `_emit_method_decl`, `_emit_sub_decl`
  - Perl.pm:773-776 — `$ir->classes(), $ir->top_level_subs(), $stmt->name()`
    in `generate_distribution` (Program walker for class-name lookup)
  - Perl.pm:793-795 — `$node->use_decls()`, `$node->classes()`,
    `$node->top_level_subs()`, `$node->other_stmts()` in `_emit_program`

- **`isa` dispatch** (the heart of the legacy emit dispatch table):
  - Perl.pm:709-714 — `$ir_node isa Chalk::IR::{Program,UseInfo,ClassInfo,FieldInfo,MethodInfo,SubInfo}`
    guards in `_build_cfg_lookup`
  - Perl.pm:740-749 — Program/ClassInfo/FieldInfo dispatch in
    `_scan_aggregate_vars`
  - Perl.pm:774 — `$stmt isa Chalk::IR::ClassInfo` in `generate_distribution`
  - Perl.pm:882-900 — the `_emit_node` UseInfo/FieldInfo/MethodInfo/
    SubInfo/ClassInfo dispatch chain, calling `_emit_use_decl`,
    `_emit_field_decl`, `_emit_method_decl`, `_emit_sub_decl`,
    `_emit_class_decl` respectively

- **External callers**: `_generate_with_cfg` is only called from
  test files (`t/bootstrap/cfg-statements.t`); `_generate_from_mop`
  has no callers per the design doc and our search; `generate($input)`
  is the only externally-reached entry, and routes MOP inputs away
  from the legacy path already.

**Migration scope:**

Phase 6 of the scheduler plan already targets `_generate_from_mop`
and `_body_from_graph` for deletion (design doc §7, Phase 6, items
1-3). The remaining legacy surface in Target::Perl after Phase 6
finishes is:

- `_emit_program` and the `_emit_*_decl(InfoStruct)` helpers
  (lines 789-1096): these stay alive while `_generate_with_cfg`
  has any caller. Today the only callers are tests.
- `_generate_with_cfg` itself (line 677) and the `_cfg_lookup`
  machinery (lines 51, 695-721, 808-846): kept alive for Target::C
  and the legacy `Chalk::IR::Program` test path. Design doc lists
  these for Phase 7 deletion alongside the Info-structs.
- `_scan_aggregate_vars` (Perl.pm:726): only called from
  `_generate_with_cfg`. Dead-code-by-coupling once that path goes.
- `generate_distribution` (Perl.pm:767): walks Program to find a
  class name; called by tests/scripts; dies/falls back if input is
  not a Program. This is more legacy contract than the Phase 6
  list captures — flag for the Phase 7 deletion sweep.

**Blockers for deletion of legacy types:**

- `Chalk::IR::Program`: Target::Perl is one of three blockers
  (the other two are `_generate_with_cfg` callers in test land and
  `StructPromotion._find_class_decl` accepting Program-shaped IR).
- `Chalk::IR::ClassInfo` / `MethodInfo` / `SubInfo` / `FieldInfo` /
  `UseInfo`: Target::Perl `_emit_*_decl` reads them; once
  `_generate_from_mop` and `_emit_program` go, the emit-decl helpers
  have no callers in production and become deletable here.

### `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`

**Role in production:** parent class of Target::C (Target::C
`:isa(EmitHelpers)`). Provides shared analysis routines that walk a
class declaration's body to populate `$field_map`, `$_class_methods`,
`$_class_subs`, `%_class_scope_vars`, etc. — used by Target::C
during XS code generation. Target::Perl does not inherit from
EmitHelpers; it owns its own analogous helpers.

**Legacy types consumed:** ClassInfo, FieldInfo, MethodInfo,
SubInfo, Program.

**Patterns:**

- **Accessor reads** on `ClassInfo.body`:
  - EmitHelpers.pm:130 — `$class_decl->body()` in
    `_build_field_index_map`
  - EmitHelpers.pm:207 — `$class_decl->body()` in
    `_scan_class_methods`

- **Type-check dispatch**:
  - EmitHelpers.pm:121 — `$stmt isa Chalk::IR::ClassInfo` in
    `_find_class_decl` (walks `$ir->classes->@*` of a Program)
  - EmitHelpers.pm:138 — `FieldInfo` dispatch in `_build_field_index_map`
  - EmitHelpers.pm:218-219 — `MethodInfo`/`SubInfo` filter in
    `_scan_class_methods`
  - EmitHelpers.pm:224 — `$init isa Chalk::IR::SubInfo` (VarDecl
    initializer that turned out to be a mis-parented sub)
  - EmitHelpers.pm:232 — `MethodInfo` dispatch
  - EmitHelpers.pm:247 — `SubInfo` dispatch
  - EmitHelpers.pm:271 — `FieldInfo` dispatch for `:reader` scan

- **No construction sites.** EmitHelpers is purely a consumer.

**Migration scope:**

The two analysis routines (`_build_field_index_map`,
`_scan_class_methods`) need to take a MOP::Class instead of a
ClassInfo and walk `$cls->fields()`, `$cls->methods()`,
`$cls->subs()` directly. Field attributes are already on
`MOP::Field`; method params/return_type are on `MOP::Method`. The
only non-trivial case is the VarDecl-initializer-is-SubInfo branch
(EmitHelpers.pm:222-227) which handles mis-parented subs — this
requires checking how Actions.pm decides what becomes a top-level
`SubInfo` vs a VarDecl-init `SubInfo`, since the MOP equivalent
may not preserve that mis-parenting.

`_find_class_decl` (line 119) is a Program-walker that returns the
first ClassInfo — its callers in Target::C should be replaced by
direct iteration over `$mop->classes`.

**Blockers for deletion of legacy types:**

- `ClassInfo`, `FieldInfo`, `MethodInfo`, `SubInfo`: EmitHelpers
  is a consumer for all four; deletion requires migration of these
  routines to MOP inputs.
- `Program`: indirectly — `_find_class_decl` walks Program; once
  Target::C constructs its input differently, this goes too.

### `lib/Chalk/Bootstrap/Perl/Target/C.pm`

**Role in production:** generates `.c` and `.xs` files for compiled
classes. The entry point `generate($mop)` (C.pm:1479) accepts a
Chalk::MOP and **already** iterates `$mop->classes` directly — but
that method is a stub (returns minimal C/XS skeletons with
"/* method: NAME */" comments only). The real work is done by
`_generate_c_files($ir, $sa, $ctx)` (C.pm:1521), which expects an
`$ir` that is a `Chalk::IR::Program`-shaped tree. This is the
production XS-building path used by `script/build-chalk-so-generated`.

**Legacy types consumed:** UseInfo, ClassInfo, FieldInfo,
MethodInfo, SubInfo.

**Patterns:**

- **Accessor reads** on body:
  - C.pm:58 — `$class_decl->body()` in `_analyze_class`
  - C.pm:128 — `$method_decl->body()` in `_emit_method`
  - C.pm:1617 — `$class_decl isa Chalk::IR::ClassInfo ? $class_decl->body() : $class_decl->inputs()->[2]` (dual-path with Constructor fallback)
  - C.pm:1625 — `$item->body()` (SubInfo in class body)
  - C.pm:1774 — `$class_decl isa Chalk::IR::ClassInfo ? $class_decl->body() : ...` (same dual-path)
  - C.pm:2052 — `$class_decl->body()` for field iteration in XS BOOT

- **Type-check dispatch / `isa` reads**:
  - C.pm:79 — `$init isa Chalk::IR::SubInfo` in class-scope VarDecl filter
  - C.pm:98 — `$item isa Chalk::IR::UseInfo` for `use constant {...}` scan
  - C.pm:126 — `$method_decl isa Chalk::IR::MethodInfo` in `_emit_method` (dual-path with Constructor)
  - C.pm:236 — same MethodInfo isa-check (return-type extraction)
  - C.pm:1616, 1773, 2032 — `$class_decl isa Chalk::IR::ClassInfo` (dual-path)
  - C.pm:1622 — `SubInfo` filter for static helper emission
  - C.pm:1643 — `MethodInfo` filter for XSUB emission
  - C.pm:2054 — `FieldInfo` filter for field-registration BOOT block

- **Dual-path Constructor fallback** is interesting: at the body /
  parent / method extraction sites, C.pm has a "Constructor"
  fallback (`$class_decl->inputs()->[2]`, etc.) that reads the legacy
  Constructor IR shape pre-MethodInfo/ClassInfo migration. That
  branch is currently reachable when the input is *not* a typed
  Info struct. Whether any production caller actually hits the
  Constructor branch is unclear — see Open Questions.

- **No construction of legacy types.** C.pm is purely a consumer.

- **`generate($mop)` (C.pm:1479)** is the MOP-shaped entry. It
  does not call `_generate_c_files` and produces only skeleton
  output. Production code (`script/build-chalk-so-generated`)
  uses `_generate_c_files` directly (line 277).

**Migration scope:**

Two-layer:

1. **`_generate_c_files($ir, $sa, $ctx)` → MOP-driven equivalent.**
   The IR arg must be replaced with a MOP::Class (or MOP plus a
   class-name selector). Then `_analyze_class`, `_emit_method`,
   `_emit_sub`, the class-body iteration (lines 1620, 1641, 2053),
   the XS BOOT block parent/field extraction (lines 2030, 2050),
   all need to walk MOP entities instead of Info structs.

2. **Schedule path (Phase 7).** The design doc commits to Target::C
   migrating to consume `Chalk::IR::Schedule` (the same shape
   Target::Perl now consumes via `_generate_from_schedule`). This
   replaces the body-arrayref iteration in `_emit_method` and
   `_emit_complex_method` with schedule-walking.

   Note that `_emit_method` (C.pm:124) has Tier A/B/empty-body
   special cases (return-only, die-only, empty) that may need to
   stay even after the schedule path lands — those are emit
   shortcuts, not graph readers.

3. **`generate($mop)` stub upgrade**. The current stub at C.pm:1479
   needs to be filled in with the actual MOP→C pipeline (currently
   `_generate_c_files` is what consumers call instead). Whether
   `generate($mop)` becomes the production entry or
   `_generate_c_files` is renamed/extended is a design choice.

**Blockers for deletion of legacy types:**

- `ClassInfo`: Target::C uses it as the type of `$class_decl`
  everywhere. Blocker.
- `FieldInfo`, `MethodInfo`, `SubInfo`, `UseInfo`: all used as
  isa-dispatch filters during body iteration. Blocker.
- `Program`: indirectly, via `_find_class_decl` inherited from
  EmitHelpers. The `_generate_c_files` entry signature accepts
  an opaque `$ir` arg, but in practice today that arg is a
  Program tree (or a ClassInfo via `_find_class_decl`). Blocker
  in the sense that callers (test harness, build scripts) pass
  Program-IR today.

### `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm`

**Role in production:** Phase 5 IR optimization pass. Detects hashes
with known key sets in method bodies and rewrites them to structs.
Polymorphic on input: accepts either a MOP or a legacy parsed-class
arrayref. Schemas are attached as a side structure
(`$mop->struct_promotion_schemas`).

**Legacy types consumed:** ClassInfo, MethodInfo, SubInfo,
FieldInfo, Program.

**Patterns:**

- **Synthesis (MOP → legacy)** — the entry-shaped anti-pattern:
  - StructPromotion.pm:60-77 — `_run_mop($mop)` translates
    `MOP::Class` → `{ class_name, ir }` shape via
    `_class_info_from_mop_class`.
  - StructPromotion.pm:94-117 — `_class_info_from_mop_class($cls)`:
    iterates `$cls->methods`, `$cls->subs`, reads `$method->body`,
    `$sub->body` from MOP (lines 101, 108), wraps in MethodInfo
    (line 97) / SubInfo (line 105), and aggregates into a fresh
    ClassInfo (line 111).
  - This synthesis exists **only** so the legacy `analyze()` method
    can walk the existing-shape body. It is exactly the anti-pattern
    the audit targets: bridge code that bridges to legacy code,
    locking the legacy code in place.

- **Construction of legacy types** in `rewrite()`:
  - StructPromotion.pm:566 — `Chalk::IR::MethodInfo->new` per
    rewritten method (preserves `graph => $item->graph()`)
  - StructPromotion.pm:600 — `Chalk::IR::SubInfo->new` per rewritten
    sub
  - StructPromotion.pm:623 — `Chalk::IR::ClassInfo->new` per
    rewritten class
  - StructPromotion.pm:634 — `Chalk::IR::Program->new` wrapping
    the new ClassInfo

  These are the canonical rebuild path: take parsed-class arrayref
  in, return rewritten-as-Program out. This shape exists because
  the legacy contract was `rewrite()` returns a rewritten
  `parsed_classes` arrayref of `{ class_name, ir => Program }`.

- **Accessor reads**:
  - StructPromotion.pm:140 — `$class_decl->body()` in `analyze`
  - StructPromotion.pm:147, 150 — `$item->body()` on MethodInfo/SubInfo
  - StructPromotion.pm:520 — `$class_decl->body()` in `rewrite`
  - StructPromotion.pm:545, 579 — `$item->body()` on MethodInfo/SubInfo

- **Type checks**:
  - StructPromotion.pm:145, 543, 869, 871, 877 — ClassInfo isa
  - StructPromotion.pm:148, 543, 620 — MethodInfo isa
  - StructPromotion.pm:148-150, 577, 621 — SubInfo isa
  - StructPromotion.pm:619 — FieldInfo isa

- **`_find_class_decl`** (StructPromotion.pm:865) — walks Program
  or accepts a direct ClassInfo. Same shape as the EmitHelpers
  helper of the same name.

**Migration scope:**

The cleanest migration shape (per design doc §7 Amendment 5) is
"StructPromotion walks MOP entities directly." That means:

1. Delete `_class_info_from_mop_class`. `analyze` takes the MOP
   directly and iterates `$mop->classes`, `$cls->methods`,
   `$sub->body` (or eventually `$method->graph` if body goes
   away in Phase 6).

2. `rewrite()` is more involved. Today it produces a new parsed-class
   arrayref with rewritten `Chalk::IR::Program` IR. If StructPromotion
   becomes MOP-shaped end-to-end, rewriting in place on the MOP is
   one option (mutates `MOP::Method.body` or `MOP::Method.graph`);
   another is to keep the schema side-table and let downstream
   targets consume schemas without ever materializing a rewritten
   IR (current `_run_mop` already attaches schemas to the MOP and
   returns the MOP unchanged — the rewrite path is the legacy one).

   The `rewrite_mop` follow-up is mentioned in the ABOUTME comment
   at StructPromotion.pm:48 but not yet implemented. That's the
   missing piece.

3. The `_rewrite_method_body` helper (line 649) currently produces
   a rewritten body arrayref; if Phase 6 deletes body, the rewrite
   target becomes the graph, which means rewriting IR nodes in
   place (matching what other optimizer passes do) or producing
   a new graph.

This migration also surfaces a question (see Open Questions) about
whether StructPromotion's rewriting semantics fit naturally onto
the MOP shape.

**Blockers for deletion of legacy types:**

- `ClassInfo`, `MethodInfo`, `SubInfo`, `FieldInfo`: all read
  and constructed. Blocker.
- `Program`: constructed and walked (`_find_class_decl`). Blocker.

## Dependency graph (informal)

Migration interactions:

- **Actions.pm is the producer.** Removing the construction sites
  in Actions requires every other consumer to no longer need the
  Info-struct shape. Actions migrates *last* on the construction
  side — but Actions's `body` field population on MOP::Method /
  MOP::Sub (Actions.pm:702, 711) is independent of Info-struct
  construction and can be removed once consumers stop reading
  `MOP::Method.body`.

- **StructPromotion's `_class_info_from_mop_class`** is a direct
  bridge from MOP to legacy and is the textbook synthesis
  anti-pattern. Migrating StructPromotion to consume MOP directly
  unblocks:
  - Deletion of `MOP::Method->body` and `MOP::Sub->body` (one of
    StructPromotion's two MOP→body readers; the other is
    Target::Perl `_generate_from_mop`).
  - Deletion of `_class_info_from_mop_class` (Op-internal).
  - StructPromotion's contribution to `ClassInfo`/`MethodInfo`/
    `SubInfo` consumer count. Does NOT unblock deletion of those
    types (Target::C and EmitHelpers still consume them).

- **EmitHelpers and Target::C are tightly coupled.** EmitHelpers
  is Target::C's base class; the two share the `_find_class_decl`
  walker, the `_build_field_index_map` analyzer, and the
  `_scan_class_methods` machinery. Migrating one without the other
  is unrewarding because the helper signatures don't change
  without the caller's input shape changing. Migrate together.

- **Target::Perl is the easiest** of the four production consumers
  because Phase 5b already migrated production codegen to the
  schedule path. `_generate_from_mop` and `_body_from_graph` have
  zero production callers — they're only kept for the golden-corpus
  diff harness. Phase 6 deletes them. The remaining
  `_generate_with_cfg` / `_emit_program` / `_emit_*_decl` machinery
  has only test-side callers (and the `Chalk::IR::Program` test
  scaffolding); deletion is gated on those tests retiring.

- **`_generate_with_cfg`'s only callers are test files.** Deleting
  it does not affect production code. It is gated on the test
  migration tracked in `2026-05-24-codegen-test-triage.md`.

Migrations that **must** happen before a deletion can land:

| To delete | Required prior migrations |
|---|---|
| `MOP::Method->body`, `MOP::Sub->body` | (a) Target::Perl `_generate_from_mop` deleted (Phase 6), (b) StructPromotion `_class_info_from_mop_class` deleted, (c) `_body_from_graph` covers all side-effect kinds (Phase 3d + 3e suggests this is already true; verify against a probe) |
| `Chalk::IR::Program` | (a) Target::Perl `_emit_program` deleted, (b) StructPromotion `_find_class_decl` migrated to MOP, (c) StructPromotion `rewrite()` migrated off Program-shaped IR, (d) EmitHelpers `_find_class_decl` migrated, (e) all test-side Program consumers retired (see triage doc) |
| `Chalk::IR::ClassInfo` | (a)-(d) above plus Target::C `_emit_method`/`_emit_sub`/XS BOOT migrated, (e) EmitHelpers `_build_field_index_map`/`_scan_class_methods` migrated, (f) Target::Perl `_emit_class_decl` deleted, (g) Actions.pm `ClassBlock` stops constructing |
| `Chalk::IR::MethodInfo`, `SubInfo` | Same as ClassInfo (they're consumed in the same iteration loops). Plus Target::Perl `_emit_method_decl`/`_emit_sub_decl` deletion. |
| `Chalk::IR::FieldInfo` | Target::C XS BOOT field registration (C.pm:2054) migrated, EmitHelpers field-index/reader scan migrated, Target::Perl `_emit_field_decl` deleted, Actions.pm `VariableDeclaration`/`AssignmentExpression` stop constructing. |
| `Chalk::IR::UseInfo` | Actions.pm `UseDeclaration` stops constructing (and pushes directly to MOP `declare_import`). Target::Perl `_emit_use_decl` deleted. Target::C `use constant` scan (C.pm:98) migrated to MOP imports. |

## Migration ordering recommendation

Recommended order, highest-leverage first:

1. **StructPromotion** — migrate to consume MOP directly (delete
   `_class_info_from_mop_class`; rewrite `analyze` and the
   `rewrite_mop` follow-up). Rationale: this is the cleanest
   synthesis-bridge anti-pattern in production. It is the smaller
   of the two MOP→legacy bridges (the other being Target::Perl's
   `_generate_from_mop`, which Phase 6 already targets for
   deletion). Unblocks `MOP::Method->body`/`MOP::Sub->body`
   deletion in combination with the Phase-6 work.

2. **Target::Perl Phase 6 cleanup** — delete `_generate_from_mop`,
   `_body_from_graph`, and the Actions-side body population for
   `MOP::Method.body` / `MOP::Sub.body`. Rationale: per the design
   doc this is already the Phase 6 plan; it removes the largest
   chunk of synthesis-bridge code. Test gate: byte-compat goldens
   pass. With (1) done first, `MOP::*->body` deletion happens in
   the same commit family.

3. **EmitHelpers + Target::C together** — migrate
   `_find_class_decl`, `_build_field_index_map`, `_scan_class_methods`
   to take a MOP::Class. Then migrate Target::C's `_emit_method`,
   `_emit_sub`, `_analyze_class`, class-body iteration loops, and
   XS BOOT field/parent extraction to consume the MOP. Rationale:
   they share a base class and analyzer routines; migrating one
   without the other is incoherent. This is Phase 7 in the design
   doc. After this, `Chalk::IR::ClassInfo`, `MethodInfo`, `SubInfo`,
   `FieldInfo`, `UseInfo` lose their last production consumers.

4. **Actions.pm construction-site removal** — once (1)-(3) are
   done and consumers no longer require Info-struct shape,
   Actions.pm's `ClassBlock`, `MethodDefinition`,
   `SubroutineDefinition`, `VariableDeclaration`, `UseDeclaration`,
   `Program` action methods can stop constructing the legacy
   types and return MOP entries / arrayrefs / undef as the new
   contract requires. Rationale: producer-side cleanup mechanically
   follows consumer-side cleanup. Without consumers, the
   constructions are dead writes.

5. **Delete the Info-struct types themselves** — remove
   `lib/Chalk/IR/Program.pm`, `ClassInfo.pm`, `MethodInfo.pm`,
   `SubInfo.pm`, `FieldInfo.pm`, `UseInfo.pm`. This is the formal
   end of the pre-MOP IR shape.

Items (1) and (2) can be done in either order (or in parallel) —
they share no code, only converge in deleting `MOP::*->body`.
Item (3) gates on (1) and (2) because Target::C currently calls
into EmitHelpers and would break if the helpers' signatures
change underneath. Item (4) gates on (3). Item (5) gates on (4).

## Open questions

1. **StructPromotion's rewrite semantics on MOP.** `rewrite()`
   today returns a new `Chalk::IR::Program` (StructPromotion.pm:634)
   per class. On the MOP, the natural equivalents are either:
   mutate `MOP::Method.graph` in place; produce a new MOP::Method
   with a new graph (immutable shape); or keep the side-table
   schema approach (`set_struct_promotion_schemas`) and let
   downstream targets consult schemas during emission.

   Which shape Phase 7 commits to changes the migration size
   substantially. The ABOUTME comment at StructPromotion.pm:48
   says "Returns the MOP (no rewriting yet - rewrite_mop is a
   follow-up once MOP carries enough body shape to be rewritten
   in place)" — so a decision is pending.

2. **Target::C's Constructor-fallback path.** At C.pm:1616, 1773,
   2032 (`$class_decl isa Chalk::IR::ClassInfo ? body() :
   inputs()->[2]`), Target::C has a fallback to read the legacy
   Constructor IR shape (pre-Info-struct). Is any production
   caller hitting this fallback today? If yes, the migration
   needs to preserve whatever that path supports. If no, this is
   dead code that should be deleted independently of the larger
   migration.

3. **`MOP::Method.body` non-codegen consumers.** Is `body` read
   anywhere outside the consumers documented here? We searched
   for `->body` in `lib/` and found only the five modules above.
   Test scaffolding likely reads it too (see triage doc) and
   debugging tools may print it. Confirm no serialization /
   diagnostic / debugger path reads it before deletion.

4. **`_body_from_graph` coverage.** Perl.pm:142 comments note
   that `_body_from_graph` "misses non-VarDecl side-effects (e.g.
   a bare `push @list, $x` statement) because Block's
   control-chain fixup only rebuilds VarDecl/Return." After
   Phase 3d/3e (memory notes that ForStatement and the control
   chain were retrofitted), is this still true? If yes,
   `MOP::Method.body` deletion is gated on closing this gap.

5. **`_emit_program` test-side caller migration.** Per the design
   doc Phase 7, `_emit_program` deletion gates on test-side
   migration. The triage doc covers ~20 test files that route
   through Program-IR. None of those are in scope for this audit
   but they are blockers in the dependency graph.

6. **Actions.pm `Program()` return type.** When Actions stops
   returning `Chalk::IR::Program`, what does it return? The
   natural answer is "the MOP" (which is what production codegen
   reads), but `Program()` is shaped as an action-method return,
   and the existing caller chain through `_run_parse` may expect
   a node-like return. This is a small shape question but
   resolves the producer-side migration.

7. **`Chalk::IR::ClassInfo` as parent of `Chalk::IR::Program`'s
   classes list.** Both types have `id()` methods used for
   hash-cons keying. Are they currently used as inputs inside
   any hash-consed Constructor node? The comment in
   `ClassInfo.pm:17` says "ClassInfo objects may appear as
   inputs inside hash-consed nodes" — if true today, that's
   another consumer category not covered above. The ABOUTME
   for each Info-struct says "may appear as inputs inside
   hash-consed Constructor nodes (e.g., ClassDecl body)" — but
   the Constructor-shape consumer chain is mostly retired. A
   probe to grep for actual uses of `ClassInfo`/`MethodInfo`
   ids in NodeFactory hash-cons keys would resolve this.

## Out of scope (NOT this audit)

- Test-side consumers (covered by `2026-05-24-codegen-test-triage.md`).
- `script/chalk-mop-audit` and `script/scan-parseable-files.pl`,
  which load `Chalk::IR::Program`/`ClassInfo`/etc. — they are
  diagnostic / audit tooling, not production code. Flagged here
  for awareness: they will also need migration when the types
  are deleted, but they are not part of the production codegen
  path the brief targets.
- The MOP::Class->body proposal that was rejected
  (see `2026-05-24-class-as-builtin-rejected.md`).
- The Phase 5b snippet-wrapping work (already shipped).
- The XS test suite as a whole (deferred to Phase 7 by
  Decision Q5).
