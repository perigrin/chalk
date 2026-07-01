---
title: "RC4: semantic miscompile -- inverted ternary/if + s/// + object-state (Phase 4, CORRECTNESS) + 4c object-state mutation across method calls"
state: in-progress
urgency: normal
milestone: codegen-harness
blocks:
- 019f1bd3-1b94-7c40-9189-0cdea873d7ed
- 019f1be7-47ac-7d06-823d-b1f959028a78
created: 2026-07-01T03:57:27.768613539Z
updated: 2026-07-01T04:23:41.990022058Z
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

Phase 4 corpus-wide root cause RC4 (4 cases, CORRECTNESS -- fix regardless of count). See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

SEMANTIC MISCOMPILES -- the graph lowers and runs but produces the WRONG value (silently wrong, not a loud GAP):
- control-flow D6 ternary + D1 if/else: return Int:2 not Int:1 -- branch selection appears INVERTED (returns the else/false arm when the condition is true). This is the dangerous one: a wrong-branch miscompile in B::SoN-produced ternary/if lowering.
- classes method-call: Int:0 not Int:11 -- object instance state not persisted across $c->inc; $c->val (ALREADY FILED as 019f1007; folded here).
- regex R3 s///: Str:foobar not Str:bazbar -- the substitution is not applied to the result.

The inverted ternary/if is the priority -- a correctness bug that would corrupt any real lib/ code with conditionals. Localize whether it is B::SoN branch-ordering (Proj/Region arm order) or the backend TernaryExpr/If lowering reading arms in the wrong order.

Localized by 4c-1b e2e (classes method-call). Counter->new(n=>10); $c->inc; $c->val LOWERS (after 4c-1b field typing) but returns the default/initial value, not the post-mutation value (got Int:0, want Int:11). The field state set by the constructor + mutated by $c->inc must persist into $c->val -- i.e. the object instance state across separate method-call statements. This is an object-lifetime/state lowering concern in the B::SoN->backend path (the three driver statements share one object), distinct from field TYPING (019f0597). Blocks method-call corpus case end-to-end.
