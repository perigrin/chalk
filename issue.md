---
title: "RC2b: loop lowering (D2/D3) + not/Bool-repr (L4, D4/D5) (Phase 4)"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-01T05:19:46.301125195Z
updated: 2026-07-01T05:19:46.301125195Z
---

Phase 4 corpus-wide, split from RC2 (019f1bd2-dc60). See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

RC2 fixed the logical short-circuit shape (And/Or). This is the OTHER mechanism bundled under the old RC2 framing: loop control-flow lowering + the Bool representation for `not`. Distinct root cause, distinct fix.

Cases:
- control-flow D2 (while), D3 (foreach): "Phi node encountered in lower_value
  before its enclosing if/loop structure was processed" at Target/LLVM.pm ~2994.
  The B::SoN producer builds the Loop Region/Phi so the Phi is read before its
  enclosing Loop/Region appears in the control chain. Likely a Loop-header Phi
  ordering / control-chain-emission problem analogous to the single-exit and
  and/or work, but for loop back-edges. Investigate one while .ll to localize:
  is the Loop node's Region.head unwired, or is the header Phi emitted before
  the Loop structure?
- logical L4 (not): lli exited 1. `!EXPR` returns a genuine primitive Bool (i1);
  needs the Bool representation + Not(Bool)->Bool + Coerce(Bool->*) edges. The
  corpus L4 constructive case already lowers GREEN, so this is a producer/repr
  wiring gap on the B::SoN path, not a backend gap.
- control-flow D4 (postfix if) / D5 (postfix while): now emit clean And nodes
  after RC2, but die with "And LHS repr=Bool; only Int truthiness lowered". Needs
  a Coerce(Bool->Int) inserted before the And (or TypeInference to annotate the
  comparison result as coercible). Shares the Bool-repr axis with L4.

Acceptance: D2/D3 while+foreach -> lli == perl; L4 not -> Bool: == perl;
D4/D5 postfix -> lli == perl. Re-run t/bootstrap/corpus/son-corpus-wide.t and
confirm green count rises from 34.

Cross-repo: producer fixes land in perl5-son (branch phase4b-single-exit),
cross-referenced by stage name; backend/repr fixes land in Chalk.
