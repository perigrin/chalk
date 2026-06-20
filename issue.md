---
title: "4b-6: increment modeling in FromOptree"
state: in-progress
urgency: normal
milestone: v0.1
blocked_by:
- 019ecd59-bbb9-7f8e-8958-8a218a8f6546
blocks:
- 019eaa51-bcfe-76b6-a02d-a23a65bd7498
created: 2026-06-15T22:14:45.983758246Z
updated: 2026-06-20T19:08:02.391796938Z
sessions:
- start_sha: 8181964fb5a9bb2fefaf697f20ba100003301d91
  end_sha: ""
  commits: 0
  started_at: 2026-06-20T19:08:02.391796938Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-20T19:08:02.391796938Z
---

Producer-side. ++/-- map to Call (OpMap:70-77); semantics + postinc return-value unverified. Model correctly. Unblocks increment K1/K2. Scope: docs/plans/2026-06-15-phase4b-scope.md
