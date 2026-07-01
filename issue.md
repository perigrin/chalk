---
title: "RC3: producer dies translating capture/qr/dor (Phase 4, 4 cases)"
state: pending
urgency: normal
milestone: codegen-harness
blocks:
- 019f1be7-47ac-7d06-823d-b1f959028a78
created: 2026-07-01T03:57:11.719268733Z
updated: 2026-07-01T04:19:42.358369468Z
---

Phase 4 corpus-wide root cause RC3 (4 cases). See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

B::SoN DIES translating these idioms, so no method graph is emitted ("no main::corpus_case method"):
- host H1/H2: $1 capture read + guarded capture (the dominant lib/ idiom).
- regex R2: qr// compiled regex.
- logical L3b: defined-or with an undef left operand.

Producer translation gaps in SoN::FromOptree: capture-var ($1) wiring to the preceding match, the qr// node, and a dor edge case. RC3 is the producer analog of RC1 -- these must at least translate before they can lower. Note G7/host work (RegexCapture $N contract, EnvRead) is the Chalk-side model these map to.
