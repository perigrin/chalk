---
title: "4b-2: PadAccess targ stability (cross-graph identity)"
state: in-progress
urgency: normal
milestone: v0.1
blocks:
- 019ecd59-f6cf-7565-b401-d09ff11dce37
- 019eaa51-bcfe-76b6-a02d-a23a65bd7498
created: 2026-06-15T22:14:45.640738117Z
updated: 2026-06-16T23:56:19.313339725Z
sessions:
- start_sha: 95c1188b2af9d386346a808df6cec46ee0a11415
  end_sha: ""
  commits: 0
  started_at: 2026-06-16T23:56:19.313339725Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-16T23:56:19.313339725Z
---

Producer-side. FromOptree serializes pad index targ verbatim (FromOptree.pm:380/656/787); targ is CV-local so two semantically-identical graphs diverge on it (4a Debt A, the noted method-comparison blocker). Decide: drop targ from identity-bearing serialization (keep varname) or normalize. Needed before son-compare on real bodies is meaningful. Scope: docs/plans/2026-06-15-phase4b-scope.md
