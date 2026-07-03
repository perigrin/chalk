---
title: "RC5: TernaryExpr Int/Bool branch-repr mismatch on nested-if (Phase 4, 2 cases)"
state: in-progress
urgency: normal
milestone: codegen-harness
blocked_by:
- 019f1bd3-1b58-725a-a996-0c0eb85910cb
blocks:
- 019f1be7-47ac-7d06-823d-b1f959028a78
created: 2026-07-01T03:57:27.827922021Z
updated: 2026-07-03T21:54:59.729220118Z
sessions:
- start_sha: 1afa515d8f3c900227c2a4a5f21ed0d1ffbf0c58
  end_sha: ""
  commits: 0
  started_at: 2026-07-03T21:54:59.729220118Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-03T21:54:59.729220118Z
---

Phase 4 corpus-wide root cause RC5 (2 cases). See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

control-flow D7/D9 nested-if: "LLVM backend: TernaryExpr branches have mismatched or unsupported types (true=Int, false=Bool)". The two branch arms get DIFFERENT reprs -- one arm folds to Bool where the other is Int -- so the backend refuses the merge. A branch-repr unification issue: nested ternary/if arms must agree on a repr (or coerce). Likely interacts with RC1 (repr seeding) and RC4 (branch handling); may partly dissolve once those land.
