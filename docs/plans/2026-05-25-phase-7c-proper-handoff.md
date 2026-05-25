# Phase 7c-proper Handoff — Target::C Consumes MOP::Class

**Date:** 2026-05-25
**Status:** Plan + kickoff prompt for a new session.
**Branch:** `fixup-audit-baseline` (currently 11 commits ahead of `pu`).
**Predecessor commits this branch:**
- `798c955e` `feat(mop): Phase 7c-prep — MOP::Class gains class-body shape` (MOP API + Actions.pm population landed).
- `3b0809ee` `docs(plans): Phase 7c-prep plan — add Step 4.2.5 golden regeneration`.

## Where we left off

Phase 7c was originally one task in the Target::C migration audit: migrate `_analyze_class`, `_find_class_decl`, `_build_field_index_map`, `_scan_class_methods`, `_scan_field_method_calls` off `Chalk::IR::ClassInfo` and onto `Chalk::MOP::Class`. We discovered mid-execution that MOP::Class lacked the entity lists those helpers needed (no `class_scope_vars`, no `use_constants`). 7c was split:

- **7c-prep** (shipped 2026-05-25, commit `798c955e`): expand MOP::Class with `$scope`, `@class_scope_vars`, `@use_constants`, `declare_class_scope_var`, `declare_use_constant`, and wire Actions.pm to populate them. **Done.**
- **7c-proper** (this handoff): migrate Target::C's analyze helpers and consumers to read MOP::Class entities instead of iterating `$class_decl->body()` arrayrefs.

## What 7c-prep made available

The MOP now carries everything the Target::C analyze layer needs, parser-populated:

- `$mop_class->fields` — `@MOP::Field` (already existed pre-7c-prep).
- `$mop_class->methods` — `@MOP::Method` (already existed).
- `$mop_class->subs` — `@MOP::Sub` (already existed).
- `$mop_class->imports` — `@MOP::Import` (already existed; `use constant` is now correctly NOT in here).
- `$mop_class->adjust_blocks` — `@MOP::Phaser::Adjust` (already existed).
- **`$mop_class->class_scope_vars` — `@Chalk::IR::Node::VarDecl` (NEW in 7c-prep).**
- **`$mop_class->use_constants` — `@{ name, value }` hashrefs (NEW in 7c-prep).**
- **`$mop_class->scope` — lexical environment (NEW in 7c-prep; not consumed by 7c-proper but available).**

## What stays alive after 7c-proper (deferred to 7d + 7g)

These survive this phase intentionally:

- `Chalk::IR::Program`, `Chalk::IR::ClassInfo`, `MethodInfo`, `SubInfo`, `FieldInfo`, `UseInfo` — still produced by Actions.pm; deleted in 7g.
- `_generate_c_files($ir, $sa, $ctx)` — still the public entry; renamed/replaced in 7d as part of schedule-driven body emission.
- `_emit_method` / `_emit_complex_method` / `_emit_sub` body-iteration on `$method_decl->body()` — 7d's "big lift". 7c-proper does NOT touch method/sub body iteration.
- `MOP::Method->body`, `MOP::Sub->body` — deleted in 7g after 7d migrates emission.
- `cfg_state`, `_build_cfg_lookup`, `_cfg_lookup` — deleted in 7g.

## Scope of 7c-proper (concrete)

Target::C currently reads class-shape data via 10 `$class_decl->body()` sites + 2 EmitHelpers sites. The class-side reads — NOT the method/sub body reads — are what 7c-proper migrates:

### Sites that move to MOP (7c-proper's job)

`lib/Chalk/Bootstrap/Perl/Target/C.pm`:

- **Line 44** `_analyze_class($ir)` — the entry point. Currently takes a Program IR, calls `_find_class_decl($ir)` to find the ClassInfo. Migrate to take a `MOP::Class` directly (or accept `$mop` and call `$mop->for_class`).
- **Line 58** `my $body = $class_decl->body();` inside `_analyze_class`. Currently walks for VarDecl (class-scope vars) and UseInfo (`use constant`). Replace with `$mop_class->class_scope_vars` and `$mop_class->use_constants` reads.
- **Line 1603** `my $body = $class_decl->body();` in the main `_generate_c_files` body-iteration loop. Currently iterates body for SubInfo and MethodInfo. Replace with `$mop_class->subs` and `$mop_class->methods`.
- **Line 1610** `my $sbody = $item->body();` — inside the SubInfo iteration. This is a method/sub *body* read; **STAYS** until 7d (it's the same body-arrayref that `_emit_sub` consumes).
- **Line 1758** `my $body = $class_decl->body();` in init_statics emission. Currently iterates for VarDecl init expressions. Replace with `$mop_class->class_scope_vars`.
- **Line 2027** `my $body = $class_decl->body();` in XS BOOT block field iteration. Currently iterates for FieldInfo. Replace with `$mop_class->fields`.

`lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`:

- **Line 119** `method _find_class_decl($ir)` — picks the ClassInfo from `$ir->classes()`. Migrate to "given a MOP, return the (typically one) compilable class" — pick the non-`main` class from `$mop->classes`.
- **Line 129** `method _build_field_index_map($class_decl)` line 130 reads `$class_decl->body()`. Replace with `$mop_class->fields` iteration. The :param tracking logic stays; only the body-iteration source changes.
- **Line 200** `method _scan_class_methods($class_decl)` line 201 reads `$class_decl->body()`. Replace with iteration over `$mop_class->methods`, `$mop_class->subs`, plus the :reader scan over `$mop_class->fields`. The mis-parented-SubInfo-as-VarDecl-init logic (audit §2c, ~lines 222-227) needs verification against the MOP shape; per the spec for 7c-prep, MOP::Method/Sub population already routes SubroutineDefinition results through `declare_sub`, so the mis-parented case may be gone — verify rather than assume.
- **Line 579** `method _scan_field_method_calls($class_decl)` — the :reader extraction. Replace with `$mop_class->fields` iteration + `$field->attributes` check.

### Sites that STAY (7d's job)

- `C.pm:126` `my $body = $method_decl->body()` in `_emit_method` — this is the method *body* read for code emission. 7d migrates this to schedule-driven walking, not 7c-proper.
- `C.pm:1610` `my $sbody = $item->body()` inside SubInfo iteration — the sub *body* read. Same as above.

Don't touch these in 7c-proper. They survive as transitional reads on `MOP::Method.body` / `MOP::Sub.body` until 7d.

### Entry-point question

Per the audit's Phase 7b, `_generate_c_files($ir, $sa, $ctx)` stays the production entry. 7c-proper has two reasonable approaches:

1. **Keep `_generate_c_files($ir, $sa, $ctx)` as the entry, derive `$mop` from `$ctx`.** Inside, call `$mop = $ctx->mop()` and pass that MOP into `_analyze_class($mop)`. Minimal entry-signature churn; matches how the parser already threads the MOP.

2. **Add a new MOP-driven entry `_generate_c_files_from_mop($mop)` alongside.** Bigger refactor; defer to 7d.

**Recommendation: approach 1.** It's smaller, matches the spec's "migrate consumers but keep entry stable until 7d", and avoids touching the production caller (`script/build-chalk-so-generated` and the various test files that call `_generate_c_files($ir, $sa, $ctx)` directly).

## Authoritative reading list for 7c-proper

In order:

1. **`docs/plans/2026-05-25-phase-7c-prep-design.md`** — the spec for what 7c-prep shipped. Section "What this commit explicitly does NOT do" lists the seams 7c-proper plugs into. The post-iteration-2 amendments are particularly relevant (no `$graph`/`$factory` on MOP::Class, `$scope` exists but is unread).

2. **`docs/plans/2026-05-24-target-c-migration-audit.md`** Section 9 Phase 7c (around lines 913-946) — the original audit text. Now partially out-of-date because 7c-prep changed the precondition; read it as historical context, not as a current spec.

3. **`docs/plans/2026-05-24-phase-7c-blocker.md`** — explains why 7c was split and what's now possible after 7c-prep.

4. **`docs/plans/2026-05-25-phase-7c-prep-plan.md`** — the implementation plan that landed 7c-prep, including the corrected test conventions (singleton-reuse pattern from `parse-toplevel-sub.t:130`, NOT the plan's original incorrect singleton-accumulation framing).

5. **Spec/plan/blocker tier 2 (read if 7c-proper expands scope):**
   - `docs/plans/2026-05-24-phase-7-handoff.md` — the original Phase 7 handoff with 7a/7b/7c/7d sub-phase breakdown.
   - `docs/plans/2026-05-24-target-c-migration-audit.md` Sections 1-8 — file:line evidence behind the audit conclusions.

6. **Blueprint for the migration pattern**:
   - `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` `_emit_mop_class`, `_emit_mop_field`, `_emit_mop_method`, `_emit_mop_sub`, `_emit_mop_import` — the MOP consumers in Target::Perl. Target::C's analyze-layer helpers should walk MOP entities the same way Target::Perl's emit helpers do, with C output instead of Perl.

## Risks and open questions for 7c-proper

1. **The mis-parented-SubInfo-as-VarDecl-init branch** (`EmitHelpers.pm:222-227`) was a workaround for a parser ambiguity where `my %_cache; sub _intern(...)` parsed as one unit with the sub as a VarDecl init. In the MOP-driven model, `SubroutineDefinition` routes through `$mop_class->declare_sub` regardless. The branch may be dead, but verify before deleting — probe with `grep "my %_cache; sub " lib/` and confirm those decls land as `$mop_class->subs` entries.

2. **`compiled_class_metadata` may still be a no-op.** Phase 7b found that `script/build-chalk-so-generated`'s second-pass type-aware-dispatch loop walks Constructor IR shapes Actions.pm doesn't produce. The loop's metadata map is empty in practice. 7c-proper inherits this question: if `_analyze_class` migrates to MOP and the second-pass loop still walks Constructor shapes, the inconsistency persists. Recommendation: fix the build script's Phase 3b loop in the same commit as the analyze migration, walking `$mop_class->fields` / `methods` instead of Constructor shapes.

3. **`_class_scope_vars` and `_use_constants` hashes on EmitHelpers** (lines 40, 49) are CURRENTLY populated by `_analyze_class` via body iteration. 7c-proper migrates the population (read from `$mop_class->class_scope_vars` / `->use_constants`) but the EmitHelpers state hashes themselves stay — they encode Target::C-specific derived state (sigil, static_name slug) that doesn't belong on the MOP. Don't try to delete them in 7c-proper.

## Test gates

The whole 7c-proper change should leave the test suite where 7c-prep left it:

- `mop/codegen-byte-compat.t` 19/19 (golden was regenerated in 7c-prep; will need ANOTHER regeneration if 7c-proper changes anything Target::Perl-visible — but it shouldn't, since 7c-proper only touches Target::C and EmitHelpers).
- `mop/class-scope-vars.t`, `mop/use-constants.t`, `mop/parse-integration.t` — all 7c-prep tests still pass.
- `c-emit-helpers-inheritance.t` 54/54, `bnf-target-c.t` 178/178 — must stay green.
- Any test that hand-builds Program IR + calls `_generate_c_files($ir, $sa, $ctx)` directly is the canary for "did 7c-proper break the legacy entry-path?" — `xs-isa-inheritance.t`, `c-target-boolean.t`, `c-xs-wrapper-gen.t` are the relevant ones. Pre-existing failures from the baseline doc must not get worse.

XS test baseline: see `docs/plans/2026-05-24-phase-7-baseline.md` for the pre-Phase-7 pass/fail counts.

## Required skills

- `superpowers:writing-perl-5.42.0` — for any Perl edits.
- `superpowers:test-driven-development` — TDD throughout.
- The CLAUDE.md mandate at the project root requires both above for all code work.

## What NOT to do in 7c-proper

- **Do NOT migrate `_emit_method` / `_emit_complex_method` / `_emit_sub`'s body iteration.** That's 7d.
- **Do NOT delete `MOP::Method.body` or `MOP::Sub.body`.** Those are 7g, after 7d migrates the emission.
- **Do NOT touch Target::Perl.** It already consumes MOP through `_generate_from_schedule`.
- **Do NOT delete `Chalk::IR::Program`, `ClassInfo`, `MethodInfo`, `SubInfo`, `FieldInfo`, `UseInfo`.** Those are 7g.
- **Do NOT push or merge `fixup-audit-baseline`.** Long-running rebase territory.

## Branch state at handoff

- `fixup-audit-baseline` at `3b0809ee`, 11 commits ahead of `pu`.
- Working tree clean.
- All tests that should be green at this point are green; pre-existing failures from `docs/plans/2026-05-24-phase-7-baseline.md` are unchanged (verified at 798c955e).

## The kickoff prompt for the next session

> I'm continuing Chalk compiler work on branch `fixup-audit-baseline` in `/home/perigrin/dev/chalk/.claude/worktrees/pu`. We're picking up **Phase 7c-proper**: migrate Target::C's analyze layer (`_analyze_class`, `_find_class_decl`, `_build_field_index_map`, `_scan_class_methods`, `_scan_field_method_calls`) off `Chalk::IR::ClassInfo` body-arrayref iteration and onto `Chalk::MOP::Class` entity reads. Method and sub *body* iteration is NOT in scope (that's 7d).
>
> Read this first, in order:
>
> 1. `docs/plans/2026-05-25-phase-7c-proper-handoff.md` — this handoff doc; full context for what 7c-prep shipped, what 7c-proper consumes, and the site-by-site migration map.
> 2. `docs/plans/2026-05-25-phase-7c-prep-design.md` — the spec for what landed in `798c955e`. Pay attention to the "What reads `$scope` in 7c-proper" section (answer: nothing in 7c-proper; `$scope` is forward infrastructure).
> 3. `docs/plans/2026-05-24-target-c-migration-audit.md` Section 9 Phase 7c (lines 913-946) — the original audit text, partially out-of-date (read as historical context).
> 4. Skim the file:line citations in the handoff doc's "Sites that move to MOP" table — you'll be touching exactly those 6 sites in C.pm + 4 sites in EmitHelpers.
> 5. Skim `lib/Chalk/Bootstrap/Perl/Target/Perl.pm`'s `_emit_mop_class` / `_emit_mop_field` / `_emit_mop_method` / `_emit_mop_sub` — Target::Perl's MOP consumers are the blueprint pattern for what Target::C's analyze-layer should do, with the obvious differences (Target::Perl emits Perl; Target::C populates internal slug/index/method-scan state for later code emission).
>
> Goal of this session: land 7c-proper as one or two commits with tests green. Use the brainstorming skill first (the audit's recommendation predates 7c-prep, so design questions like "do I migrate `_find_class_decl` to take `$mop` or `$mop_class` directly?" need fresh consideration). Then writing-plans, then subagent-driven-development for execution.
>
> Before any code change:
> - Confirm `git log --oneline -1` shows `3b0809ee` (Phase 7c-prep plan amendment) or a later docs-only commit.
> - Run `mop/codegen-byte-compat.t`, `mop/class-scope-vars.t`, `mop/use-constants.t`, `mop/parse-integration.t` — all must be green. Run `c-emit-helpers-inheritance.t` and `bnf-target-c.t` — both must be green at the counts in `docs/plans/2026-05-24-phase-7-baseline.md`.
> - Document any new pre-existing failures as a baseline-delta in case 7c-proper introduces regressions.
>
> Working method:
> - Required skills: `writing-perl-5.42.0` and `test-driven-development` (CLAUDE.md mandate).
> - Brainstorm the entry-point decision (approach 1 vs approach 2 from the handoff doc) BEFORE writing any code.
> - The 7c-prep precedent shipped as one commit covering MOP API + Actions.pm population + tests + golden. 7c-proper may want the same shape: one commit covering all 10 site migrations + tests + (possibly) a regenerated `Chalk__MOP__Class.pl.golden` if Target::Perl-visible state shifts. Or two commits split between C.pm and EmitHelpers. Decide during brainstorming.
> - **Mid-execution surfacing is encouraged.** 7c-prep's Task 1 caught the golden-regeneration gap because the implementer refused to silently fix it. Apply that discipline here too.
>
> Hard constraints:
> - Do not push or merge the branch.
> - Do not touch method/sub body iteration (`_emit_method`, `_emit_complex_method`, `_emit_sub`) — that's 7d.
> - Do not delete `MOP::Method.body`, `MOP::Sub.body`, `Chalk::IR::Program`, `ClassInfo`, `MethodInfo`, `SubInfo`, `FieldInfo`, `UseInfo` — those are 7g.
> - Do not modify Target::Perl.
> - Per Auto Mode (if active): act, but the user may interrupt with course corrections; treat those as normal input.
>
> Acceptance for this session: Target::C and EmitHelpers' analyze-layer reads `MOP::Class` entity lists instead of `$class_decl->body()` arrayrefs for the 10 sites enumerated in the handoff doc. Existing tests stay green; pre-existing failures from the baseline doc don't get worse. New TDD test coverage for any newly-introduced MOP-consuming code path.
>
> Start by reading the handoff doc.
