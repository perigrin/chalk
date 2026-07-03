---
title: "Producer: nested and/or inside a loop body misparsed as the loop condition"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T06:23:13.932800142Z
updated: 2026-07-03T06:23:13.932800142Z
---

Found during RC2b (019f1c1e). _walk_loop_body treats the FIRST and/or op with stack_depth>0 as the loop condition (builds the header Projs). A nested value-context and/or inside the body (`my $x = $a && $b`) would fire that branch and corrupt the loop shape. No corpus case exercises it yet. Fix direction: the loop-condition and op is structurally identifiable (its other-branch is the body/back-edge; op_next leaves the loop) -- discriminate on that, or delegate nested and/or to the main handler machinery.
