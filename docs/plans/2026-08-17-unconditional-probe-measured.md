# Unconditional construction, measured: same 8/9 as the parked branch, and it terminates

**Date:** 2026-08-17
**Status:** PROBE, measured and REVERTED. Producer clean on `pu`/`6c54ec4`.
**Answers:** "why are we still doing arm scans?" and "what if we applied the
parked branch and resumed from there?"

## Why arm scans are still there

Because nothing has deleted them. They were worked past in the RESEARCH
(2026-08-13) and in the PLAN (step 5), never in the code. On `pu` today: 4
predicates, 26 references, 16 live calls at 4 gate sites — unchanged since the
survey said to remove them.

Worth naming plainly: three separate times in this arc I have been working ON
arm-scan code the plan says to delete — attempt 5, then the parked-branch
evaluation, then a ~50-minute diagnosis of an infinite loop INSIDE a mechanism
that should not exist. The diagnosis was correct and the target was wrong.

## Why not resume from the parked branch

Measured, three-way, on the 9-case shape suite with the backend dominance fix
(`67f0aba7`) in place:

| | PASS | terminates? | arm scans at these gates |
|---|---|---|---|
| `pu` | 4 | yes | yes |
| parked branch (`98d7d24`) | 8 | **NO — infinite loop** | yes, and EXTENDED |
| unconditional probe | **8** | **yes** | **none at the two gates** |

Same 8, identical per-case — both pass everything except `postmerge-read`, and
with the same failure mode (prints `1\n`, drops `done\n`).

So resuming from the parked branch would inherit its non-termination
(`docs/plans/2026-08-17-parked-branch-nontermination-found.md`), keep the
predicates the prior art says to delete, and then require this work anyway. The
unconditional version reaches the same score without either, in ~15 lines
against the parked branch's 107.

The parked branch's real value was its construction code showing what my
attempt 5 got wrong. That is now absorbed: build the If and both Projs BEFORE
the body walk, route the body onto its Proj, and finish with a structural
`$sim->merge` rather than a value-only rebind.

## But the probe is NOT ready, and the full suite says why

`prove -Ilib -Iblib/lib -j1 t/` on a clean build: **4 files, 8 subtests
failing.** `t/from-optree-postfix-modifier.t` loses 4 of 7, and those are REAL
regressions, not stale GAP assertions:

    not ok 1 - postfix if merges the assignment as TernaryExpr(cond, arm, base)
    not ok 2 - postfix unless puts the arm on the false side
    not ok 3 - chained modifiers: the second reads the first's merged value
    not ok 4 - read-modify arm: $x += 1 if $cond

`$x = 5 if $cond` is a PURE REBIND. It has no effect to order, so the
value-only `TernaryExpr` merge is correct for it and a diamond is not. Making
the MODIFIER site unconditional converts those into control flow and breaks
them.

This is exactly the regression the third subtest of my own producer RED was
written to catch ("the shapes that already worked still work" — the pure rebind
must still merge as `TernaryExpr`, not gain an If). It caught it.

## What this establishes

**Unconditional construction is right for the branch sites and wrong for the
modifier site, and the discriminator between them is not arm CONTENT.** It is
whether the construct has an effect to order at all:

- a void `and`/`or` that IS a statement (`if (C) { ... }`) — always build
  control flow; measured, this is safe and terminates
- a statement MODIFIER whose body only rebinds (`$x = 5 if C`) — a select, and
  the ternary merge is correct

That is close to the distinction the prior art already draws: Graal builds the
diamond at every BRANCH, and its collapse pass later turns an empty-armed
diamond back into a select. Chalk has no collapse pass, so a diamond built for
a pure rebind stays a diamond — and the postfix-modifier tests are pinning the
select form.

So the honest ordering is now measured, and it is the reverse of what I assumed
this morning:

1. **The collapse pass is not optional cleanup — it is the prerequisite.**
   Without it, unconditional construction cannot be applied to the modifier
   site without regressing every pure-rebind shape.
2. Then unconditional construction at both sites.
3. Then delete the predicates.

## What is landed and unaffected

- The backend dominance fix (`67f0aba7`) — the thing that made 8/9 reachable at
  all, and the reason the "malformed IR / nested merge-Phi" blocker is gone.
- The backend ownership fix (`60a4bec6`).
- `postmerge-read` remains a separate, pre-existing defect: both Prints are in
  the producer graph, one is not emitted.
