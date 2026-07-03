# Alignment Review: RC2b — loop lowering (D2/D3) + not/Bool-repr (L4, D4/D5)

**Date:** 2026-07-03
**Commit:** 5df32523 (Chalk, phase1-lateral-bindings) / a9630f8 (perl5-son, phase4b-single-exit)

## Documents Reviewed

- **Intent:** git-zhi issue 019f1c1e (acceptance criteria + case list)
- **Action:** the implementation itself — perl5-son fa7e8ef, 60c6ade, d20f1e1,
  b1530fb, a9630f8; Chalk db166680, 5df32523
- **Design:** docs/plans/2026-07-01-phase4-corpus-wide-status.md (RC2b section)

## Source Control Conflicts

None — the commits under review are the current session's; the plan doc was
updated in the same window.

## Issues Reviewed

### [1] Acceptance criteria coverage
- **Category:** coverage
- **Severity:** n/a (fully covered)
- **Issue:** every AC item verified with direct evidence:
  D2 while -> lli Int:6 == perl (plus zero-iteration Int:5, single-var Int:12);
  D3 foreach -> Int:6 (plus empty-range Int:7); L4 not -> Bool: == perl;
  D4 postfix if -> Int:1 (plus false-path Int:0 and unless polarity Int:1);
  D5 postfix while -> Int:6 (plus pre-test zero-iteration Int:0);
  corpus-wide green 34 -> 39 (t/bootstrap/corpus/son-corpus-wide.t).
- **Resolution:** aligned.

### [2] Implementation deviates from the issue's HYPOTHESIZED fixes
- **Category:** design gap (in the filing, not the implementation)
- **Severity:** minor
- **Issue:** the issue predicted "Region.head unwired" for D2/D3 and
  "Coerce(Bool->Int) before the And" for D4/D5. Investigation falsified both:
  D4 was a semantic miscompile (void-context arm over-walk), D5 a loop
  misclassified as value context, D2/D3 post-hoc SSA construction. No Coerce
  node was added anywhere.
- **Resolution:** alignment is judged against acceptance criteria, which are
  met; the falsification is recorded in the issue's Outcome section and the
  plan doc.

### [3] Behavior changes beyond the AC (honesty guards)
- **Category:** scope compliance
- **Severity:** minor (accepted)
- **Issue:** three silently-wrong paths were converted to loud GAP dies:
  function exit inside a loop body, loop-carried type widening, until
  (or-condition) loops; general-list foreach now dies instead of emitting a
  wrong graph. These are guards required to keep the new machinery honest,
  consistent with the RC4 "loud > silently wrong" lesson.
- **Resolution:** in scope as correctness guards; each documented in commits.

## Unresolved Issues

None blocking. Five adjacent findings filed as new issues (019f26a5 family):
bare side effects in modifier arms dropped; nested and/or inside a loop body;
StackSim::snapshot mark collapse; cond_expr/dor arm over-walk; loader
forward-ref hardening.

## Alignment Summary

- **Requirements:** 6 AC items, 6 covered, 0 gaps
- **Tasks:** 6 slices executed, 6 in scope, 0 orphaned
- **Status:** ALIGNED

## TDD Task Rewrite

Not applicable to the completed work (all six slices were executed RED-first;
the RED tests are in the commits). The five follow-up issues carry their fix
directions in their bodies; they will get RED-first treatment when picked up.
