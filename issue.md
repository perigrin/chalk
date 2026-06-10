---
title: "Branch-review suggestions: emitter consolidation + harness strictness"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-10T19:50:59.71678573Z
updated: 2026-06-10T19:50:59.71678573Z
---

Verified Suggestions from the whole-branch review 2026-06-10 (paad/code-reviews/...-256a9b37-branch-agentic.md), all latent:
- Symbol-prefix logic triplicated (@str_const/@rxs_lit/@env_key) and already micro-diverged: str_const uses bytes-length, env/rxs use char length (wrong global sizes if non-ASCII ever reaches them); class names with :: are not legal unquoted LLVM identifiers. One _module_global_name helper owning prefix + byte-length (+ a \w+ die per the G6 S4 finding).
- Slot-payload store helper: the repr dispatch (Int/Bool zext/ref ptrtoint/Str StrPair-boxing) now exists in 3-5 variants (:param binding, FieldAccess-lvalue, element stores, defaults-GAP). One shared helper; then Str/ref field DEFAULTS can be lowered instead of GAP-dying.
- ClassInfo::id()/MethodInfo::id() omit the R3-added fields (adjusts/parent_ci/body_node/return_repr) — id-keyed %visited dedup could silently drop a second same-id ClassInfo adjusts. Fold the fields in.
- EnvRead emits a per-node @env_empty_N global (wasteful, symbol-unique); share one empty-string global.
- Harness strictness: unquoted const_type builds a garbage integer Constant silently (croak on , or : in a bare value); MethodInfo/ClassInfo recognizers silently DROP positional %ref inputs and ignore a params: attr (croak instead); duplicate field_index in _populate_registry_from_classinfo silently drops the second field (croak).
