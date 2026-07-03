---
title: "Producer: cond_expr/dor arms over-walk past their convergence point"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T06:23:14.008991908Z
updated: 2026-07-03T22:20:06.742370845Z
---

Found during RC2b (019f1c1e). The D4 bug class -- an arm walk with no stop at the convergence op consumes the rest of the sub -- was fixed for and/or via a stop address (the op_next). cond_expr and dor arms still walk with NO stop: a ternary or // in non-final position (`my $x = $c ? 1 : 2; ...more...`) can consume trailing statements inside the arm snapshot. No corpus case fails on it today (D1/D6/L3 use final-expression position). cond_expr convergence is NOT op_next (next reaches the false arm) -- derive the join op from the arm tails instead.

UPDATE 2026-07-03 (RC5): the cond_expr half is FIXED -- arms now stop at the
join op (_find_join_addr) and nest recursively (perl5-son 6b59303), and a
return inside an arm dies GAP (3d6c5ab). REMAINING SCOPE: dor arms only.
Semantic angle beyond over-walk: `my $x = E // return "f"` treats the return
as the dor FALLBACK VALUE (binds $x and continues) instead of a function exit
-- silent wrong control flow when E is undef. The dor fix needs exited-signal
handling with real control threading (this is the ubiquitous lib/ idiom, so
prefer the real fix over a GAP die).
