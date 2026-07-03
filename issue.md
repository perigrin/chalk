---
title: "Producer: StackSim::snapshot collapses mark positions"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T06:23:13.97098945Z
updated: 2026-07-03T06:23:13.97098945Z
---

Found during RC2b forensics (019f1c1e). StackSim::snapshot re-pushes marks at the copy final stack depth ($copy->push_mark() for @marks), not at the original positions -- all copied marks collapse to scalar(@stack). Any arm containing a mark-consuming op (pop_to_mark) walked on a snapshot whose parent had a pending mark below leftover values gets a corrupted arg list. Did not bite D2-D5. Fix: copy the mark POSITIONS verbatim; the deep-copy comment is wrong and should be corrected too.
