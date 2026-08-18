# The 2b-3 refusal still earns its keep: a THIRD defect behind it, inverted arms

**Date:** 2026-08-18
**Status:** MEASURED. Producer change DISCARDED, not parked — it is unlandable
as written. Clean on `pu`/`6c54ec4`.
**Answers the decision in:** `docs/plans/2026-08-18-step5a-done-oracle-found.md`

## The check that settled it

That doc flagged two of the eight producer-test failures as needing a
behavioural check before the stash could land, and named
`void-direct-call` subtest 4 as the dangerous one: it asserts a GAP that now
lowers, which is *exactly* the shape of attempt 5's silent miscompile.

It was right to flag it. Measured, bilaterally:

    my $x = 5; my $n = 0;
    if ($x > 3) { print "call\n"; $n = 5 }
    print "n=$n\n";

      perl : call / n=5        chalk: call / n=0      WRONG

    my $x = 1; my $n = 0;          # guard false
    if ($x > 3) { print "call\n"; $n = 5 }
    print "n=$n\n";

      perl : n=0               chalk: n=5             WRONG

**Both polarities wrong, and INVERTED** — the Phi selects the opposite arm in
each case. Not a missing value, a swapped one.

## Why the earlier fixes did not cover this

`44d1fa8c` taught the backend to read the Phi's arm pairing off the Region
instead of assuming slot 0 is the then-arm, and that fixed the pure-rebind
case (`$x = 1 if $n > 0`, verified PASS). This shape is different: the arm
carries a void CALL *and* a rebind, so the merge has an effect on the control
chain as well as a value to select. The pairing that is correct for a
rebind-only arm is evidently not what this shape produces.

So the 2b-3 refusal has been covering **three** distinct defects, discovered in
this order:

1. **Placement** — a Phi on a Region no memory-Phi pins to the control path
   could not be lowered at all. Fixed, `f2971b5f`.
2. **Value (rebind-only)** — the backend assumed Phi slot 0 was the then-arm
   while the producer builds Region inputs continuing-path-first. Fixed,
   `44d1fa8c`.
3. **Value (void call + rebind)** — arms inverted, both polarities. **OPEN.**

Its comment names only (1). Each removal of a layer exposed the next.

## Verdict on the stash

**Discarded.** It contained unconditional construction, the 5a If-reuse, and
the 2b-3 deletion; the third of those makes a silent miscompile reachable, and
the first two are what make the third reachable in this shape. Landing any part
of it now would trade a loud GAP for a wrong answer.

`program-return` subtest 2 (no program Return at all) was NOT separately
diagnosed — the miscompile settles the question the two checks were asked to
answer, so it stays open with the rest.

## The state of step 5, honestly

Landed and standing, all backend, all verified:

- `67f0aba7` pre-lower store operands through nested branches
- `f2971b5f` a Phi read before its Region drives that Region
- `44d1fa8c` a Region Phi reads its arm pairing from the graph

Not landed, and now with a known blocker:

- unconditional construction + 5a If-reuse + 2b-3 deletion, blocked on defect
  (3) above.

The next step is a backend RED for defect (3) — a hand-built diamond whose arm
holds BOTH a control-pinned effect and a value the merge selects — and then the
fix. The producer change stays out until that is green.

## Method note

The producer test earned its keep twice over. It failed for a reason that
looked like stale-convention drift (asserting a GAP that no longer fires), and
the honest read would have been to update it. Checking the behaviour instead
found an inverted miscompile in both polarities.

The pattern from this whole arc, now with a fourth instance: **a test that
fails because "the thing it guards against no longer happens" is a claim to
verify, not an assertion to update.** Four times now the verification found a
real defect: attempt 5's void-call drop, the parked branch's infinite loop, the
double-If, and this.
