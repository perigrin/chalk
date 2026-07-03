---
title: "Producer: wire the loop condition to the Loop node through the JSON seam"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T21:41:04.3520326Z
updated: 2026-07-03T21:41:04.3520326Z
---

RC2b review C4 (report paad/code-reviews/phase1-lateral-bindings-2026-07-03-rc2b-5df32523.md). The producer discards the loop-condition comparison unconsumed; the backend can only find it via the ambiguous first-icmp-consumer-of-a-phi fallback (LLVM.pm:3259 strategy 2, the documented H3 bug), and a decoy comparison in the body hijacks the condition (repro: body `my $c = $n > -1` -> one extra iteration, silent). Interim guard (RC2b fix pass): producer dies GAP when >1 icmp consumes header Phis. REAL FIX: give the condition a control edge to the Loop (corpus branch_control semantics) and carry control_in for data nodes through SoN::Serialize::JSON + the Chalk loader, so backend strategy 1 matches. Then remove the ambiguity guard.
