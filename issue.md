---
title: "RC5: TernaryExpr Int/Bool branch-repr mismatch on nested-if (Phase 4, 2 cases)"
state: done
urgency: normal
milestone: codegen-harness
blocked_by:
- 019f1bd3-1b58-725a-a996-0c0eb85910cb
blocks:
- 019f1be7-47ac-7d06-823d-b1f959028a78
created: 2026-07-01T03:57:27.827922021Z
updated: 2026-07-03T22:34:55.345204738Z
sessions:
- start_sha: 1afa515d8f3c900227c2a4a5f21ed0d1ffbf0c58
  end_sha: 1afa515d8f3c900227c2a4a5f21ed0d1ffbf0c58
  commits: 0
  started_at: 2026-07-03T21:54:59.729220118Z
  ended_at: 2026-07-03T22:34:55.345204738Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-03T21:54:59.729220118Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-07-03T22:34:55.345204738Z
---

Phase 4 corpus-wide root cause RC5 (2 cases). See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

control-flow D7/D9 nested-if: "LLVM backend: TernaryExpr branches have mismatched or unsupported types (true=Int, false=Bool)". The two branch arms get DIFFERENT reprs -- one arm folds to Bool where the other is Int -- so the backend refuses the merge. A branch-repr unification issue: nested ternary/if arms must agree on a repr (or coerce). Likely interacts with RC1 (repr seeding) and RC4 (branch handling); may partly dissolve once those land.

### Outcome (2026-07-03, DONE)

D7 (Int:3), D9 (Int:1), and the outer-false path (Int:0) GREEN end to end;
corpus-wide 39 -> 41; control-flow topic FULLY GREEN (8/8 lowerable, 0 bugs).

The filed hypothesis (branch-repr unification) was falsified: the Bool/Int
mismatch was the SYMPTOM of the cond_expr arm walk (a) not recursing into a
nested cond_expr (the arm value degraded to the inner CONDITION, dropping the
inner assignments) and (b) having no stop at the join op (D1 was green only
by accident). Fix (perl5-son 6b59303): _find_join_addr (first common op of
the two arms op_next chains) + extracted recursive _handle_cond_expr + a
void-context if/else merge (TernaryExpr per changed pad slot, the D4-proven
strategy) + TernaryExpr stamped as the join of its ARM stamps (_make_ternary).
Also closes 019f1bff (nested rvalue ternary). A return inside an arm now dies
GAP (3d6c5ab; pre-existing silent drop found by proactive probing).

Review gate (TIER_1 by sanbao -- zero Chalk commits -- plus one adversarial
fresh-context reviewer per the RC2b lesson): 4 verified findings, 3 Critical,
all fixed in 7f13d42: arm-not-reaching-join truncation (statements after the
if/else vanished), die-in-arm exception erasure, value-context ternary
discarding arm pad rebinds (now merged in every context), list-context
ternary mistranslation (GAP). B::SoN discovery now re-emits GAP refusals on
stderr instead of silently omitting the sub.

Verified: perl5-son suite 330; corpus-wide 41; son-e2e 22/3/0; son-compare
clean. perl5-son commits 6b59303, 3d6c5ab, 7f13d42 (pushed). No Chalk-side
code change this issue.
