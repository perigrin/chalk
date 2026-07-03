---
title: "RC2b: loop lowering (D2/D3) + not/Bool-repr (L4, D4/D5) (Phase 4)"
state: in-progress
urgency: normal
milestone: codegen-harness
created: 2026-07-01T05:19:46.301125195Z
updated: 2026-07-03T21:49:51.880109733Z
sessions:
- start_sha: 96214d2af17ccadd460500300bdf9006fbc41b79
  end_sha: 5df3252337de2ce6069a94148b18fb3cb9b8a99f
  commits: 2
  started_at: 2026-07-03T04:56:38.418410821Z
  ended_at: 2026-07-03T06:18:50.031474196Z
- start_sha: 5df3252337de2ce6069a94148b18fb3cb9b8a99f
  end_sha: ""
  commits: 0
  started_at: 2026-07-03T21:41:24.561556319Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-03T04:56:38.418410821Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-07-03T06:18:50.031474196Z
- state: reopened
  actor: human:git-zhi
  timestamp: 2026-07-03T21:41:24.521816136Z
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-07-03T21:41:24.561556319Z
observed_paths:
- docs/plans/2026-07-01-phase4-corpus-wide-status.md
- lib/Chalk/IR/Serialize/JSON.pm
- t/bootstrap/ir/son-loop-backedge.t
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

### Outcome (2026-07-03, DONE)

All five cases GREEN; corpus-wide green 34 -> 39 (t/bootstrap/corpus/son-corpus-wide.t).
Investigation FALSIFIED the filed hypotheses -- none of these needed Coerce(Bool->Int):

- L4: Not missing from %RESULT_STAMP (perl5-son fa7e8ef). Bool: == perl.
- D4: semantic miscompile -- the void-context and/or arm walk consumed the rest
  of the sub. Fixed: arm stop-op at the convergence point + TernaryExpr(cond,
  arm, base) rebinds (perl5-son 60c6ade). Bilateral if/unless + false-path green.
- D2: producer built SSA post-hoc. Rewritten two-phase (scout -> pre-walk header
  Phis -> set_backedge patch; Projs directly on Loop, exit Region) per the
  corpus contract (perl5-son d20f1e1). Chalk loader defer-patches the forward
  Phi-backedge ref a loop cycle forces (Chalk db166680, RED-first via a
  hand-authored corpus-shape JSON that lowers to Int:6); producer DFS cuts
  exactly the backedge so that is the only forward ref. Zero-iteration green.
- D5: back-edge detected (arm walk stops on a pre-visited op) -> routed to the
  while machinery (perl5-son b1530fb). Pre-test zero-iteration green.
- D3: enteriter range form desugared to the corpus counted loop (induction Phi,
  NumGt(high+1, i), synthesized +1 step) (perl5-son a9630f8). General-list
  foreach = honest GAP. Empty-range green.

Made loud instead of silently wrong: return inside a loop body, loop-carried
type widening, until (or-condition) loops.

Verification: perl5-son suite 303; Chalk IR suite 558; son-e2e 22 GREEN/3 GAP/0
BUG (baseline preserved); son-compare + cross-load + emit + ir-serialize clean.
perl5-son branch phase4b-single-exit pushed (a374d42..a9630f8).

### Review Findings (2026-07-03, TIER_2 gate -- reopened)

Full report: paad/code-reviews/phase1-lateral-bindings-2026-07-03-rc2b-5df32523.md
20/20 findings verified. Fix pass scope (everything else filed as 019f29ed follow-ups):

1. _walk_loop_body guards: die GAP for last/next/redo, cond_expr,
   enterloop/enteriter, any branch op; die if a second condition mints Projs.
   (C1+C2: silent miscompiles reproduced -- last-> Int:15 vs Int:1, if/else
   in body -> Int:0 vs Int:103, nested while -> Int:3 vs Int:6.)
2. Side-effecting-condition guard: die GAP when the loop condition segment
   mutates any pad slot (C3/C5 class: while(\$i-- > 0) family, postfix init
   contamination). Full lowering filed separately.
3. Ambiguous-condition guard: die GAP when >1 icmp consumes header Phis
   (C4: decoy body comparison hijacks the condition -> Int:5 vs Int:4).
   Real control-wiring fix filed separately.
4. Unstamped-backedge: die GAP instead of silently un-stamping (stale stamps
   contaminate sibling Phi joins).
5. foreach: IV_MAX bound guard; non-lexical iterator (targ==0) truthful GAP.
6. perl5-son from_json: defer-patch forward Phi backedges (round-trip of its
   own loop graphs currently dies); fix the false topo comment.
7. Chalk _lower_ternary: coerce Int condition to i1 (icmp ne) mirroring
   _lower_and -- makes bare-scalar guards (\$x = 7 if \$c) and plain ternary
   (\$c ? 7 : 5) lowerable; loud GAP for other reprs.
### Review fix pass (2026-07-03, DONE)

All 7 gate items landed (perl5-son b484a2f, Chalk 1afa515d):
items 1-6 as loud GAP guards + the from_json defer-patch (round-trip
restored); item 7 (_lower_ternary truthiness) is a FULL fix -- bare-scalar
guards ($x = 7 if $c) and plain scalar ternaries are now GREEN e2e.
Verified: reviewer repro cases now refuse at the producer (last-in-loop,
decoy comparison); perl5-son suite 320; Chalk IR suite 560; corpus-wide
green holds at 39. Real fixes for the guarded classes filed as the
019f29ed family; loader Phi-slot hardening noted on 019f26a5 #5.
