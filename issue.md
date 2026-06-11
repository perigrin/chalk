---
title: "MOP migration 4/4: Phase 6 deletions as amended by the R3 reconciliation"
state: pending
urgency: normal
milestone: codegen-harness
blocked_by:
- 019eb421-13e9-7411-b8e9-cab95da31177
- 019eb42a-844b-7575-8883-1cfec92e2ff4
created: 2026-06-11T00:42:07.233155643Z
updated: 2026-06-11T00:53:19.148830781Z
---

Item 4 of the re-audit punch list (blocked by 3/4 AND by "LLVM backend reads the MOP directly", 019eb42a). The Phase-6-vs-R3 tension was RESOLVED by the architecture review 2026-06-11 (docs/plans/2026-06-11-target-ir-architecture-review-resolution.md, perigrin): the metadata structs DELETE eventually; LLVM reads the MOP directly; R3's ClassInfo consumption is transitional.

Execute the ORIGINAL Phase 6 deletions once both blockers land:
- compat_class field off Chalk::IR::Node (+ migrate its 17 test files)
- Actions::Program() returns the MOP, not Chalk::IR::Program; delete IR::Program
- delete the metadata structs (ClassInfo/MethodInfo/SubInfo/FieldInfo/UseInfo) after their last consumers (LLVM bridge retired by 019eb42a; Perl/C targets + StructPromotion off body/structs via 1/4-3/4; the corpus builder migrated with 019eb42a)
- the body arrayrefs are already gone by 3/4
