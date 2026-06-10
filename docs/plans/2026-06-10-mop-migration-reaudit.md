# MOP / SoN Migration Re-Audit — 2026-06-10

**Status:** Read-only audit. No code modified; this document is the only write.
**Branch:** `phase1-lateral-bindings` (HEAD `fbe812c0`), worktree `/home/perigrin/dev/chalk/.claude/worktrees/pu`.
**Baseline being re-measured:** `docs/plans/2026-04-25-audit-3-mop-ir-findings.md` (the "30–40% of acceptance criteria" audit) and the figures quoted in CLAUDE.md Plan Discipline item 3.
**Oracle:** plan oracle — the 9 acceptance criteria of `docs/plans/2026-04-04-son-ir-polymorphic-migration.md` and the per-phase exit criteria of `docs/plans/2026-04-21-chalk-mop-migration-plan.md`. Test runs cited below are regression evidence only, not correctness oracles.

**Methodology note:** `ag` silently missed matches in this worktree (e.g., reported zero `body_stmts` in `lib/` while `grep -r` finds 29 lines). Every count below was verified with `grep -r`; `ag`-only results were discarded.

## Summary

The CLAUDE.md item-3 figures are obsolete on every axis. Since the April audit, the May 2026 phase campaign (3a-infra through 3e, plus the scheduler campaign that implemented MOP-plan Phases 4–7) shipped most of the cutover:

- **Shim.pm: deleted** (commit `b530c7a1`), zero references in `lib/` or `t/`.
- **compat_class setters: 0 in production** (was 61 in Actions.pm + 19 in Shim). Field still declared/read on `Chalk::IR::Node`; 1 pass-through site in StructPromotion; 17 test files still touch it.
- **`->class()` string-compare readers: 0 in `lib/`** (was 12). 8+ test files still call it.
- **`->body` reader sites in `lib/`: 15** (was 18, but composition changed completely: Target/C 6→0, EmitHelpers 2→0, Target/Perl 4 all on the legacy path, StructPromotion 6→8, Actions +3 dual-write plumbing).
- **`body` fields: still present on MethodInfo/ClassInfo/SubInfo — and the surface grew**: `MOP::Method` and `MOP::Sub` now also carry `body` arrayrefs.
- **`_build_method_graph`: deleted.** Successor residue: `_finalize_body_graph` (a smaller post-hoc Context-subtree walker).
- **`Graph::body_stmts`: deleted** (`13f350d3`); `Graph::nodes()` is now **bidirectional** with a cache-membership filter (`60c269ab`).
- **cfg side channel: deleted** (`update_cfg`/`inherited_cfg_state`/`$_pending_cfg_update`: zero in `lib/`); `cfg_state` survives as a read-only adapter, now on Context (`Context.pm:205`), consumed by legacy codegen paths and 22 test files.
- **`($sa,$ctx)` backchannel: removed from the public surface, retained privately.** `Target::C::_generate_c_files($ir,$sa,$ctx)` is still the real C entry point; `Target::Perl::_generate_with_cfg($ir,$sa,$ctx)` survives on the legacy path. The literal moved (underscore-prefixed); the contract did not — the same pattern the April audit flagged for `compat_class`.
- **Phase 3a-infra (April's "highest-leverage unblock"): shipped**, and the phases it blocked (3a-migration, 3b, 3c, 3d, 3e, 4, 5, 6, 7, 8) all landed in full or in part.

**Verdict roll-up:** polymorphic plan — 2 DONE, 5 PARTIAL, 1 NOT-DONE, 1 MOOT (criteria-weighted ≈ 56%). MOP plan — 7 of 13 phases fully exited, 6 partial, 0 not-started (phase-weighted ≈ 75%). Honest single figure: **roughly two-thirds complete, vs. April's 30–40%** — with the remaining third concentrated in Phase 6 residue deletion and the Target::C entry-point migration.

## 1. Polymorphic plan (2026-04-04) — 9 acceptance criteria, re-measured

| # | Criterion | April 2026 | Current state (evidence) | Verdict |
|---|---|---|---|---|
| 1 | Zero `make('Constructor',…)` in Actions.pm | partial (61 renamed, contract kept) | `grep -rn "make('Constructor" lib/` → **0** anywhere in `lib/` (StructPromotion's 4 also gone). Zero `compat_class` setters in Actions.pm. | **DONE** |
| 2 | Shim.pm deleted; no refs | not-started | `lib/Chalk/IR/Shim.pm` does not exist; `grep -rln "Chalk::IR::Shim" lib/ t/` → 0. Deleted in `b530c7a1` "chore: delete Chalk::IR::Shim (Phase 6 closure)"; shim tests deleted in `e91fa574`. | **DONE** |
| 3 | `compat_class` removed from `Chalk::IR::Node` | not-started | Field still declared `Node.pm:23`, read in `class()` at `Node.pm:74-75`. Production setters: **0** (was 80). One pass-through preserver: `StructPromotion.pm:877-881` (copies an existing node's compat_class when rebuilding). 17 test files reference it (`grep -rlc compat_class t/`). | **NOT DONE** (production-quiescent, field alive) |
| 4 | `body` removed from MethodInfo; readers → graph | not-started | Field present `MethodInfo.pm:11`; dual-written at `Actions.pm:924-930` (`body => $fixed_body, graph => $graph`). Production Perl emission no longer reads it (schedule-driven `_generate_from_schedule`, `Perl.pm:79-95`); legacy `_emit_program` path still does (4 sites). | **PARTIAL** |
| 5 | ClassInfo `body` removed or deferred-with-tracking | partial | Field present `ClassInfo.pm:13`. Deferral now documented in `docs/architecture/mop.md` §"Relationship to metadata structs" and the MOP plan's Phase 6; no GH issue. | **PARTIAL** (deferral documented, not issue-tracked) |
| 6 | All codegen + optimizer walk Graph instead of `->body()` | not-started | Perl target production path emits from MOP + `Chalk::IR::Scheduler::EagerPinning` schedules (Phase 5a/5b scheduler commits `cc28c4a9`, `2f35121f`; facade `_generate_from_mop`/`_body_from_graph` deleted in `8b8ee251`). Target/C body emission schedule-driven (`9e287747`). But 15 `->body` reader sites remain (see §4.3) — StructPromotion's MOP path itself reads `MOP::Method->body` (`StructPromotion.pm:108`). | **PARTIAL** |
| 7 | `_build_method_graph` constructs complete SoN with Phi insertion | not-started | `_build_method_graph` **deleted** (grep → 0). Graph construction is during-parse (`$graph->merge` in actions); if/else Phis (3b) and loop Phis (3c) shipped, verified green by `docs/plans/2026-05-22-phase-3-4-audit.md` (8 TDD files + reachability). Residue: `_finalize_body_graph` (Actions.pm, after line ~1010) still walks the Context subtree post-hoc to collect schedule annotations, synthesize implicit Return, and transitively seed the cache. Known gaps: M7 foreach-iterator TODO in `t/bootstrap/mop/ir-completeness.t` (315/316); lateral-binding propagation under active fix on this very branch. | **PARTIAL** (criterion's named method dissolved; SSA substantially real) |
| 8 | `ir-program-pipeline.t` / `ir-sub-info-pipeline.t` pass | not-started | Both test files **deleted** in `75079483` "test: Phase 5b DELETE — remove 10 legacy-only tests". The criterion's intent (end-to-end pipeline validation) is carried by `t/bootstrap/mop/*.t` instead. | **MOOT** (resolved by deletion, not by passing) |
| 9 | No codegen target exposes `($sa,$ctx)` entry points | not-started | Public surface clean: `t/bootstrap/mop/codegen-no-backchannel.t` passes today (2 ok, run 2026-06-10). Private surface not clean: `Target/C.pm:1764 method _generate_c_files($ir,$sa,$ctx)` (stores into EmitHelpers `$_sa`/`$_ctx`, `EmitHelpers.pm:81-82`, `C.pm:1765-1766`), `Target/Perl.pm:539 _generate_with_cfg($ir,$sa,$ctx)`, `Perl.pm:1571 emit_from_cfg_state($sa,$ctx)`. Scripts (`01143845` repaired the chalk.so build's call) and 2 test files call `_generate_c_files` directly. | **PARTIAL** (renamed private; contract intact) |

**Score: 2 done / 5 partial / 1 not-done / 1 moot** (April: 0 / 2 / 7). Done=1, partial=0.5 over the 8 scoreable criteria → **4.5/8 ≈ 56%**.

## 2. MOP migration plan (2026-04-21) — phase-by-phase

Phase-numbering disambiguation, because three independent "Phase N" series coexist in the history:

- **MOP-plan phases** (0–8 incl. 2.5/3a-infra/3a-migration/3b/3c, plus retrofits 3d/3e) — this section.
- **Scheduler-campaign phases** (commits labeled "Phase 4b/4c/4d/4e/5a/5b/6/6.1/7a/7b/7c/7d" in May 2026, e.g. `9e287747 feat(target-c): Phase 7d`) — these *implement* MOP-plan Phases 4–7 but use their own numbering. Note "Phase 7d" exists twice: factory unification (`73b23143`, 2026-05-21) and target-c schedule emission (`9e287747`).
- **The current branch's "phase1"** is Phase 1 of the 2026-06-01 merge-and-control / lateral-propagation plan (`6a2fc2db`) — successor work, not a MOP-plan phase.

| Phase | April verdict | Current verdict | Evidence |
|---|---|---|---|
| 0 — Scaffold MOP | done | **DONE** | unchanged |
| 1 — Actions builds the MOP | partial | **DONE** (per its own exit criteria) | Zero `make('Constructor',…)`; `$mop->classes` populated; exit criteria explicitly permitted ClassInfo/MethodInfo still being produced ("still produces ClassInfo/MethodInfo, now owned by the MOP"). The plan's *scope* item "Program() returns the MOP itself" did not land — `Actions.pm:265 Program()` still returns `Chalk::IR::Program`; that deletion belongs to Phase 6. |
| 2 — Per-graph hash-cons | done-as-scaffolding | **DONE** | `MOP::Method/Sub/Phaser` own graphs with `merge`/`next_cfg_id` delegators; `current_class` removed (grep → 0); `t/bootstrap/mop/graph-merge.t` 8 ok and `per-graph-hash-cons.t` 8 ok, run 2026-06-10. Per-method *factory* isolation remains future (per-parse factory is the architecture, `docs/architecture/mop.md` §Per-parse ownership). |
| 2.5 — Fixup redistribution | not-started | **DONE by dissolution** | `_fix_postfix_chain`, `_fix_postfix_chain_deep`, `_fixup_stmts`, `_push_deref_inward`, `_push_methodcall_inward`: zero definitions/callers in `lib/`. Residue: 7 stale comments still referencing them as "canonical" (`Perl.pm:846,1214`, `EmitHelpers.pm:320`, `SemanticAction.pm:532`, `FilterComposite.pm:541`, `C.pm:1351,1368`, `Node/Call.pm:18`). |
| 3a-infra — Context fields + side-channel deletion | not-started (April's highest-leverage unblock) | **DONE** | `Context.pm:17-21`: `mop`, `graph`, `bindings` (renamed from `scope`, C3 divorce), `factory`, `control_head`. `update_cfg`/`inherited_cfg_state`/`$_pending_cfg_update`: zero in `lib/`. Exception documented in `docs/plans/2026-05-20-mop-migration-3a-infra-status.md`: `cfg_state()` survives as a **read-only adapter**, since relocated to `Context.pm:205`, assembling the legacy hashref from `control_head`/`bindings`/annotations. Consumers: codegen legacy paths + 22 test files. |
| 3a-migration — bottom-up graph construction | not-started | **DONE with residue** | `9b38596c` (VarDecl control input), `d422310b` (Block synthesis), `d6087cdc` (Block control-chain fixup), `5cde06d5` (lexical_bindings) — all ancestors of HEAD (verified `git merge-base --is-ancestor`). `_build_method_graph` deleted. Residue: `_finalize_body_graph` post-hoc walker (schedule collection, implicit-Return synthesis, transitive seeding) — smaller than the deleted pass but still aggregation the amended plan said should not exist. |
| 3b — if/else Phi | not-started | **DONE** | Shipped silently 05-20→05-22; all 4 TDD files green per `2026-05-22-phase-3-4-audit.md`. |
| 3c — loop Phi | not-started | **PARTIAL** | Loop-Phi TDD files green (same audit). But: pipeline-test revival criterion mooted by deletion (`75079483`); M7 iterator-less foreach TODO; eager-vs-lazy loop Phi open (memory: phi_merge_strategy); sentinel path half-wired; lateral-propagation fixes in flight on this branch (`f18d9f30`, `fef70b6b`). |
| 3d/3e — retrofits (not in original plan) | n/a | **DONE** | 3d effect-chain completion (2026-05-22, `7416a5df..ec8b7f2d`); 3e ForStatement (`0d986d1b`). |
| 4 — Codegen reads the MOP | not-started | **PARTIAL** | Contract met: `generate($mop) → HashRef[Str]` on both targets (`Perl.pm:79`, `C.pm:1722`); byte-compat goldens exist (`t/bootstrap/mop/codegen-byte-compat{,-schedule}.t`, `t/fixtures/codegen-goldens/`, `script/diff-codegen-goldens`); Call nodes carry resolved `Chalk::MOP::Method` handles (`Actions.pm:836-847` post-pass; `call-node-resolved-handle.t` 7 ok, run 2026-06-10); no-backchannel test green. Exit criteria NOT met: 15 `->body` readers remain in `lib/`; `($sa,$ctx)` args persist on private target methods; **`Target::C::generate($mop)` emits stub output only** (`C.pm:1721-1726` comment: "minimal stub output") — real C emission still enters via `_generate_c_files($ir,$sa,$ctx)`, which now *requires* `$ctx->mop()` (`C.pm:1853`) and emits bodies schedule-driven (`9e287747`), but keeps the IR+backchannel signature. |
| 5 — Optimizer passes take the MOP | not-started | **PARTIAL** | `Pass.pm:24 run($input)` contract exists. `StructPromotion::run` polymorphic — MOP path (`_run_mop`, `StructPromotion.pm:53-67`) attaches schemas via `$mop->set_struct_promotion_schemas` (`MOP.pm:22`) but is **analyze-only**: "rewrite_mop is a follow-up" (`StructPromotion.pm:48-50`) — an unfiled deferral. `ce27c16a` migrated analyze to read MOP::Class directly. DCE is `run($input, $factory)` (`DCE.pm:22`) — accepts Graph but the extra `$factory` param and legacy arrayref form deviate from `run($X)→$X`. |
| 6 — Delete residue | not-started | **PARTIAL** | Done: Shim + 3 shim tests deleted; Bootstrap singleton factory deleted (`73b23143`, beyond plan). Not done: `compat_class` field (Node.pm:23); `body` fields on MethodInfo/ClassInfo/SubInfo **plus new ones on MOP::Method (`Method.pm:18`) and MOP::Sub (`Sub.pm:17`)**; `Chalk::IR::Program` + ClassInfo/MethodInfo/SubInfo/FieldInfo/UseInfo all alive and constructed at `Actions.pm:850/924/999`, consumed by StructPromotion, Target/Perl, Target/EmitHelpers, Actions. |
| 7 — Trim body_stmts, all_nodes() | not-started | **PARTIAL (core done)** | `Graph::body_stmts` deleted (`13f350d3`); `Graph::nodes()` restored to **bidirectional** with cache-membership filter (`60c269ab`) — exceeding the plan, which had deferred it. `MOP::Class::all_nodes()`: does not exist (grep → 0). The `body_stmts` *name* survives in a different layer: Context structural-annotation keys (`Context.pm:191`), Actions annotations, and scheduler data (`Chalk/Scheduler/EagerPinning/Loop.pm:22`) — not the Graph seed. |
| 8 — Documentation | not-started | **DONE with drift** | `docs/architecture/mop.md` exists (`44c0a5a7` "Phase 8 finish-up", maintained through `f003f173`, `145dede3`). Drift found: see §4.6 (the MethodInfo->graph "delegating accessor" claim is wrong in mechanism and direction). |

**Score: 7 phases fully exited (0, 1, 2, 2.5, 3a-infra, 3a-migration, 3b) + 6 partial (3c, 4, 5, 6, 7, 8) + 0 not-started.** April: 1 done / 1 partial / 1 scaffolding / 10 not-started.

## 3. CLAUDE.md item-3 figure-by-figure re-measurement

| CLAUDE.md claim (April figures) | Current measurement | Command |
|---|---|---|
| "~30–40% of acceptance criteria met" | ≈56% criteria-weighted, ≈75% phase-weighted | §1, §2 |
| "92 sites: 61 compat_class setters in Actions.pm + 19 in Shim.pm + 12 `->class()` readers" | **0 + 0 + 0.** Shim gone; Actions.pm has zero `compat_class` mentions; zero `->class()` callers in `lib/`. Remaining compat_class surface: field decl+read (Node.pm:23,74-75), 1 pass-through (StructPromotion.pm:877-881), 17 test files. | `grep -rn compat_class lib/` → 8 lines / 2 files; `grep -rn -- "->class()" lib/` → 0 |
| "Shim.pm deletion (1 production consumer + 4 test files)" | Deleted; 0 refs anywhere | `ls lib/Chalk/IR/Shim.pm` → ENOENT; `grep -rln "Chalk::IR::Shim" lib/ t/` → 0 |
| "codegen migration from body() to graph-walk (18 reader sites)" | 15 `->body` sites, redistributed: StructPromotion 8 (108,120,155,162,165,543,568,602), Target/Perl 4 legacy-path (610,814,840,867), Actions 3 dual-write (773,777,786). Target/C and EmitHelpers: **0** (were 6+2). Production Perl path is schedule-driven. | `grep -rn -- "->body\b" lib/` |
| "removal of body field from MethodInfo/ClassInfo/SubInfo" | Not removed (MethodInfo.pm:11, ClassInfo.pm:13, SubInfo.pm:11); surface **grew**: MOP::Method (Method.pm:18) and MOP::Sub (Sub.pm:17) also carry `body` | `grep -n 'field \$body' lib/Chalk/IR/*.pm lib/Chalk/MOP/*.pm` |
| "removal of compat_class from Chalk::IR::Node" | Not removed; production-quiescent (0 setters) | above |
| "`_build_method_graph` completion (Return-collector + body_stmts seeder)" | Method **deleted**; SSA built during parse with Phi insertion; residue = `_finalize_body_graph` | `grep -rn _build_method_graph lib/ t/` → 0 |
| "commit c7361f3c prototype (Graph::body_stmts seeding) still in production" | **Retired.** `Graph::body_stmts` deleted in `13f350d3`; the prototype's behavior is no longer in production | Graph.pm (no field); git log |
| "highest-leverage unblock = Phase 3a-infra" | **Shipped** (2026-05-20), and everything it blocked has since landed at least partially | §2 |

## 4. Detailed findings

### 4.1 The backchannel repeated the compat_class pattern

April's headline finding was "the cutover happened to the call and not to the contract" (Constructor literals renamed, `compat_class` contract kept). The same shape now applies to the codegen backchannel: `generate_with_cfg`/`generate_c_files` were removed *as public names* (`codegen-no-backchannel.t` asserts exactly that) but live on as `_generate_with_cfg($ir,$sa,$ctx)` (Perl.pm:539) and `_generate_c_files($ir,$sa,$ctx)` (C.pm:1764), with EmitHelpers still storing `$_sa`/`$_ctx` fields (EmitHelpers.pm:45-46, 81-82). The chalk.so build script calls the underscored form (`01143845`). The rollup criterion "no reference to the `($sa,$ctx)` backchannel anywhere in `lib/`" is not met.

### 4.2 cfg_state: side channel dead, read adapter alive

The write side (`$_pending_cfg_update`, `update_cfg`, `inherited_cfg_state`, SemanticAction multiply propagation) is fully deleted. The read side survives as `Context::cfg_state()` (Context.pm:205-249), a tree-walking adapter assembling the legacy hashref from `control_head` + `bindings` + structural annotation keys (`if_node`, `loop`, `then_stmts`, `body_stmts`, …, Context.pm:190-196). Consumers: Target/Perl legacy path (~10 sites), EmitHelpers (~6 sites), 22 test files. This is load-bearing for the legacy Program emission path and for Target::C control-flow emission.

### 4.3 The 15 remaining `->body` readers, classified

- **Actions.pm 773, 777, 786** — dual-write plumbing: ClassBlock reads `$item->body()` off MethodInfo/SubInfo to populate `declare_method(body => …)` and lexical bindings. Dies with the dual-write, not separately.
- **Target/Perl.pm 610, 814, 840, 867** — legacy `_emit_program` path only ("kept alive transitionally for Target::C-via-Phase-7", Perl.pm:75-77). Production MOP path does not touch them.
- **StructPromotion.pm 108, 120** — the *MOP* path reads `MOP::Method->body` / `MOP::Sub->body`; code comment at :86-92 explicitly defers the body→graph swap to "Phase 6 alongside this migration". 155, 162, 165, 543, 568, 602 — legacy analyze/rewrite paths over ClassInfo.

### 4.4 Phase → commit map (all verified ancestors of HEAD)

| Work | Commits |
|---|---|
| 3a-infra | status doc 2026-05-20; cfg side-channel deletion (memory: cfg_state_side_channel_deleted) |
| 3a-migration | `9b38596c`, `d422310b`, `d6087cdc`, `5cde06d5` |
| 3b/3c | silent, 05-20→05-22; green per `2026-05-22-phase-3-4-audit.md` |
| 3d / 3e | `7416a5df..ec8b7f2d` / `0d986d1b` |
| 4+5 contract | per 05-22 audit (6 TDD files green) |
| 4 real Perl emission | scheduler campaign: `cc28c4a9` (5a golden parity), `2f35121f` (5b routes `generate($mop)`), `8b8ee251` (6.1 deletes the body-reading facade) |
| 4 real C emission | `c41589a6` (7c-proper: analyze reads MOP::Class), `9e287747` (7d: schedule-driven bodies) |
| 5 optimizer | `ce27c16a` (StructPromotion reads MOP::Class) |
| 6 partial | `b530c7a1` (Shim), `e91fa574` (shim tests), `7586b543` (Constructor.pm) |
| 7 | `13f350d3` (body_stmts), `60c269ab` (bidirectional nodes()), `73b23143` (singleton factory deleted) |
| 8 | `44c0a5a7`, `f003f173`, `145dede3` |

### 4.5 Tests run in this audit (regression evidence only)

`t/bootstrap/mop/graph-merge.t` (8 ok), `per-graph-hash-cons.t` (8 ok), `codegen-no-backchannel.t` (2 ok), `call-node-resolved-handle.t` (7 ok) — all pass at HEAD, 2026-06-10. The full suite was **not** run by this audit; broader green claims above cite the 2026-05-22 audit and commit-time gates.

### 4.6 Doc-drift finding: mop.md's MethodInfo->graph bridge claim is wrong

`docs/architecture/mop.md:233-235` claims "`MethodInfo->graph()` exists as a delegating accessor that reads from the MOP-side graph; this is the bridge while the migration is in flight." Reality: `MethodInfo.pm:12` is a plain `field $graph :param :reader = undef;` — no delegation. The actual bridge is value-level sharing in the **opposite direction**: MethodDefinition builds the graph and stores it on MethodInfo (`Actions.pm:924-930`); ClassBlock then copies `$item->graph()` into `declare_method(graph => …)` (`Actions.pm:778-780`). Same Graph object on both sides, but the MOP side reads from MethodInfo, not vice versa. mop.md also still says "MethodInfo->body … is still the source codegen walks", which is no longer true for the production Perl path (schedule-driven since scheduler-Phase 5b).

### 4.7 Unlabeled deferrals and dangling references (Plan Discipline anti-pattern 7)

1. **`rewrite_mop` follow-up** — `StructPromotion.pm:48-50` defers MOP-path rewriting "once MOP carries enough body shape"; no plan doc or issue names it.
2. **"Phase 9"** — `2026-05-22-phase-8-docs-punchlist.md` and the MOP plan's current-state section both refer the codegen-reads-MOP completion to "Phase 9 / superseded plan"; the MOP plan defines no Phase 9. The remaining work (this report's §5) has no owning plan document.
3. **Stale comments** referencing deleted fixup helpers at 7 sites (§2, Phase 2.5 row).
4. **`MOP::Class::all_nodes()`** — Phase 7 scope item, never built, not re-deferred anywhere.

### 4.8 Relationship to the 2026-06 R3 / LLVM work — different axis, new tension

The R3 IR-taxonomy reconciliation (HEAD-adjacent, `b1a6dcea` era) extended `Chalk::IR::MethodInfo` with `body_node`/`return_repr` (MethodInfo.pm:17,21) and made immutable `ClassInfo` (carrying MethodInfo + `MOP::Field` + `MOP::Phaser::Adjust`) the **LLVM backend's** class-structure read surface (`Chalk::Target::LLVM`, LLVM.pm:255-262, 355; mop.md §"The LLVM backend consumes class structure via ClassInfo"). This is a different axis from this migration (Perl-target codegen reading MOP graphs): it neither advances nor regresses the criteria above. But it **adds a deliberate, current consumer to the metadata structs that Phase 6 says to delete**. Phase 6's "delete ClassInfo/MethodInfo/SubInfo/…" criterion now conflicts with R3's converged design and needs explicit reconciliation (likely: keep the structs as the immutable read surface, amend Phase 6's deletion list) before any Phase 6 completion claim. This belongs to the paused target/IR architecture review (memory: architecture_review_needed_target_layer).

## 5. Remaining work (the accurate punch list)

1. **Target::C entry-point migration** — make `generate($mop)` real (it is a stub, C.pm:1721-1726) by routing the existing schedule-driven emission through it; retire `_generate_c_files($ir,$sa,$ctx)`, EmitHelpers `$_sa`/`$_ctx`, and the chalk.so build script's backchannel call.
2. **Then** delete the Perl legacy path (`_emit_program`, `_generate_with_cfg`) and the `Context::cfg_state()` read adapter (+ migrate its 22 test-file consumers).
3. **Then** retire the `body` dual-write: drop `body` from MethodInfo/ClassInfo/SubInfo *and* MOP::Method/MOP::Sub; switch StructPromotion's MOP path to graph/schedule walks (its own comment's plan); ship `rewrite_mop`.
4. **Then** Phase 6 deletions as amended by the R3 reconciliation decision (§4.8): `compat_class` field (+ 17 test files), IR::Program (Program() returns the MOP), struct deletion or formal retention as immutable read surface.
5. Smaller items: DCE signature (`run($graph,$factory)` → contract shape), `MOP::Class::all_nodes()`, `_finalize_body_graph` dissolution (ties into the in-flight lateral-bindings/clean-control campaign, which owns control-chain construction now), stale fixup-helper comments, mop.md §"Relationship to metadata structs" corrections.

Items 1→4 are a strict dependency chain; item 1 is the new highest-leverage single unblock. Caveat: whether item 1 is worth doing *now* depends on the paused architecture review's LLVM-first-vs-C/XS-first decision — if LLVM-first wins, items 2–4 may reorder around the LLVM backend's ClassInfo consumption instead.

## 6. Proposed replacement text for CLAUDE.md Plan Discipline item 3

> 3. **Known stalled migration**: the SoN-IR/MOP migration (plans:
>    `2026-04-04-son-ir-polymorphic-migration.md`, superseded by
>    `2026-04-21-chalk-mop-migration-plan.md`) is now **roughly two-thirds
>    complete** per the 2026-06-10 re-audit
>    (`docs/plans/2026-06-10-mop-migration-reaudit.md`) — the April-2026
>    "30–40%, 92 dispatch sites, Shim pending" figures are obsolete. Shipped:
>    Shim deleted; zero `compat_class` setters and zero `->class()` readers in
>    production; cfg side channel deleted (Context carries graph/bindings/
>    control_head/mop/factory); `_build_method_graph` deleted — SSA with
>    if/else and loop Phis is built during parse; `Graph::body_stmts` gone and
>    `Graph::nodes()` is bidirectional; per-parse factory; Perl target emits
>    from MOP + scheduler at golden parity; commit c7361f3c's prototype
>    behavior is retired.
>
>    Still open (do not call this migration done): the `($sa,$ctx)` backchannel
>    survives privately — Target::C's real entry is
>    `_generate_c_files($ir,$sa,$ctx)` and its public `generate($mop)` is a
>    stub; `Context::cfg_state()` is a legacy read adapter with codegen + 22
>    test-file consumers; `body` arrayrefs are dual-written on
>    MethodInfo/ClassInfo/SubInfo *and* MOP::Method/MOP::Sub with 15 reader
>    sites left; `compat_class` field still on Node (17 test files);
>    `Actions::Program()` still returns `Chalk::IR::Program`, not the MOP;
>    StructPromotion's MOP path is analyze-only (`rewrite_mop` unfiled); DCE is
>    `run($graph,$factory)` not `run($X)→$X`.
>
>    **Highest-leverage single unblock:** migrate Target::C's entry point onto
>    the schedule-driven MOP path (the Perl target already proves it) — it is
>    the last load-bearing consumer keeping the backchannel, `cfg_state()`, the
>    legacy Perl path, and the body dual-write alive. **Caution:** Phase 6's
>    "delete the metadata structs" now conflicts with the R3 reconciliation
>    (2026-06), which made immutable ClassInfo/MethodInfo (`body_node`/
>    `return_repr`) the LLVM backend's read surface — reconcile in the paused
>    target/IR architecture review before deleting structs.

## 7. Acceptance walkthrough (per dispatching brief)

1. Governing plans read, phases and criteria enumerated — **met** (§1, §2).
2. Each criterion/remaining-work item measured with commands and file:line evidence — **met** (§1–§4; all counts grep-verified after the `ag` reliability finding).
3. Per-criterion verdict table + overall % vs April's 30–40% — **met** (§1–§3: ≈56% criteria-weighted / ≈75% phase-weighted ≈ two-thirds).
4. Proposed CLAUDE.md replacement text, CLAUDE.md itself untouched — **met** (§6).
5. R3/LLVM axis kept distinct, tension named — **met** (§4.8).

No oracle exists for "the MOP+IR semantically represents the source program"; behavioral-equivalence claims remain blocked on the codegen-harness/mdtest corpus work and are out of this audit's scope.
