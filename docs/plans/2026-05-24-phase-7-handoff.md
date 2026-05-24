# Phase 7 Handoff — Target::C Migration

**Date:** 2026-05-24
**Status:** Plan + prompt for picking up Phase 7 in a new session.
**Branch:** `fixup-audit-baseline` (64 commits ahead of `pu`)

## Where we left off

Phase 6 shipped two architectural deletions and Phase 7 is fully
scoped and ready to start. The session ending here produced the
audit doc that drives Phase 7 implementation.

### Phase 6 final state (what shipped)

- **`ce27c16a`** — StructPromotion migrated to consume MOP::Class
  directly. `_class_info_from_mop_class` synthesis layer deleted.
- **`8b8ee251`** — `_generate_from_mop` + `_body_from_graph` +
  `_is_explicit_exit` deleted from Target::Perl (~190 lines).
- **Three doc commits** (`b577fd5c`, `8ec03f00`, `e763347f`)
  capturing Amendment 5 + the legacy IR consumer audit + Amendment 6
  describing what actually shipped vs. what deferred.

### What stays alive (Phase 7's job)

- `Chalk::IR::Program`, all Info-struct types
- `_generate_with_cfg`, `_emit_program`, `_emit_*_decl(InfoStruct)`,
  `emit_cfg_*` helpers
- `_build_cfg_lookup`, `%_cfg_lookup`, `cfg_state()` on Context,
  `Graph->schedule`
- `MOP::Method->body`, `MOP::Sub->body` (StructPromotion's
  `_analyze_mop` still reads them)

All of the above are entangled with Target::C and come down together
once Target::C migrates.

## Authoritative reading list for Phase 7

In order:

1. **`docs/plans/2026-05-24-target-c-migration-audit.md`** —
   the audit doc this session produced. Section 9 has the 7-step
   sub-phase plan. Sections 1-8 have the file:line evidence behind
   it. **This is the primary reference for Phase 7 implementation.**

2. **`docs/plans/2026-05-24-son-scheduler-design.md`**, Section 7
   Phase 7 (around lines 1137-1159, post-Amendment 6) — the design
   doc's authoritative description of what Phase 7 must accomplish.

3. **`docs/plans/2026-05-24-legacy-ir-consumer-audit.md`**,
   sections on `Target::C` and `EmitHelpers` — file:line citations
   of the legacy-shape consumers.

4. **Blueprint for the migration pattern**:
   `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` lines covering
   `_generate_from_schedule`, `_emit_scheduled_body`,
   `_emit_schedule_item`, `_emit_mop_class`, `_emit_mop_method`,
   `_emit_mop_sub`, `_emit_mop_field`, `_emit_mop_import`.

   Target::C migration follows the same shape but for C output. The
   schedule walker is target-agnostic; only the per-item-emit logic
   differs.

## Phase 7 sub-phases (from audit Section 9)

Each sub-phase should be its own commit (or commit cluster) with
tests staying green.

### 7a — Dead-code cleanup (~50 lines, low risk)

Remove Constructor-fallback else-branches that are no longer
reachable (Actions.pm produces only Info-structs, not Constructor
IR). Per the audit:

- `lib/Chalk/Bootstrap/Perl/Target/C.pm:137-140, 239-241,
  1616-1618, 1773-1775, 2030-2039, 2068-2076`
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:154-157, 281-285`

Verify by tracing producers in Actions.pm before deleting. Should be
mechanical. Pre-migration prep.

### 7b — Resolve build script + `generate_c_files` mystery

The audit's risk #1: `script/build-chalk-so-generated` calls
`$target->generate_c_files(...)` (no underscore) at lines 140, 289 —
but no method by that public name exists. Either:

- The script is dead and dies on first call (likely; verify),
- There's hidden indirection (less likely),
- Or it's a future API stub.

Resolve before 7c touches the same name. May result in deleting
parts of the build script too.

### 7c — `_analyze_class` MOP-ification (small)

Migrate `_find_class_decl`, `_build_field_index_map`,
`_scan_class_methods` to take `Chalk::MOP::Class` directly instead
of `Chalk::IR::ClassInfo`. Small, contained, sets up 7d.

### 7d — Schedule-driven body emission (THE BIG LIFT)

Replace body-arrayref iteration in `_emit_method` /
`_emit_complex_method` / `_emit_sub` with
`Chalk::IR::Scheduler::EagerPinning`-driven schedule walking. Gate
ScheduleMeta access via typed isa-checks against `EagerPinning::*`
classes.

Five body-iteration sites per the audit: 2 in
`_emit_complex_method`/`_emit_sub`, 3 in class-body iteration.

This is the migration's core. Pattern:

- Construct scheduler, call `schedule($method)`.
- Walk Schedule items with indent-tracked C output.
- Per-item: stmt nodes go to existing per-node emit; block_open
  emits the appropriate C control structure (`if`, `while`, `for`,
  `try` analog if XS supports it); block_close emits `}`;
  else/elsif/catch emit interior markers.
- Read ScheduleMeta off control nodes for surface-syntax decisions
  (loop form, foreach iterator, etc.).
- Synthetic Return with control-node value: same special case as
  Target::Perl (commit `74e3f8fd`) — emit as structured block.

Verify: existing XS test suite continues to pass. The audit's risk
#3 (the `emit_cfg_loop` textual regex patch at EmitHelpers.pm:1284-
1325) needs verification — schedule-driven output may not match the
regex; either port the patch or confirm the underlying issue is
gone.

### 7e — TestXSHelpers + hand-built tests migration

`TestXSHelpers::parse_file_ir` returns `($ir, $sa, $ctx)` today.
Switch to returning `$mop`. The XS test suite (~10 files per the
triage report) inherits the change. Three tests construct Program
IR by hand; rewrite those to MOP construction.

### 7f — StructPromotion `_analyze_mop`: body → graph

Switch `_analyze_mop` from `$method->body` reads to walking
`$method->graph` (probably via the scheduler's chain walk or by
filtering `$graph->nodes` to side-effect ops). This finishes the
body-field deletion arc.

Small commit; independent from 7d. Could land before or after.

### 7g — Final deletion wave

Once 7a-7f are green, delete the transitional infrastructure:

- `_generate_with_cfg`, `_emit_program`, `_emit_*_decl(InfoStruct)`
- `_build_cfg_lookup`, `%_cfg_lookup`, `cfg_state()` on Context
- `emit_cfg_*` helpers in EmitHelpers (and the Target::Perl copies)
- `Graph->schedule` field
- `MOP::Method->body`, `MOP::Sub->body`
- `Chalk::IR::Program`
- `Chalk::IR::ClassInfo`, `MethodInfo`, `SubInfo`, `FieldInfo`,
  `UseInfo`

Single coordinated commit if possible, since these are tied.

## Top-3 risks (from audit, repeated for emphasis)

1. **`generate_c_files` (no underscore) mystery** at
   `script/build-chalk-so-generated:140, 289`. Possibly stale build
   artifact. Resolve in 7b before touching method names.

2. **`compiled_class_metadata` may be no-op in production.** The
   build script's class-metadata loop walks
   `Chalk::Bootstrap::IR::Node::Constructor` shapes (an obsolete
   polymorphic-IR class name); Actions.pm produces only Info-structs.
   Loop likely returns empty. The second-pass type-aware Earley
   regeneration may be dead. Same probe as risk #1.

3. **`emit_cfg_loop` regex patch** at EmitHelpers.pm:1284-1325 is a
   textual workaround for an Earley filter-gap artifact in
   while-shift loops. Phase 7d's schedule-driven emit produces
   different textual output; the patch may stop matching. Verify
   whether the underlying filter-gap persists in schedule-walked
   output; port or delete accordingly. Same pattern at
   `_repair_stale_merge` (EmitHelpers.pm:378-423).

## Pre-flight verification before starting Phase 7

In the new session, before any code change:

```bash
# Confirm branch position
git log --oneline -3
# Should show 9559717a, e763347f, 8b8ee251 or similar

# Confirm test baseline
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-byte-compat.t | tail -3
# Expect 19/19

# Confirm XS test baseline (a few representative files)
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/xs-athx-no-args.t | tail -3
# Whatever status: take a baseline so regressions are detectable
```

## Required skills

- `superpowers:writing-perl-5.42.0` — for any Perl edits
- `superpowers:test-driven-development` — TDD throughout, especially
  for 7d which is the riskiest sub-phase
- The current CLAUDE.md project file requires both above for all
  code work

## What NOT to do

- **Do not start Phase 7 by writing code.** Start by re-reading the
  audit's Section 9 implementation plan and the design doc's Phase 7
  section. The audit is the spec.
- **Do not delete anything in 7g before 7a-7f land green.** The
  final deletion wave depends on every consumer being migrated.
- **Do not modify the design doc unless something the audit didn't
  anticipate surfaces.** Five amendments is enough; if a new
  architectural question emerges, capture it in a separate doc and
  reference it.
- **Do not push or merge `fixup-audit-baseline`.** This branch is in
  long-running rebase territory; integration is a separate decision.

## Branch state at handoff

- 64 commits ahead of `pu`
- Last commit: `9559717a` (the Target::C audit)
- All tests that should be green are green (codegen-byte-compat,
  tier-a/b, struct-promotion, scheduler suite)
- Known-deferred pre-existing TODOs in Phi-family tests (parser
  bugs unrelated to migration)
- XS tests: not yet verified post-Phase-6; baseline before Phase 7
  starts.

## The prompt for the next session

Use this as the initial prompt:

> I'm continuing Chalk compiler work on branch `fixup-audit-baseline`
> in `/home/perigrin/dev/chalk/.claude/worktrees/pu`. We're picking
> up Phase 7 of the SoN scheduler migration: migrate Target::C from
> the legacy Program IR + cfg_state path to MOP + Schedule +
> ScheduleMeta.
>
> Read this first, in order:
>
> 1. `docs/plans/2026-05-24-phase-7-handoff.md` — this handoff doc;
>    full context for where we are.
> 2. `docs/plans/2026-05-24-target-c-migration-audit.md` — the spec.
>    Section 9 has the 7-step sub-phase plan; Sections 1-8 have the
>    evidence.
> 3. `docs/plans/2026-05-24-son-scheduler-design.md` Section 7
>    Phase 7 — design contract for what Phase 7 must accomplish.
> 4. Skim `lib/Chalk/Bootstrap/Perl/Target/Perl.pm`'s
>    `_generate_from_schedule` / `_emit_scheduled_body` /
>    `_emit_schedule_item` — the blueprint pattern. Target::C
>    follows the same shape with C output instead of Perl.
>
> Goal of this session: land sub-phases 7a, 7b, 7c at minimum.
> Possibly start 7d if budget allows. Each sub-phase its own commit
> with tests green.
>
> Before any code change:
> - Confirm `git log --oneline -1` shows `9559717a` (audit commit).
> - Run `codegen-byte-compat.t` and the XS test suite to get a
>   baseline. Document anything failing pre-change so post-change
>   regressions are distinguishable.
>
> Working method:
> - Required skills: `writing-perl-5.42.0` and
>   `test-driven-development` for all code work (CLAUDE.md mandate).
> - Strict TDD for 7d (the body-emission rewrite). 7a is mechanical
>   dead-code deletion — confirm-by-grep is enough.
> - For 7b's `generate_c_files` mystery: probe before touching.
>   Either the build script is broken (likely) or there's hidden
>   indirection. Resolve the question, don't paper over it.
> - Commit each sub-phase separately. The deletion-wave in 7g should
>   be one coordinated commit (its components are tied) but 7a-7f
>   are independent.
>
> Hard constraints:
> - Do not push or merge the branch.
> - Do not start with 7d (the big lift) — work the small sub-phases
>   first to build confidence and reduce 7d's surface.
> - Do not delete anything from the "stays alive for Phase 7" list
>   until 7a-7f are green; 7g is the final coordinated deletion.
> - Per Auto Mode (if active): act, but the user may interrupt with
>   course corrections; treat those as normal input.
>
> Acceptance for this session: at least 7a + 7b complete, ideally
> 7c too. Each sub-phase landed as its own commit. XS test baseline
> documented. If 7d gets started, it doesn't have to finish.
>
> Start by reading the handoff doc, then the audit's Section 9.
