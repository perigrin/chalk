---
title: "Producer: postfix-while discarded walks pollute the serialized graph with orphan nodes"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T21:41:04.423063502Z
updated: 2026-07-03T21:41:04.423063502Z
---

RC2b review (state lens). The main walk condition pass and the arm walk build real nodes before back-edge detection; Graph::nodes consumer-edge BFS collects them, so every postfix-while ships dead nodes (verified: NumLt/Add orphans) into the trusted-IR contract surface Chalk repr-propagation walks. Fix direction: detect the back-edge with an insulated probe BEFORE real construction (the _scout_mutated_targs pattern), or admit only nodes input-reachable from start/returns.
