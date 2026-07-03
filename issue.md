---
title: "Producer: nested ternary ($a ? ($b ? 1 : 2) : 3) not recursed"
state: in-progress
urgency: normal
milestone: codegen-harness
created: 2026-07-01T04:45:58.786486223Z
updated: 2026-07-03T22:20:26.973358268Z
sessions:
- start_sha: 1afa515d8f3c900227c2a4a5f21ed0d1ffbf0c58
  end_sha: ""
  commits: 0
  started_at: 2026-07-03T22:20:26.973358268Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-03T22:20:26.973358268Z
---

Pre-existing limitation surfaced in the RC4 review (not a regression). SoN::FromOptree cond_expr uses a flat arm-walk that does not recurse into a nested cond_expr, so $a ? ($b ? 1 : 2) : 3 produces only ONE TernaryExpr with a wrong inner arm. The RC4 fix (arm order + leavesub-stop) does not worsen it (the false arm is now correct). Producer fix: the arm walk must build a nested TernaryExpr when an arm is itself a cond_expr. Cross-ref RC4 (019f1bd3), RC5 (branch typing).

CLOSED by RC5 (2026-07-03): _walk_branch dispatches nested cond_expr recursively (perl5-son 6b59303); pinned by t/from-optree-nested-if.t subtest 4 (rvalue nested ternary) and corpus D7/D9 GREEN.
