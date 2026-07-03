---
title: "Producer: bare side effects in statement-modifier arms are dropped silently"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T06:23:13.892309666Z
updated: 2026-07-03T06:23:13.892309666Z
---

Found during RC2b alignment (019f1c1e). The void-context and/or path merges PAD REBINDS via TernaryExpr, but an arm whose effect is not a binding change (e.g. `foo($x) if $cond` -- a bare call) contributes nothing to the merge: the Call node is created in the real factory (orphan) and its control/effect is dropped with no warning. Pre-existing class (the old path dangled it inside a dead And instead), preserved not worsened. Fix direction: detect a non-empty arm with zero binding diffs and either thread control (If/Region like the guarded-exit path) or die GAP honestly.
