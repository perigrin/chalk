---
title: "4b-3b: B::SoN loses is_bool on constant-folded comparisons"
state: in-progress
urgency: normal
milestone: v0.1
created: 2026-06-18T20:15:28.200150885Z
updated: 2026-06-19T01:12:07.884217449Z
sessions:
- start_sha: 4579e823078d50b5393a5c1e49c50804bff22559
  end_sha: ""
  commits: 0
  started_at: 2026-06-19T01:12:07.884217449Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-19T01:12:07.884217449Z
---

Localized by the 4b-3 e2e runner. A constant-folded comparison (e.g. 1<2, 2<1) yields a boolean SV, but B::SoN emits it as Constant(const_type=string, value=1 or empty, stamp=Unknown). Two losses: (1) is_bool -- the perl oracle tags Bool:1/Bool: but B::SoN sees a plain string; (2) stamp=Unknown maps to no representation, so it GAPs at the backend. Fix: B::SoN should detect SvIsBOOL on a folded constant SV and emit a Boolean-stamped Constant. Producer-side fidelity gap.
