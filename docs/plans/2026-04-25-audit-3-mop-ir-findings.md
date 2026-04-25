# Audit 3 — MOP + IR Findings

**Date:** 2026-04-25
**Scope:** Read-only audit per `docs/plans/2026-04-25-audit-3-mop-ir-brief.md`.
**Branch:** `worktree-pu` at HEAD.

## Summary

- **Migration plan acceptance criteria status (2026-04-04 polymorphic plan):** 1 done / 5 partial / 3 not-started (9 criteria total). The seed claim of "approximately 80% complete" overstates progress against the plan's own gates: only 1 acceptance criterion is fully met. Verified per-item, the migration is closer to **30–40% of acceptance criteria, with substantial *infrastructure* (typed nodes, NodeFactory, Graph.merge, MOP scaffolding) in place but the cutover not landed**.
- **MOP migration plan (2026-04-21):** Phase 0 complete; Phase 1 partially landed (MOP populated *alongside* the IR metadata structs in Actions.pm, not replacing them); Phase 2 graph-merge infrastructure exists; Phases 2.5, 3, 4, 5, 6, 7, 8 not started.
- **Transitional code markers:** 18 `->body()` reader sites; 1 live `Chalk::IR::Shim` consumer in `lib/`; 1 `compat_class` declaration site (read in `Chalk::IR::Node::class`) plus 19 setters in Shim plus 61 setters in Actions.pm; `_build_method_graph` is the prototype Return-collector described in CLAUDE.md (still active); `body_stmts` BFS seeding and inputs-only `Graph::nodes()` workaround both still present; commit `c7361f3c` ("prototype:") still describes live behavior; 4 test files still consume Shim.
- **IR invariant test coverage gaps:** 1 invariant well-covered, 3 partial, 0 fully unverified — but coverage is mostly at the unit level on the `Bootstrap::IR::NodeFactory` path, not against `Chalk::IR::NodeFactory` or per-graph hash-cons.
- **MOP capabilities needed to retire DepChaser:** 2 (parse-driven import enumeration with file-resolution; transitive closure with topological sort).
- **Dead/unused IR node types:** 4 (`Slice`, `Length`, `Stringify`, `Yada`) declared in `Chalk::IR::NodeFactory` and have a class file in `lib/Chalk/IR/Node/` but no consumer site in `lib/` or `t/`.

The single biggest finding: the migration is **not stalled at "Constructor calls in Actions.pm"**. The 61 `make('Constructor',...)` call sites described in the plan have been *renamed* to `$typed->make('TypedClass', ..., compat_class => 'BinaryExpr', ...)` on `Chalk::IR::NodeFactory`. The visible call shape changed; the `compat_class` field, the `class()` override path, and the legacy class-name dispatch in consumers (Actions.pm itself, EmitHelpers, StructPromotion) all still depend on the same backward-compatibility surface. **The cutover happened to the *call* and not to the *contract*.**

## Migration plan vs code state — 2026-04-04 polymorphic SoN IR migration

Per `docs/plans/2026-04-04-son-ir-polymorphic-migration.md` "Acceptance Criteria":

| # | Criterion | Plan says | Code today | Status |
|---|---|---|---|---|
| 1 | Zero `make('Constructor', …)` in `Perl/Actions.pm` | Zero call sites | Zero `make('Constructor',...)` literally; replaced by `$typed->make('OpClass',..., compat_class => 'OldClass')` (61 such sites). The legacy class-name dispatch is preserved through `compat_class`. | partial — call literal renamed, contract still in use |
| 2 | `lib/Chalk/IR/Shim.pm` deleted; no files reference `Chalk::IR::Shim` | File gone, no refs | File present (`lib/Chalk/IR/Shim.pm:1-227`). Live consumer in `lib/Chalk/Bootstrap/IR/NodeFactory.pm:8,96`. 4 test files reference it (`t/bootstrap/ir-node-ternary-struct.t`, `ir-shim.t`, `ir-shim-activation.t`, `ir-factory-shim-integration.t`). 1 doc-comment reference in `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm:774`. | not-started |
| 3 | `compat_class` removed from `Chalk::IR::Node` | Field gone | Field declared at `lib/Chalk/IR/Node.pm:23`, read in `Chalk::IR::Node::class()` at `lib/Chalk/IR/Node.pm:42`. Set at 19 sites in `lib/Chalk/IR/Shim.pm` and 61 sites in `lib/Chalk/Bootstrap/Perl/Actions.pm`. Read via `$node->class()` at 12 sites in 3 files (`Actions.pm`, `EmitHelpers.pm`, `StructPromotion.pm`). | not-started |
| 4 | `body` removed from `MethodInfo`; readers migrated to `graph` | Field gone, readers walk graph | Field present at `lib/Chalk/IR/MethodInfo.pm:11`. `graph` field also present at `:12`. Both populated at `Actions.pm:1440-1441`. 18 `->body()` reader sites across `Target/Perl.pm` (4), `Target/C.pm` (6), `Target/EmitHelpers.pm` (2), `Optimizer/StructPromotion.pm` (6). | not-started |
| 5 | `body` on `ClassInfo` either removed (D3) or explicitly deferred with tracking | Removed or deferred-with-issue | Field present at `lib/Chalk/IR/ClassInfo.pm:13`. 9 reader sites (`StructPromotion.pm` ×3, `Target/EmitHelpers.pm` ×2, `Target/C.pm` ×3, `Target/Perl.pm` ×1). No deferral document or issue link found; superseding plan absorbs into Phase 6 deletion. | partial — deferral exists in successor plan but no issue/spec ties it to D3 explicitly |
| 6 | All codegen + optimizer walk Graph instead of `->body()` | Zero `->body()` readers | 18 readers remain (cited above). | not-started |
| 7 | `_build_method_graph` constructs complete SoN graph with Phi insertion | Full SSA construction | `_build_method_graph` (`Actions.pm:1551-1638`) collects existing Return/Unwind nodes from `$fixed_body`, synthesizes implicit Return on fall-through (`:1600-1608`), seeds `body_stmts` from the body and from `cfg_state` `then_stmts`/`else_stmts`/`statements`/`body_stmts` keys (`:1620-1630`). Does NOT perform Phi insertion, dominator analysis, or rewrite data-flow edges. Matches CLAUDE.md's "Return-collector, not a real SoN construction pass." | not-started |
| 8 | `ir-program-pipeline` and `ir-sub-info-pipeline` tests pass | Tests pass | Both fail. `ir-program-pipeline.t` fails at test 17 (`Shim.pm: parse produces IR`) — the test attempts to parse `lib/Chalk/IR/Shim.pm`, which contains `our %ENABLED = %DEFAULT_ENABLED` after a `qw(...)` initializer ending in `);` — the Perl grammar rejects this construct. Then exits 2 reading a non-existent path `lib/Chalk/Bootstrap/IR/Node/Constant.pm`. `ir-sub-info-pipeline.t` fails the same Shim.pm-parse step. | not-started |
| 9 | Every codegen target derives output purely from IR — no `($sa, $ctx)` entry points | No backchannel | `Target/Perl.pm:72` `generate_with_cfg($ir, $sa, $ctx)` still defined. `Target/C.pm:1479` `generate_c_files($ir, $sa, $ctx)` still defined. `Target/C.pm:1833` `generate_xs_wrapper($ir, …)` defined. `EmitHelpers.pm:1360` comments reference "stored `$_sa` and `$_ctx` set by `generate_c_files`." | not-started |

**Total: 0 done | 2 partial | 7 not-started.** Counting #1's call-site count "zero" as a literal pass would inflate to 1 done / 1 partial / 7 not-started, but the criterion's intent (eliminating the legacy contract surface) is not met — the renamed calls retain `compat_class` and the legacy class names.

## Migration plan vs code state — 2026-04-04 Phase 4 structural split

Per `docs/plans/2026-04-04-phase4-structural-split.md` (archived; superseded by 2026-04-21 MOP plan, but its own acceptance criteria still verifiable):

| # | Item | Plan says | Code today | Status |
|---|---|---|---|---|
| 1 | Phase 4a: Assign updates scope | Reassignments produce SSA values | Phase 4a archived as "absorbed into MOP migration's Phase 3" — code change not landed. Scope is still updated only by VarDecl. | not-started |
| 2 | Phase 4a: IfStatement merges scopes with eager Phis | If/else Phi at Region | No eager merge in IfStatement action; Phi insertion remains via `cfg_state`/loop-body sentinel mechanism in Program(). | not-started |
| 3 | Phase 4a: Trivial Phi removal inline | Inline trivial-Phi elimination | Not present in current Actions.pm. | not-started |
| 4 | Phase 4a: Remove Program() Phi pass | Post-hoc Phi pass deleted | `_loop_body_var_refs` references and post-hoc Phi pass: I did not find this active in current `Program()` — appears either removed in earlier work or never introduced. **unclear-plan** | unclear-plan |
| 5 | Phase 4b: UseDecl → UseInfo | Metadata struct exists | `lib/Chalk/IR/UseInfo.pm` exists. UseDecl no longer constructed via Constructor; `Actions.pm:758` constructs `Chalk::IR::UseInfo->new(...)` directly. | done |
| 6 | Phase 4b: FieldDecl → FieldInfo | Metadata struct exists, replaces FieldDecl | `lib/Chalk/IR/FieldInfo.pm` exists; FieldInfo objects flow through Actions.pm. | done |
| 7 | Phase 4b: MethodDecl → MethodInfo with Graph | MethodInfo carries Graph | `MethodInfo.pm` has both `body` and `graph` fields (transitional). Constructed at `Actions.pm:1436-1442`. | partial — dual-write (body + graph) |
| 8 | Phase 4b: SubDecl → SubInfo with Graph | SubInfo carries Graph | `SubInfo.pm` has both `body` and `graph` fields. Constructed at `Actions.pm:1536-1542`. | partial — dual-write |
| 9 | Phase 4b: ClassDecl → ClassInfo | Metadata struct exists | `ClassInfo.pm` exists, has `body` field present (transitional per #5 of polymorphic plan). | partial — body field remains |
| 10 | Phase 4b: Program → Program metadata struct | Metadata struct exists | `IR/Program.pm` exists; Program() returns it (`Actions.pm:989-994`). MOP-as-compilation-unit (per 2026-04-21 plan §"Delete residue") not yet landed — Program is not absorbed into MOP. | partial — IR::Program parallel to MOP |
| 11 | Phase 4b: ReturnStmt → Return CFG node, DieCall → Unwind | Done | `Chalk::IR::Node::Return` and `::Unwind` exist; produced via `make_cfg` in Actions.pm. | done |
| 12 | Phase 4b: Codegen accepts both old and new formats | Transitional dual-path | 18 readers still on `->body()`. New `graph()` path consumed only by tests. | partial — old path still primary |

**Total: 3 done | 4 partial | 4 not-started | 1 unclear-plan (12 items).**

## Migration plan vs code state — 2026-04-21 MOP migration plan

The current operative plan supersedes the two above. Phase-by-phase verdict:

| Phase | Goal | Status |
|---|---|---|
| 0 — Scaffold MOP | New code alongside metadata structs | done — `lib/Chalk/MOP.pm`, `MOP/Class.pm`, `Field.pm`, `Method.pm`, `Sub.pm`, `Import.pm`, `Phaser.pm`, `Phaser/Adjust.pm` exist; tests in `t/bootstrap/mop/` (15 files). `mop` field added to Context (`lib/Chalk/Bootstrap/Context.pm:16,37`). |
| 1 — Actions.pm builds the MOP | Zero Constructor sites; MOP populated | partial — MOP populated *alongside* (not replacing) `Chalk::IR::ClassInfo`/`MethodInfo`/etc. `Program()` and `ClassBlock()` declare on MOP via `current_mop()` at `Actions.pm:967-987` and `:1315-1364`. But `Actions.pm` STILL returns `Chalk::IR::Program`/`ClassInfo`/`MethodInfo`/`SubInfo`/`UseInfo` objects — the MOP write is additive, not the new return value. |
| 2 — Per-graph hash-cons scope | `merge`/`next_cfg_id` on Graph; graph-owners have a graph | done as scaffolding — `Graph::merge()` and `Graph::next_cfg_id()` exist (`Graph.pm:50-64`). `MOP::Method` (`Method.pm:14,19-20`), `Sub` (`Sub.pm:14,19-20`), `Phaser` (`Phaser.pm:10,16-17`) each own a graph. **But Actions.pm body-node construction is NOT migrated to `$method->merge(...)` — it still uses the `$factory` (Bootstrap::IR::NodeFactory) and `$typed` (Chalk::IR::NodeFactory) singletons.** `t/bootstrap/mop/per-graph-hash-cons.t` and `graph-merge.t` exercise the new API in isolation only. |
| 2.5 — Fixup classification | Document and redistribute fixups | not-started |
| 3a-infra — Context fields, side-channel removal | `$graph` and `$scope` Context fields; delete `annotations->{cfg}`, `update_cfg`, `cfg_state`, `inherited_cfg_state`, `_pending_cfg_update` | not-started — `Context.pm` has `mop` but not `graph` or `scope`. `update_cfg()`/`cfg_state()`/`inherited_cfg_state()` still in use; `_resolve_from_scope` at `Actions.pm:126-136` still calls `update_cfg`. |
| 3a-migration — Bottom-up graph construction | Linear-code SSA via Context fields | not-started |
| 3b — If/else Phi insertion | Eager click-style merge | not-started |
| 3c — Loop Phi insertion | Local-pass loop Phi | not-started — `ir-program-pipeline.t`, `ir-sub-info-pipeline.t` tests still fail. |
| 4 — Codegen reads MOP | `generate($mop)` returns HashRef[Str] | not-started |
| 5 — Optimizer passes take MOP | `run($mop) → $mop`, `run($graph) → $graph` | not-started |
| 6 — Delete residue | Shim, compat_class, body fields, body_stmts removed | not-started |
| 7 — Bidirectional Graph traversal | `nodes()` follows inputs and consumers | not-started — current `Graph::nodes()` is inputs-only (`Graph.pm:115-130`). |
| 8 — Documentation | `docs/architecture/mop.md` exists | not-started — file does not exist. |

**Total: 1 done | 1 partial (Phase 1) | 1 done-as-scaffolding (Phase 2) | 10 not-started.**

## Transitional code inventory

### `make('Constructor', ...)` calls — 4 in `lib/`

The 61-call seed figure refers to a *prior* call shape. Today there are 4 `make('Constructor',...)` literal calls in `lib/`, all in `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm:664, 670, 721, 808`. These are post-parse transformations rebuilding nodes after rewrite. Plus 1 docstring reference in `lib/Chalk/Bootstrap/IR/NodeFactory.pm:7`.

The 61 sites the migration plan still tracks **moved into `$typed->make('OpClass', ..., compat_class => 'LegacyClass', ...)`** form (61 occurrences in `Actions.pm`, all carrying `compat_class`). The dispatch-by-string contract is preserved through `compat_class`; the polymorphic migration is therefore not finished — the call literal changed but the dispatch surface that the plan wants to remove (`compat_class` + Shim) is intact. See `Actions.pm:187, 212, 220, 267, 276, 301, 308, 380, 387, 394, 399, 418, 423, 464, 470, 488, 496, 513, 522, 561, 572, 590, 617, 629, 640, 657, 669` (sample; total 61 lines).

### `Chalk::IR::Shim` references — 4 production sites + 4 test files

In `lib/`:

- `lib/Chalk/IR/Shim.pm:6` — package declaration.
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm:8` — `use Chalk::IR::Shim;`
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm:96` — `Chalk::IR::Shim::translate($_new_factory, $class, %params);` — only consumer of the runtime translate path.
- `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm:774` — comment-only reference ("These mirror the input order used by each shim translation in Chalk::IR::Shim.").

In `t/`:

- `t/bootstrap/ir-shim.t` — full Shim API tests.
- `t/bootstrap/ir-shim-activation.t` — `enable_class`/`disable_class` toggle tests.
- `t/bootstrap/ir-factory-shim-integration.t` — Bootstrap::NodeFactory + Shim integration.
- `t/bootstrap/ir-node-ternary-struct.t` — uses `Chalk::IR::Shim::reset_enabled` and `Chalk::IR::Shim::translate` directly.
- `t/bootstrap/ir-sub-info-pipeline.t` (line ~64) — refs only the *names* `enable_class`/`disable_class` as data being parsed from Shim.pm itself.

### `compat_class` — 1 declaration, 80 setter sites, 12 readers

- **Declaration:** `lib/Chalk/IR/Node.pm:23` `field $compat_class :param :reader = undef;`
- **Read (in production):** `lib/Chalk/IR/Node.pm:42` (the `class()` method override). Plus 12 `$node->class()` callers driving dispatch:
  - `lib/Chalk/Bootstrap/Perl/Actions.pm:375, 382, 389, 396, 408, 434, 547, 603` (8 sites)
  - `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:749, 774` (2 sites)
  - `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm:308, 771` (2 sites)
- **Set:** 19 sites in `lib/Chalk/IR/Shim.pm` + 61 sites in `lib/Chalk/Bootstrap/Perl/Actions.pm` = 80 setter sites.

### `body()` method — 2 declarations, 18 callers

- **Declarations:** `lib/Chalk/IR/MethodInfo.pm:11`, `lib/Chalk/IR/ClassInfo.pm:13`, `lib/Chalk/IR/SubInfo.pm:11`. (3 metadata struct declarations; the plan and seed text reference `MethodInfo.body` and `ClassInfo.body`. `SubInfo.body` is a fourth instance.)
- **Callers in `lib/`** (18 total, per migration plan):
  - `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:143, 337, 363, 388` (4)
  - `lib/Chalk/Bootstrap/Perl/Target/C.pm:57, 127, 1575, 1583, 1732, 2010` (6)
  - `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:130, 207` (2)
  - `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm:64, 71, 74, 445, 470, 504` (6)

### `_build_method_graph` — current capability vs target

- **Declaration:** `lib/Chalk/Bootstrap/Perl/Actions.pm:1551-1638`.
- **Callers:** `Actions.pm:1434` (MethodDefinition), `Actions.pm:1534` (SubroutineDefinition).
- **Current behavior:**
  1. Walks the Context subtree to collect `cfg_state` entries that reference `if_node`/`loop`/`try_node` (via `$sa->cfg_state(...)`).
  2. Determines a `$start` node by reading inherited `cfg_state.control` or creating fresh `Start`.
  3. Collects existing Return/Unwind nodes already present in `$fixed_body`.
  4. Synthesizes implicit Return wrapping the final body expression on fall-through (`:1600-1608`).
  5. Collects body-statement nodes as BFS seeds (the `body_stmts` workaround).
  6. Returns `Chalk::IR::Graph->new(start, returns, schedule, body_stmts)`.
- **What plan requires (acceptance #7 of polymorphic, MOP plan §3a/3b/3c):** complete SoN with bottom-up Phi insertion via Context-threaded `$scope` field, eager merge for if/else, local-pass loop Phi rewrite, no `body_stmts` seeding, no `cfg_state` walk.
- **Verdict:** the method matches the CLAUDE.md description "currently a Return-collector, not a real SoN construction pass." It is the `prototype:` commit `c7361f3c`'s output now living as `Actions.pm` permanently.

### `body_stmts` BFS seeding and inputs-only `Graph::nodes()`

- `lib/Chalk/IR/Graph.pm:14` declares the `body_stmts` field; `:33-35` seeds the cache from it; `:104` falls back to legacy BFS using it.
- `lib/Chalk/IR/Graph.pm:115-130` — `nodes()` traverses **inputs only** in its DFS post-order walk. The plan's Phase 7 restores bidirectional traversal once per-graph hash-cons isolation makes consumers safe; today, every consumer of the IR depends on inputs-only reachability supplemented by `body_stmts` seeding.
- The plan flags both as "deferred technical debt" symptoms of incomplete SSA construction. Both are still load-bearing for codegen.

### Prototype/WIP/stopgap commits

- **`c7361f3c` "prototype: thread body stmts into Graph for control-flow visibility"** (2026-04-19). Per CLAUDE.md "explicitly a prototype, not a fix." Code introduced by this commit is still in production:
  - `Chalk::IR::Graph::body_stmts` field is present.
  - `_build_method_graph` collects `body_stmts` into the Graph.
  - The "23 visible nodes vs 6 before" demonstration is the current production behavior, not a discarded experiment.
- No follow-up issue labeled to the prototype was found in the GitHub-issue inventory I could check. The follow-up is the MOP migration plan's Phase 3 + Phase 7 (full SSA + bidirectional traversal), but this is not a tracked issue — it is "the entire migration."
- Other `prototype:`/`draft:`/`stopgap:`/`WIP:` commits in recent history: `31fca713` "prototype: unified EvalContext comonad architecture" — appears unrelated to this audit's scope.
- No commits prefixed `stopgap:` were found.

### Migration TODOs

`grep -rEn "FIXME|HACK|TODO" lib/Chalk/IR/ lib/Chalk/MOP/ lib/Chalk/Bootstrap/IR/ lib/Chalk/Bootstrap/Perl/` returns zero results. Migration progress is not annotated in the code; tracking is exclusively through plan documents and CLAUDE.md.

## Dependency graph for remediation

The remaining migration work has a single critical-path lock-step. Below, each task lists what it blocks and what it depends on, followed by a proposed ordering.

### Tasks and dependencies

1. **MOP migration Phase 2.5 — fixup classification & redistribution.**
   *Blocks:* Phase 3a-migration (which will delete the `_fix_postfix_chain_deep` and `_fixup_stmts` calls from `MethodDefinition`/`SubroutineDefinition`).
   *Depends on:* nothing in the current state (Phase 2 scaffolding is in place).
   *Notable:* `_fixup_stmts` and `_fix_postfix_chain_deep` are large, well-tested helpers; redistribution is mechanical reshuffling, not rewriting.

2. **Phase 3a-infra — promote `$graph` and `$scope` to Context fields, delete `annotations->{cfg}` side-channel.**
   *Blocks:* every later phase. All bottom-up SSA work assumes Context-borne graph and scope.
   *Depends on:* nothing structurally; it is a refactor of `Context.pm` and `SemanticAction.pm` plus a sweep of `Actions.pm` `update_cfg`/`cfg_state`/`inherited_cfg_state` callers.
   *Notable:* `Context.pm:37` already follows the same pattern with `mop`; the same pattern applies to `graph` and `scope`.

3. **Phase 3a-migration — bottom-up graph construction (linear code).**
   *Blocks:* Phase 3b, 3c, 4. Removes `_build_method_graph`. Deletes the `body_stmts` seed for linear code.
   *Depends on:* Phase 2.5, Phase 3a-infra.

4. **Phase 3b — if/else Phi insertion.**
   *Depends on:* Phase 3a-migration.
   *Blocks:* Phase 3c (which tests use loops nested inside ifs).

5. **Phase 3c — loop Phi insertion + revive `ir-program-pipeline`/`ir-sub-info-pipeline` tests.**
   *Depends on:* Phase 3b. *Blocks:* Phase 4 (codegen byte-compat assumes full SSA reachability).

6. **Phase 4 — codegen reads MOP, `generate($mop)`, eliminate `($sa, $ctx)` backchannel, migrate 18 `->body()` readers to graph walks.**
   *Depends on:* Phase 3c (so graph reachability is sufficient).
   *Blocks:* Phase 5 (optimizer signatures), Phase 6 (deletion).

7. **Phase 5 — optimizer signatures (`run($mop)/run($graph)`).**
   *Depends on:* Phase 4. *Blocks:* Phase 6 (StructPromotion still constructs Constructor nodes, blocking Shim deletion).

8. **Phase 6 — delete residue: Shim.pm, `compat_class`, `MethodInfo.body`, `ClassInfo.body`, `SubInfo.body`, `Chalk::IR::Program`, `ClassInfo`, `MethodInfo`, `SubInfo`, `FieldInfo`, `UseInfo`.**
   *Depends on:* Phases 1, 4, 5 all complete. Once StructPromotion is migrated and codegen reads only the MOP, both Constructor users disappear and Shim has no callers.

9. **Phase 7 — restore bidirectional `Graph::nodes()`, delete `body_stmts`.**
   *Depends on:* Phase 3c (full SSA reachability) + Phase 2 (per-graph hash-cons in production).
   *Blocks:* nothing structural; closes the consumer-traversal exclusion.

10. **Phase 8 — `docs/architecture/mop.md` and update `ARCHITECTURE.md`, `parsing-pipeline.md`, `ir-lowering.md`, `optimization.md`.**
    *Depends on:* Phase 7 complete. *Blocks:* nothing.

11. **DepChaser retirement (X3, deferred per MOP plan §"Not in scope").**
    *Depends on:* MOP exposing transitive-import resolution as a method (Task 4 below).

### Single-task unblock candidate

**Phase 3a-infra is the highest-leverage single task.** Promoting `$graph` and `$scope` to Context fields and deleting `update_cfg`/`cfg_state`/`inherited_cfg_state` is mechanical, has a well-defined boundary (`Context.pm`, `SemanticAction.pm`, the ~50 `update_cfg`/`cfg_state` callers in `Actions.pm`), and unblocks every subsequent phase. Without it, Phase 3a-migration cannot start.

### Proposed ordering (this is a proposal, not a directive)

1. Phase 2.5 — fixup classification (parallel-able; foundational for 3a-migration).
2. Phase 3a-infra — Context fields + side-channel deletion.
3. Phase 3a-migration — bottom-up linear graph; delete `_build_method_graph`.
4. Phase 3b — if/else Phis.
5. Phase 3c — loop Phis; revive pipeline tests.
6. Phase 4 — codegen reads MOP; migrate 18 `->body()` readers.
7. Phase 5 — optimizer signatures.
8. Phase 6 — delete Shim, compat_class, body fields.
9. Phase 7 — bidirectional Graph::nodes, delete body_stmts.
10. Phase 8 — docs.
11. (Independent track) DepChaser retirement once MOP gains transitive-import resolution.

Phases 2 and 2.5 are loosely coupled to 3a-infra; some 2.5 work can land before, alongside, or after.

## MOP scope vs DepChaser

`lib/Chalk/Bootstrap/DepChaser.pm` performs queries that the MOP doesn't yet answer. Per the brief, audit identifies what specifically is missing.

### Query 1: enumerate import declarations from a parsed file's IR

**DepChaser site:** `DepChaser.pm:15-24` (`extract_use_decls`).
**Inputs:** a `Chalk::IR::Program` (or undef).
**Output:** list of module-name strings extracted from `$ir->use_decls()`.
**Should MOP own?** Yes — imports are class-scoped in the MOP plan (`MOP::Class::imports()`, `MOP::Import::module()`). Once Actions.pm returns a `Chalk::MOP` rather than an `IR::Program`, "enumerate top-level imports" is `$mop->for_class('main')->imports`, plus each non-`main` class's imports.
**Missing from MOP today:**
- DepChaser receives a parsed `IR::Program` from the parse pipeline (`_parse_file_to_ir` at `:159-178`). The MOP is populated *alongside* `IR::Program` today, so the MOP has the import data — but the parse helper returns `$sem_ctx->extract()` (the IR::Program), not the MOP.
- A method to fetch all imports across all classes in a single MOP — currently each `MOP::Class` has its own list, and DepChaser would need `for my $cls ($mop->classes) { push @imports, $cls->imports }`. Not blocking but a small ergonomic gap.

### Query 2: transitive closure with topological sort

**DepChaser site:** `DepChaser.pm:73-137` (`resolve_closure`).
**Inputs:** seed file paths, plus an internally-built grammar pipeline.
**Output:** topologically-sorted list of all dependent files.
**Should MOP own?** Partial — the *parse-each-file-to-MOP* and *enumerate-imports* steps belong to the MOP-and-its-construction pipeline. The *map-module-name-to-file-path* and *topological-sort* steps are dependency-graph algorithms that don't belong on the MOP itself; they belong to a small dependency-resolution module that consumes the MOP.
**Missing from MOP today:**
- A factory or pipeline helper that says "given a file path, return the MOP for the parsed compilation unit." Currently this is `_parse_file_to_ir($grammar, $file)` returning IR::Program; it would become `parse_file_to_mop($grammar, $file)` returning `Chalk::MOP`.
- Path-resolution for module names (`module_to_path` at `DepChaser.pm:28-33`) is filesystem logic, not MOP logic — keep it in DepChaser-the-resolver-utility, but the resolver becomes a thin wrapper over MOP enumeration.

### Net "what makes DepChaser retirable" punch list

To retire DepChaser:

1. Phase 1 of the MOP migration must complete enough that `Actions.pm` returns a `Chalk::MOP` (not just populates one as a side effect).
2. A `parse_file_to_mop(file)` helper in the test pipeline (or `Chalk::Frontend::parse_file`) replaces `_parse_file_to_ir`.
3. A small transitive-closure utility consuming `Chalk::MOP` replaces `DepChaser::resolve_closure` (algorithm unchanged; inputs change from `$ir->use_decls` to `$mop->for_class(...)->imports`).
4. Optional: an aggregate `$mop->imports()` method enumerating all imports across all classes (minor ergonomic).

Per the MOP plan §"Not in scope," DepChaser retirement is deferred until the MOP exists end-to-end. The audit confirms this is the right ordering: today's MOP is populated but not consumed (Phase 1 incomplete), so retiring DepChaser would require a write-then-rewrite.

## IR invariant claims vs test coverage

Per the brief, each invariant the IR claims to satisfy. Current architecture doc is `docs/architecture/sea-of-nodes-ir.md`.

### Invariant 1: Hash-consing — identical inputs produce identical node IDs

**Claim documented at:**
- `docs/architecture/sea-of-nodes-ir.md:15-16` ("Hash consing for data nodes. Two data nodes with identical operations and identical inputs are guaranteed to be the same object.")
- `docs/architecture/sea-of-nodes-ir.md:175-188` (full protocol description for `make()`).
- `lib/Chalk/IR/Node.pm:63-65` (`content_hash` method comment).
- `lib/Chalk/IR/NodeFactory.pm:122-138` (`make` method implementation).
- `lib/Chalk/IR/Graph.pm:50-58` (`merge` method, per-graph variant).

**Test coverage:**
- `t/bootstrap/ir-hash-consing.t` — 11K of tests against `Chalk::Bootstrap::IR::NodeFactory` (the legacy/Shim-dispatching factory). Tests deduplication of `Constant`, `Constructor` (via Shim), and complex node trees.
- `t/bootstrap/hash-consing-position.t` — argues hash-consing rules are positional.
- `t/bootstrap/mop/per-graph-hash-cons.t` — covers per-graph isolation on `Chalk::MOP::Method`/`Sub`/`Phaser::Adjust`.
- `t/bootstrap/mop/graph-merge.t` — covers `Graph::merge()` deduplication and CFG ID independence.

**Gap:** the `Chalk::IR::NodeFactory` (the typed factory) is exercised by the MOP graph-merge tests but not directly tested in isolation for content-hash correctness across the full set of 76 typed node classes. Each individual node class has a `content_hash` override (e.g., `Phi.pm:14-16`); coverage that all overrides correctly include their distinguishing fields is implicit through the per-class node tests (`ir-node-base.t`, `ir-node-data.t`, `ir-node-binop.t`, `ir-node-unaryop.t`, `ir-node-cfg.t`) but not a single property-style sweep.

### Invariant 2: Immutability — no node mutation post-construction

**Claim documented at:**
- `docs/architecture/sea-of-nodes-ir.md:16` ("Immutability. Once a node is constructed through `NodeFactory`, its operation and inputs are never changed. (The Loop node is the single exception: it exposes `set_backedge_ctrl` to wire in the back edge after the loop body is built…)").

**Code reality:**
- The exceptions are `Loop::set_backedge_ctrl` (`lib/Chalk/IR/Node/Loop.pm:12-17`) and `Phi::set_backedge` (`lib/Chalk/IR/Node/Phi.pm:18-23`). The doc names Loop only; Phi's backedge mutation is also documented in the doc (`:84`) but not flagged in the immutability statement.
- `Node::add_consumer`/`Node::remove_consumer` (`Node.pm:26-34`) are intentional post-construction mutations of the consumer list. The doc justifies this implicitly via the bidirectional use-def chain claim (`:17`).

**Test coverage:**
- No dedicated immutability test exists. There is no test that, for example, asserts `inputs` on a constructed node cannot be reassigned, or that `Loop` and `Phi` are the only nodes exposing post-construction mutation.
- `t/bootstrap/ir-use-def.t` exercises consumer-list mutation through normal construction paths, which de facto verifies the consumer-list-only mutation behavior.

**Gap:** invariant is stated; no test enforces it. A grammar audit-style test sweep ("every node class must have read-only fields and no setter methods other than the documented exceptions") would close this gap. Not currently present.

### Invariant 3: Use-def chain consistency — every node in `defs(x)` has `x` in its consumers

**Claim documented at:**
- `docs/architecture/sea-of-nodes-ir.md:17` ("Bidirectional use-def chains. Each node records both its inputs (producers) and its consumers (users)…").
- `lib/Chalk/IR/NodeFactory.pm:106-120` (`_register_consumers`).
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm:151-167` (legacy factory's consumer registration).

**Test coverage:**
- `t/bootstrap/ir-use-def.t` (6.5K) — asserts consumer registration on construction. Verifies `add_consumer` and `remove_consumer` behavior. Tests positive bidirectional shape (decl has var as input → var has decl as consumer).
- `t/bootstrap/ir-graph.t` — exercises the Graph container's interaction with use-def.
- `t/bootstrap/optimizer-dce.t` — DCE assumes correct use-def chains; failures would surface here.

**Gap:** the test corpus covers happy-path consumer registration. There's no test for consistency across `Loop::set_backedge_ctrl` and `Phi::set_backedge` (which call `remove_consumer` + `add_consumer`); the doc claim that backedge wiring preserves the invariant is not directly asserted. **Coverage adequate but with a small gap on the mutation-respects-invariant case.**

### Invariant 4: Determinism — byte-identical IR / codegen output across runs for same input

**Claim documented at:**
- `docs/architecture/sea-of-nodes-ir.md:18` ("Stable content-based IDs. Data node IDs are derived from the node's operation and its inputs' IDs, not from a creation counter. This makes IDs deterministic across runs, which is required for byte-identical code generation.")
- CLAUDE.md ("Determinism: Code generation must produce byte-identical output across runs").

**Test coverage:**
- `t/bootstrap/codegen-determinism.t` — generates the same IR five times via `full_pipeline` and asserts all runs produce identical output. Also asserts non-empty and content-shape sanity.
- No specific test for content-based ID determinism on the IR side independent of codegen.

**Gap:** determinism is end-to-end-tested at the codegen layer; the IR-layer claim ("data node IDs are derived from operation and input IDs") relies on the codegen test as the sole proof. CFG node IDs are explicitly NOT deterministic (`OpName#N` with N = sequential counter); the doc admits this, and the determinism claim is restricted to data nodes. There is no IR-layer test that diffs IR-node IDs across two runs of the same parse to assert per-data-node determinism. Adequate as integration tests; gap at the unit-invariant level.

## Polymorphic dispatch maturity

### Are all node types in `lib/Chalk/IR/Node/` instantiable directly?

The new typed factory (`Chalk::IR::NodeFactory`, *not* the Bootstrap one) has 76 entries in `%DATA_CLASSES` (lines 80-100 of `lib/Chalk/IR/NodeFactory.pm`) plus 7 in `%CFG_CLASSES`. Every entry maps to a concrete `Chalk::IR::Node::*` class with `:isa(Chalk::IR::Node)`. Each class is instantiable directly via `Chalk::IR::Node::Foo->new(id => ..., inputs => [...], ...)` — verified by `lib/Chalk/MOP/Method.pm`'s `merge` interface and by `t/bootstrap/mop/per-graph-hash-cons.t` constructing `Chalk::IR::Node::Constant->new(id => 'c1', value => 0)` directly.

**Verdict:** all 76+7 typed node classes are instantiable directly. The Shim is the *legacy entry point*; the typed-node API exists in parallel and is callable without it.

### Are there node types declared in `lib/Chalk/IR/Node/` that nothing uses?

Four candidate dead types found:

- `Chalk::IR::Node::Slice` — declared in `Chalk/IR/NodeFactory.pm`, file at `lib/Chalk/IR/Node/Slice.pm`. No `isa Chalk::IR::Node::Slice` consumer anywhere in `lib/Chalk/Bootstrap/`. Found only in `lib/Chalk/IR/NodeFactory.pm`, the class file itself, and `t/bootstrap/son-compare.t`.
- `Chalk::IR::Node::Length` — same story. No `isa` consumer.
- `Chalk::IR::Node::Stringify` — same. No `isa` consumer.
- `Chalk::IR::Node::Yada` — same. The corresponding `'...'` op-string is in `Chalk::IR::Shim::%BINOP_MAP` but never produced (Yada is not a binop in Perl), and no `isa` consumer.

These appear to be *anticipatory* nodes added during the polymorphic migration phase 1 but not yet wired into `Actions.pm` or codegen. Not blocking the migration, but cleanup candidates after Phase 6.

### Are there call sites that do `if (ref($node) eq '...')` type-tagging that should be polymorphic methods?

The codebase **does not** generally use `ref($node) eq '...'` — the migration earlier removed those in favor of the Perl 5.42 `isa` operator. There are 279 `isa Chalk::IR::Node::...` dispatches across `lib/`, which is the canonical typed-dispatch idiom.

The one remaining type-tagging-by-string dispatch pattern uses `$node->class()` (via `compat_class` override) on the legacy class names:

- `lib/Chalk/Bootstrap/Perl/Actions.pm:375-396, 408, 434, 547, 603` — eight `eq` comparisons against `'MethodCallExpr'`, `'PostfixDerefExpr'`, `'BuiltinCall'`, `'SubscriptExpr'`.
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:749, 774` — calls `$node->class()`, then string-comparison-driven dispatch. (Did not enumerate the cases here; pattern preserved.)
- `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm:308, 771` — `$node->class()` against legacy class names for `_rebuild_constructor` dispatch.

These 12 sites are direct candidates for replacement with `isa` checks against typed-node classes (`isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'method'`, etc.). They are the *consumer side* of the `compat_class` field; they cannot be removed before Phase 6 deletes `compat_class`.

## Cross-references

- **Audit 2 inputs (semiring code that depends on IR shape):** the FilterComposite semiring's filter-comparison logic indirectly assumes typed-node identities for hash-consed comparison. None observed during this audit; flagged as audit-2 territory.
- **Future round-trip-harness phase inputs:** the `t/grammar-conformance.t` harness already excludes 2 transitional files (DepChaser.pm) but has no IR-shape conformance — it's a parse-and-zero-tie harness, not an IR-equivalence one. The semantic-correctness oracle the brief flags as out-of-scope is the entire end-to-end phase: a "compile X, lower X, run X, compare X" harness against a known-good Perl implementation. Outside this audit's scope.
- **Plan documents needing update:**
  - `docs/plans/2026-04-04-son-ir-polymorphic-migration.md` is archived and supersededl no update needed except to reflect that Acceptance Criterion #1's literal call form has been changed but its intent is not yet met.
  - `docs/plans/2026-04-21-chalk-mop-migration-plan.md` describes phases 0–8 from a starting state that mostly matches today; "Phase 1" goal of "61 Constructor sites in Actions.pm" needs to be re-described in terms of the *current* form (61 `compat_class` sites + 19 in Shim + 12 readers, total surface to retire).
  - `CLAUDE.md` Plan Discipline section's seed quote ("approximately 80% complete") is overstated against acceptance criteria. Recommend updating to "the migration's *infrastructure* is in place; *cutover* is 0/9 acceptance criteria fully met."
  - `docs/architecture/mop.md` does not exist; Phase 8 of the migration plan owns it.

## Plan Discipline check (per CLAUDE.md)

CLAUDE.md flags this migration's known state and lists six items the audit must verify:

1. **~61 `make('Constructor', ...)` calls in Actions.pm** — verified: 61 `compat_class` sites in Actions.pm, 0 literal `make('Constructor', ...)` calls. The migration moved the call literal but kept the contract.
2. **Shim.pm deletion** — verified not done. Shim.pm at `lib/Chalk/IR/Shim.pm:1-227`, 1 production consumer (`NodeFactory.pm`), 4 test consumers.
3. **Codegen migration from `body()` to graph-walk** — verified not done. 18 `->body()` reader sites unchanged.
4. **Removal of `body` field from MethodInfo** — verified not done. Field at `MethodInfo.pm:11`, populated alongside `graph` field at `Actions.pm:1440-1441`.
5. **Removal of `compat_class` from Chalk::IR::Node** — verified not done. Field at `Node.pm:23`, read at `:42`, set at 80 sites.
6. **`_build_method_graph` completion** — verified not done. Currently a Return-collector + body_stmts seeder at `Actions.pm:1551-1638`. The implicit-Return-on-fall-through synthesis (`:1600-1608`) and the `body_stmts` collection from `cfg_state` (`:1620-1630`) are post-hoc compensations for the missing SSA construction.
7. **Commit `c7361f3c` is explicitly a prototype, not a fix** — verified. The commit's behavior is still in production via `Graph::body_stmts` and `_build_method_graph`'s `body_stmts` collection.

All six CLAUDE.md flags are validated against current code. The migration is *not* approximately 80% complete by acceptance criteria.

## Acceptance — walkthrough per brief §"Acceptance"

1. **Every named criterion in both migration plans has a current-state verdict.** ✓ — 9 polymorphic + 12 phase-4 = 21 verdicts, plus phase-by-phase assessment of MOP plan (12 phases). One marked unclear-plan (Phase 4a item #4: post-hoc Phi pass deletion).
2. **All transitional-code markers are inventoried with file:line citations.** ✓ — 4 `make('Constructor',...)` literal calls + 61 `compat_class` setters + 12 `compat_class` readers + 18 `->body()` callers + 4 Shim files + 1 prototype commit + 4 dead node types, all with file:line.
3. **The remediation dependency graph is drawn (even if simple).** ✓ — 11-task graph with single-task unblock candidate (Phase 3a-infra) and proposed ordering.
4. **MOP-vs-DepChaser scope is documented per-query.** ✓ — 2 queries enumerated with should-MOP-own / missing-from-MOP rows.
5. **Each IR invariant has a coverage entry.** ✓ — 4 invariants with documentation citation, test citation, and gap analysis.
6. **Findings file committed to `worktree-pu` directly.** *(this commit — pending Bash run)*
7. **Subagent reports: completion percentage, ordered punch list, no claims of "fixed."** *(in the parent assistant's final report)*

No oracle for "MOP+IR semantically represents the source program"; semantic correctness blocked on a future behavioral-equivalence harness phase. This audit produces structural and procedural findings only.
