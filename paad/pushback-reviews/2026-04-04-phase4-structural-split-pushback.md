# Pushback Review: Phase 4 Structural Split + Braun SSA

**Date:** 2026-04-04
**Spec:** docs/plans/2026-04-04-phase4-structural-split.md
**Commit:** 7b83b64d

## Source Control Conflicts

None — no conflicts with recent changes.

## Issues Reviewed

### [1] Braun fights Earley's completion order for if/else
- **Category:** feasibility
- **Severity:** serious
- **Issue:** Braun assumes backward walk through CFG predecessors, but Earley completions process if-bodies before IfStatement fires. Full Braun is unnecessary for if/else — Earley gives us both branches' scopes at merge time.
- **Resolution:** Hybrid approach: eager Phi at if/else (Click-style, info available at completion), lazy Phi at loops (sentinel mechanism). Not pure Braun but correct and works with Earley's natural order.

### [2] IfStatement doesn't fork/merge scopes today
- **Category:** feasibility
- **Severity:** serious
- **Issue:** IfStatement passes scope unchanged through Region. Per-branch scope threading needed. Verified that Context/cfg_state carries per-branch scopes via multiply() — IfStatement can read child Contexts to get branch-final scopes.
- **Resolution:** IfStatement reads per-branch scopes from child Contexts, diffs against pre-if scope, creates Phis for differing variables. Feasible with existing infrastructure.

### [3] Phase 4 scope imbalance — SSA scope is the hard part
- **Category:** scope imbalance
- **Severity:** serious
- **Issue:** Part A (SSA scope) requires: reassignment tracking, per-branch scope forking, eager Phi creation, trivial removal, sentinel integration. Much larger than the mechanical structural split.
- **Resolution:** Split into Phase 4a (SSA scope) and Phase 4b (structural split). 4a is independently testable and risky. 4b is safer with 4a complete.

### [4] Scope doesn't track reassignments
- **Category:** omission
- **Severity:** serious
- **Issue:** `$x = expr` (Assign) doesn't update scope — only `my $x` (VarDecl) does. Without this, if/else Phis are meaningless since the scope never sees the reassignment.
- **Resolution:** AssignmentExpression updates scope for plain assignments. New SSA value per reassignment.

### [5] ReturnStmt and DieCall disposition
- **Category:** omission
- **Severity:** moderate
- **Issue:** Not specified in original design. Both are control flow, not computation.
- **Resolution:** ReturnStmt → Return CFG node, DieCall → Unwind CFG node. Created during graph construction in Phase 4b steps 4-5. Dual Call projections remain deferred.

### [6] TernaryExpr disposition
- **Category:** omission
- **Severity:** minor
- **Issue:** Candidate for CFG lowering (If+Proj+Region+Phi) but adds complexity.
- **Resolution:** Keep as computation node. Lower in future pass after foundation is solid.

### [7] _Attribute disposition
- **Category:** omission
- **Severity:** minor
- **Issue:** Not specified. Used inside FieldDecl for :param/:reader/:writer.
- **Resolution:** Becomes plain hashref `{name => $str}`. Phase 4b step 2.

### [8] Atomic C+D risk
- **Category:** feasibility
- **Severity:** serious
- **Issue:** Changing Actions.pm output and codegen input simultaneously is high-risk.
- **Resolution:** Migrate one structural type at a time: UseDecl → FieldDecl → MethodDecl → SubDecl → ClassDecl → Program. Each step independently verifiable against 16 green files.

## Summary

- **Issues found:** 8
- **Issues resolved:** 8
- **Unresolved:** 0
- **Spec status:** Updated and ready for implementation planning
