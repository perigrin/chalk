---
title: "F10: split the LLVM.pm Context package (4 responsibilities, duplicated control processors)"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-10T19:50:59.689209706Z
updated: 2026-06-10T19:50:59.689209706Z
---

The reconciliation plan (~74) deferred this with the promise that the issue number/ref is recorded in G.0s note — no ref existed (whole-branch review 2026-06-10). The 2831-line (now larger) Chalk::Target::LLVM Context package bundles value lowering, control processing, emission buffers, and the side-table state machine; _process_if_node/_wire_region_phis are duplicated between Context and ElaboratedContext (copy-paste-with-divergence). Split AFTER the cache/identity family (019eb316) — that work will reshape the state machine anyway.
