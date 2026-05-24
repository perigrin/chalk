# Phase 7c Blocker — MOP missing entity lists

**Date:** 2026-05-24
**Branch:** `fixup-audit-baseline`
**Status:** Phase 7c not started this session.

## Summary

Phase 7c per the audit calls for migrating `_analyze_class` (C.pm:44),
`_find_class_decl`, `_build_field_index_map`, `_scan_class_methods`,
and `_scan_field_method_calls` to consume `Chalk::MOP::Class` directly
instead of `Chalk::IR::ClassInfo`. The audit said:

> "Class-scope variable scan (C.pm:60-91) and `use constant` scan
> (C.pm:93-120) become walks of the relevant MOP entity lists."

This is not actually possible against the current MOP. The MOP has
no entity list for class-scope `my $x;` declarations or for class-scope
`use constant { K => V, ... }` declarations. Those things are
represented today only on the legacy Program IR / ClassInfo body
arrayref.

## Evidence

- `lib/Chalk/MOP/Class.pm:18-22` declares fields, methods, subs,
  imports, adjust_blocks — no class-scope-vars list, no
  use-constant list.
- `_analyze_class` at `lib/Chalk/Bootstrap/Perl/Target/C.pm:58-120`
  walks `$class_decl->body()->@*` looking for `Chalk::IR::Node::VarDecl`
  and `Chalk::IR::UseInfo` items. These are body items today.
- Across `lib/Chalk/MOP/` and `lib/Chalk/IR/`, no production code
  surfaces class-scope VarDecls or `use constant` decls as MOP
  entities. They live only in the legacy body arrayref.

## Implication

Phase 7c as written by the audit cannot land cleanly. The choices are:

1. **Expand the MOP first.** Add `Chalk::MOP::Class.class_scope_vars`
   and `Chalk::MOP::Class.use_constants` entity lists, populate them
   from the parser path, then migrate Target::C's `_analyze_class`
   over. This is "Phase 7c-prep" and should land before 7c-proper.

2. **Partial migration with two sources of truth.** Migrate
   `_build_field_index_map` and `_scan_class_methods` to consume
   `MOP::Class.fields` / `.methods` / `.subs`, but keep the
   class-scope-var + use-constant scans iterating `$class_decl->body()`
   on the ClassInfo side. This creates a dual-path that survives until
   the MOP expansion lands, and risks the same "80-90% drift" pattern
   CLAUDE.md warns against — `_analyze_class` would be sometimes-MOP
   sometimes-ClassInfo, which is worse than wholly one or the other.

3. **Fold 7c into 7d.** Phase 7d already needs schedule-driven body
   emission and a MOP-driven entry. Doing the field-map / method-scan
   migration together with the MOP entity-list expansion plus the body
   emission rewrite is one bigger commit cluster but a coherent one
   ("Target::C consumes MOP, not ClassInfo").

## Recommendation

Option 1 + 3 combined: a small "Phase 7c-prep" commit that adds the
two missing MOP entity lists and parser-side population, then 7c/7d
done together. 7c-prep should be doable in an isolated commit; the
parser side likely populates these from the same Actions.pm paths
that already produce the ClassInfo body items.

## What was completed this session

- Phase 7a: Constructor-fallback dead-code deletion (commit
  `efca2671`).
- Phase 7b: build script `generate_c_files` underscore fix (commit
  `01143845`).

This Phase 7c blocker doc captures the scope mismatch between the
audit and the current MOP shape. Pre-existing test baseline documented
at `docs/plans/2026-05-24-phase-7-baseline.md`.

## Next-session prompt amendment

For the next Phase-7 session, **read this doc before re-reading the
audit**. The Phase 7c plan in the audit needs adjustment per the
"Recommendation" above; the next session should either pursue 7c-prep
(MOP entity-list expansion) standalone, or land 7c+7d together with
a coherent MOP-driven entry path.
