---
title: "4b-4: field/element write wiring in FromOptree"
state: in-progress
urgency: normal
milestone: v0.1
blocked_by:
- 019ecd59-bbb9-7f8e-8958-8a218a8f6546
blocks:
- 019eaa51-bcfe-76b6-a02d-a23a65bd7498
created: 2026-06-15T22:14:45.778229695Z
updated: 2026-06-19T12:20:42.233540143Z
sessions:
- start_sha: 35bff2233675665b493e682c98afd81d2f4955e6
  end_sha: ""
  commits: 0
  started_at: 2026-06-19T12:20:42.233540143Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-19T12:20:42.233540143Z
---

Producer-side. Confirmed drop (4a §1b probe): $n += 1 lowers to FieldAccess;Add;Return with the store back ABSENT. Wire the result back as Assign-over-FieldAccess/Subscript lvalue (Chalk store shape). Unblocks references R6/R7; prerequisite for 4c class-tier mutation methods. Scope: docs/plans/2026-06-15-phase4b-scope.md
