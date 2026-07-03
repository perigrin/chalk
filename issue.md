---
title: "Producer: full lowering of side-effecting loop conditions"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T21:41:04.390352894Z
updated: 2026-07-03T21:41:04.390352894Z
---

RC2b review C3 (report paad/code-reviews/phase1-lateral-bindings-2026-07-03-rc2b-5df32523.md). Perl evaluates a while condition N+1 times; the two-phase translation models condition mutations as back-edge effects and post-loop reads as the header Phi, losing the failing evaluation. Postfix form additionally leaks the main walk pre-evaluation into Phi inits. Repros: `while ($i-- > 0) {} $i` oracle Int:-1 vs Int:0; `$t=$t+$n while $n-- > 0` oracle Int:3 vs Int:1. Interim guard (RC2b fix pass): die GAP when the condition segment mutates any pad slot. REAL FIX: materialize condition effects on the exit path (post-loop rebind to the at-exit recomputation), and snapshot/restore statement-boundary scope for the postfix first-walk.
