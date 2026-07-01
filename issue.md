---
title: "RC2: control-flow + logical lower but crash at runtime (Phase 4, 8 cases)"
state: done
urgency: normal
milestone: codegen-harness
created: 2026-07-01T03:57:11.648124386Z
updated: 2026-07-01T05:19:52.347494098Z
sessions:
- start_sha: b725af3d23422f1fe1384f67082be32ff7420c98
  end_sha: 6c36af9793edede7e6812eb94f0cb5d830811228
  commits: 1
  started_at: 2026-07-01T04:49:42.41147947Z
  ended_at: 2026-07-01T05:19:52.347494098Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-01T04:49:42.41147947Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-07-01T05:19:52.347494098Z
observed_paths:
- lib/Chalk/IR/Serialize/JSON.pm
- t/bootstrap/ir/son-region-head.t
---

Phase 4 corpus-wide root cause RC2. See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

SCOPE NARROWED after investigation: the original "8 cases, one control-flow lowering bug" framing was wrong. There are TWO distinct mechanisms, not one:

DONE (this issue) -- logical short-circuit shape (perl5-son a374d42, branch phase4b-single-exit):
- L1 `$a && $b` and L2 `$a || $b` now lower to And/Or operand-returning nodes
  (corpus logical.md contract) instead of a malformed If/Region/Phi that dropped
  the left operand (Phi(7,7)). End-to-end: L1 -> lli Int:7 == perl; L2 -> Int:3.
- Statement-modifier guards (`return X if C` / `... unless C`) keep control-flow
  with correct continuation-Proj polarity (and->false proj, or->true proj).
- corpus-wide green 32 -> 34. perl5-son suite 290/290.
- Side effect: postfix-if/while (D4/D5) now surface a clean downstream repr GAP
  (And LHS repr=Bool needs Coerce(Bool->Int)), not a malformed graph.

REMAINING -- moved to RC2b (loops + not), a different mechanism:
- control-flow D2/D3 (while / foreach): "Phi node encountered in lower_value
  before its enclosing if/loop structure was processed" -- a Loop Region/Phi
  ordering / control-chain problem in the B::SoN producer, NOT the and/or shape.
- logical L4 (not): lli exited 1 -- needs a Bool representation path.
- D4/D5 postfix depend on the Bool->Int coercion GAP above.

Cross-repo: perl5-son commits cannot ride this chain; the fix is committed
there and cross-referenced by stage name.
