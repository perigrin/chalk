---
title: "4b-4: field/element write wiring in FromOptree"
state: pending
urgency: normal
milestone: v0.1
blocked_by:
- 019ecd59-bbb9-7f8e-8958-8a218a8f6546
created: 2026-06-15T22:14:45.778229695Z
updated: 2026-06-15T22:14:59.356933859Z
---

Producer-side. Confirmed drop (4a §1b probe): $n += 1 lowers to FieldAccess;Add;Return with the store back ABSENT. Wire the result back as Assign-over-FieldAccess/Subscript lvalue (Chalk store shape). Unblocks references R6/R7; prerequisite for 4c class-tier mutation methods. Scope: docs/plans/2026-06-15-phase4b-scope.md
