---
title: "Producer: nested ternary ($a ? ($b ? 1 : 2) : 3) not recursed"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-01T04:45:58.786486223Z
updated: 2026-07-01T04:45:58.786486223Z
---

Pre-existing limitation surfaced in the RC4 review (not a regression). SoN::FromOptree cond_expr uses a flat arm-walk that does not recurse into a nested cond_expr, so $a ? ($b ? 1 : 2) : 3 produces only ONE TernaryExpr with a wrong inner arm. The RC4 fix (arm order + leavesub-stop) does not worsen it (the false arm is now correct). Producer fix: the arm walk must build a nested TernaryExpr when an arm is itself a cond_expr. Cross-ref RC4 (019f1bd3), RC5 (branch typing).
