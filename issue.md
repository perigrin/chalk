---
title: "4b-2: PadAccess targ stability (cross-graph identity)"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-15T22:14:45.640738117Z
updated: 2026-06-15T22:14:45.640738117Z
---

Producer-side. FromOptree serializes pad index targ verbatim (FromOptree.pm:380/656/787); targ is CV-local so two semantically-identical graphs diverge on it (4a Debt A, the noted method-comparison blocker). Decide: drop targ from identity-bearing serialization (keep varname) or normalize. Needed before son-compare on real bodies is meaningful. Scope: docs/plans/2026-06-15-phase4b-scope.md
