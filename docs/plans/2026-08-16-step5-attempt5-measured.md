# Step 5, attempt 5: unconditional construction alone is NOT sufficient

**Date:** 2026-08-16
**Status:** MEASURED AND REVERTED. Nothing landed in the producer.
**Parent scope:** `docs/plans/2026-08-16-step5-scope-corrected.md`
**Prior attempts:** 1-4 in
`docs/plans/2026-08-13-post-merge-statement-ownership.md`. This is the fifth.

## What was tried

Exactly what the scope specified, and what the prior-art survey recommends:
delete the arm-content discriminator, build control flow unconditionally in
void context.

Two sites were changed:

1. **`FromOptree.pm:~4360`** — the modifier/nested-branch-in-an-arm refusal.
   Replaced the `_arm_has_*` disjunction with unconditional `If` + `Proj`
   construction plus `$sim->merge`.
2. **`FromOptree.pm:~378`** — the top-level void `and`/`or` `$mem_branch` gate.
   Replaced with `($op->flags & 3) == 1` (void context) alone.

## What was measured, in order

**Site 1 alone:** the shape suite went SKIP=3 → 0, PASS 4 → 6. But
`nested-if-store-d1` became a SILENT MISCOMPILE — perl `9\n`, chalk `1\n`.

Diagnosed by reading the graph rather than guessing. The working single-level
case reads `Subscript(%1, %2, %11)` where `%11` is the memory-Phi. The nested
case read `Subscript(%1, %2, %3)` where `%3` is `MemStart` — the PRE-store
memory. Instrumenting `merge()` confirmed it built the Phi correctly
(`sim.mem` went MemStart → Phi); the problem was that the ENCLOSING branch
built no control flow, so the Phi had no Region on the outer control path and
the outer read never saw it.

**Site 2 as well:** worse. `lli` exited 1 on all three nested cases —
MALFORMED IR, a use of an undefined `%tmp`. The backend cannot place a Phi
whose incoming value is itself a nested merge. **This is the same failure mode
as attempts 2 and 4**, which also produced malformed IR.

**Site 2 reverted, site 1 kept, plus a guard** refusing when the body advanced
memory while this branch's own control was not already on a Proj. That reached
PASS=4 SKIP=3 with zero miscompiles — the same counts as baseline, with a GAP
message naming the real limit.

**Then the full producer suite, on a clean build, found the real problem.**
Two PRE-EXISTING tests failed:

- `t/from-optree-nested-if.t` subtest 7: "a void-effect statement modifier
  inside an arm still GAPs loudly"
- `t/from-optree-void-direct-call.t` subtest 3: "nested branch in the arm stays
  a loud GAP"

Both assert the old GAP. Rather than update them, I verified the shape they
cover, bilaterally:

    my $x = 5; my $y = 5;
    if ($x > 3) { print "helper\n" if $y > 3 }
    print "end\n";

    perl : "helper\nend\n"
    chalk: "end\n"              <- the guarded print DROPPED, silently

**My change introduced a miscompile in the void-CALL case.** The guard-not-taken
polarity passed. Those two tests were right, and they caught it.

Reverted. The loud GAP is restored and both tests are green again.

## CORRECTION, same day: the void-call case is NOT blocked — my code was wrong

perigrin pushed back on the revert: "if unconditional construction is necessary
but not sufficient, why revert? The goal is correctness not ease of
implementation." The revert itself was right — my change turned a loud GAP into
a silent miscompile, and that trade is forbidden regardless of effort. But the
CONCLUSION I drew from it was too broad, and one measurement shows it.

The PARKED branch (`modifier-effect-in-arm-parked`, `98d7d24`) was built and
measured against the same cases:

| case | parked branch |
|---|---|
| `if ($x>3) { print "helper\n" if $y>3 }` guard TAKEN | **PASS** — perl `helper\nend\n`, chalk `helper\nend\n` |
| same, guard NOT taken | **PASS** |
| `mod-print-c0` / `c1` | PASS |
| `mod-elem-c0` / `c1` | PASS |
| `nested-if-store-d0` / `d1` | **FAIL, lli exit 1 — malformed IR** |
| `postmerge-read` | **FAIL, lli exit 1 — malformed IR** |

So the void-CALL case is SOLVABLE, and something in the parked implementation
gets it right that mine did not. Point 3 below ("a void CALL needs more than
control flow") is WITHDRAWN as a statement about the problem; it was a
statement about my code.

What survives, now confirmed from a THIRD independent direction: the
nested-STORE cases fail with malformed IR on the parked branch too — same
`exit=1`, same wall as attempts 2, 4 and 5. That half is a real backend
blocker.

The blocker is therefore NARROWER than this document originally claimed:
**nested merge-Phi placement**, not "unconditional construction in general".
The void-call half can proceed independently, and the parked branch is the
starting point for it rather than a dead end.

## What this establishes

**Unconditional construction is necessary but NOT sufficient for the
nested-store shape**, and that half's blocker is in the backend:

1. A nested merge needs the ENCLOSING branch to have built control flow too,
   or its memory-Phi is stranded. Fixing one nesting level at a time cannot
   work — the levels are coupled.
2. Making every void branch build control flow exposes that **the backend
   cannot place a Phi whose incoming value is itself a merge**. That is the
   wall attempts 2, 4 and now 5 all hit, from three different directions.
3. ~~A void CALL in a modifier body needs more than control flow.~~
   **WITHDRAWN — see the correction above.** The parked branch handles the
   void-call case correctly on both polarities. That was a defect in my
   implementation, not a property of the problem.

So the prior art's recommendation stands and its ORDER is now measured: the
collapse pass is not the only missing piece. **Nested merge-Phi placement in
the backend is a prerequisite for the nested-STORE half**, not a consequence
of it.

## What the next attempt needs

The work SPLITS, and only one half is blocked:

**Half A — the void-call / void-effect shapes. NOT blocked.** The parked branch
(`modifier-effect-in-arm-parked`, `98d7d24`) already passes these bilaterally.
It cannot be merged as-is — its gate is still the `_arm_has_*` disjunction the
prior art rejects, and its predicates were EXTENDED to descend into nested
branches, which is the fifth-scan trap. But its CONSTRUCTION code is correct
where mine was not, and diffing the two is the cheapest way to find what I got
wrong. Start there.

**Half B — the nested-store shapes. Blocked on the backend.**

1. **Place a Phi whose incoming value is itself a merge.** Build the RED at the
   IR level (hand-built graph, no producer), since the producer refuses to emit
   the shape. Attempts 2, 4, 5 AND the parked branch all produce malformed IR
   at exactly this point — four independent directions, same wall.
2. **Then** unconditional construction at both producer sites, together.
3. **Then** the collapse pass, to remove the redundant diamonds.

Do NOT attempt half B's producer side before (1).

## What survives

- The backend ownership fix (`60a4bec6`) is unaffected and stays.
- The chalk-side bilateral test
  (`t/bootstrap/ir/llvm-postmerge-read-ownership.t`) is unaffected and stays
  green.
- The producer RED written today is preserved in the session scratchpad as
  `producer-red-2026-08-16.t`. Its subtest 3 (the shapes that already work) is
  the regression guard any future attempt needs.
- `~/dev/perl5-son` is CLEAN at `pu`/`6c54ec4`. Nothing was committed there.

## Method note

The suite caught this, not my own testing. My 7-case shape suite showed
PASS=4 SKIP=3 and zero miscompiles AFTER the guard — a green result on the
cases I chose. The miscompile was in a shape I had not thought to write, and
two tests written months ago for a different reason were pinning it. Running
the full producer suite on a clean build before believing a green subset is
what turned a shipped miscompile into a reverted branch.
