---
title: "Producer: cond_expr/dor arms over-walk past their convergence point"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T06:23:14.008991908Z
updated: 2026-07-03T06:23:14.008991908Z
---

Found during RC2b (019f1c1e). The D4 bug class -- an arm walk with no stop at the convergence op consumes the rest of the sub -- was fixed for and/or via a stop address (the op_next). cond_expr and dor arms still walk with NO stop: a ternary or // in non-final position (`my $x = $c ? 1 : 2; ...more...`) can consume trailing statements inside the arm snapshot. No corpus case fails on it today (D1/D6/L3 use final-expression position). cond_expr convergence is NOT op_next (next reaches the false arm) -- derive the join op from the arm tails instead.
