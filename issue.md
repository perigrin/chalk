---
title: "Loader/serializer: Chalk to_json silently corrupts loaded control-flow graphs"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T21:41:04.458882933Z
updated: 2026-07-03T21:41:04.458882933Z
---

RC2b review (contract lens). from_json moves control into control_in and leaves loop conditions unconsumed; _all_nodes_topo traverses inputs + Phi region only, so to_json of a LOADED loop graph drops both Projs, the exit Region, and the condition (verified: 10 of 14 nodes), emitting valid-looking but unlowerable JSON with no guard. No live consumer round-trips today. Fix: either enforce the one-directional boundary (die/warn) or traverse control_in + Loop-consumer conditions with the targeted Phi-backedge cut.
