---
title: "Phase 4: B::SoN as trusted IR/MOP producer (directional, verified through harness)"
state: pending
urgency: normal
milestone: codegen-harness
blocked_by:
- 019eaa51-bd60-73ee-bec0-6bb0ba204e3b
- 019eb316-0c85-7a68-87fc-f0c1cd221b5a
- 019eb6ff-c505-71f7-9665-5e087be277fe
blocks:
- 019eaa51-b9eb-7bc5-bee4-ca6140dc8b81
created: 2026-06-09T02:59:04.062678084Z
updated: 2026-06-12T01:54:12.268241594Z
---

Scoping brief: docs/plans/2026-06-12-phase4-bson-brief.md (the phase-shape decision the three-axis plan deferred to post-Phase-3).

Shape: 4a re-audit the seam (node parity vs TODAY's IR, son-compare baseline, cross-load of the new vocabulary) -> 4b computation-slice green through the corpus triple contract (behavior==oracle via P corner + L corner where runtime-free + ir-block shape subset + TypedInvariant) -> 4c class tier (B::SoN emits the SEALED MOP + Call.class_name; FromOptree method-body/field-write gaps) -> 4d regex/host tier (after 019eb6ff item 1 decides RegexMatch identity).

Gate 0: 019eb6ff wired as blocker -- the verifier's backend must have no known miscompiles (RegexMatch staleness, loop-exit phi wiring, _arr_table keying) before "a divergence is a B::SoN bug" is a sound rule.

Known debts (April figures STALE, re-audit first): FromOptree PadAccess targ bug; fails on feature-class method bodies (zero overlap for class files); drops field writes; no MOP emission; node parity table outdated by G4/G6/G7/R3.

Open decisions made in 4a: conversion locus (JSON load vs in-process NodeFactory), MOP emission side (build-there vs declarative replay through declare_*/seal), multi-exit method bodies (gap-map vs early Phi normalization).
