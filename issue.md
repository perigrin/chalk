---
title: "RC4: semantic miscompile -- inverted ternary/if + s/// + object-state (Phase 4, CORRECTNESS) + 4c object-state mutation across method calls"
state: in-progress
urgency: normal
milestone: codegen-harness
blocks:
- 019f1bd3-1b94-7c40-9189-0cdea873d7ed
- 019f1be7-47ac-7d06-823d-b1f959028a78
created: 2026-07-01T03:57:27.768613539Z
updated: 2026-07-01T04:46:45.763142493Z
sessions:
- start_sha: b725af3d23422f1fe1384f67082be32ff7420c98
  end_sha: ""
  commits: 0
  started_at: 2026-07-01T04:23:41.990022058Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-01T04:23:41.990022058Z
---

Phase 4 corpus-wide root cause RC4 (semantic miscompiles). See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

DONE (Chalk-side producer perl5-son 94eee4b): the INVERTED ternary/if -- the priority correctness bug. $n > 0 ? 1 : 2 returned 2 (else arm). Two fixes in cond_expr/_walk_branch: (a) arm order (op->other=true, op->next=false; TernaryExpr inputs[1]=true); (b) arm value no longer consumed by walking through the implicit leavesub (stop_at_exit for cond_expr arms; explicit return still stepped for mark balance -- review-caught). Corpus-wide 26->32 GREEN: fixed ternary D6 + if/else D1 + regex 0->4 (match-as-conditional uses the same ternary path). Review gate PASSED (blocker: // return mark leak -- fixed + guarded).

REMAINING in RC4 (still open):
- regex R3 s///: Str:foobar not Str:bazbar -- the substitution is not applied to the result. Separate producer/lowering fix.
- object-state mutation (merged 019f1007): method-call Int:0 not Int:11 -- object instance state not persisted across $c->inc; $c->val. Separate object-lifetime fix.

The dangerous inverted-branch class is CLOSED. s/// and object-state are the residual RC4 miscompiles.
