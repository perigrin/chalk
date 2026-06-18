---
title: "4b-3b: B::SoN loses is_bool on constant-folded comparisons"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-18T20:15:28.200150885Z
updated: 2026-06-18T20:15:28.200150885Z
---

Localized by the 4b-3 e2e runner. A constant-folded comparison (e.g. 1<2, 2<1) yields a boolean SV, but B::SoN emits it as Constant(const_type=string, value=1 or empty, stamp=Unknown). Two losses: (1) is_bool -- the perl oracle tags Bool:1/Bool: but B::SoN sees a plain string; (2) stamp=Unknown maps to no representation, so it GAPs at the backend. Fix: B::SoN should detect SvIsBOOL on a folded constant SV and emit a Boolean-stamped Constant. Producer-side fidelity gap.
