---
title: "Phase 4 gate: enforce the triple contract (shape + TypedInvariant) in the corpus runner"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-01T04:19:29.658105629Z
updated: 2026-07-01T04:19:29.658105629Z
---

Phase 4 coverage gap (chain-review 2026-07-01). The gate is the TRIPLE contract (brief lines 32-39): each corpus case must pass behavior (lli==perl) AND shape (structural-subset vs the ir block) AND invariant (TypedInvariant). The corpus-wide runner (t/bootstrap/corpus/son-corpus-wide.t) checks BEHAVIOR ONLY. So the current "26 GREEN" does not certify the full gate.

Work: extend the corpus-wide runner to also (1) structural-subset match the B::SoN graph against the case ir block (the format decided matching mode, same as the constructive builder), and (2) run TypedInvariant on the loaded graph. A case is "gate-green" only when all three pass. Re-audit the current 26 behavior-greens against the stricter bar. Until this lands, Phase 4 completion cannot be asserted against the acceptance criterion.
