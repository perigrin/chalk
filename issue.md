---
title: "MOP migration 4/4: Phase 6 deletions as amended by the R3 reconciliation"
state: pending
urgency: normal
milestone: codegen-harness
blocked_by:
- 019eb421-13e9-7411-b8e9-cab95da31177
created: 2026-06-11T00:42:07.233155643Z
updated: 2026-06-11T00:42:28.807147353Z
---

Item 4 of the re-audit punch list (blocked by 3/4): the original Phase 6 (delete compat_class field + 17 test files; Actions::Program() returns the MOP instead of Chalk::IR::Program; delete the metadata structs) now CONFLICTS with the R3 reconciliation, which made immutable ClassInfo/MethodInfo (body_node/return_repr) the LLVM backend class-structure read surface. Resolve in the target/IR architecture review FIRST (likely outcome: keep the structs as the immutable read surface, amend the deletion list), then execute the amended deletions. Do NOT delete structs before that decision.
