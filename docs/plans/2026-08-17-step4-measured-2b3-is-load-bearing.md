# Step 4 measured: the 2b-3 refusal is load-bearing for a SECOND reason

**Date:** 2026-08-17
**Status:** MEASURED, both producer probes REVERTED. Producer clean on
`pu`/`6c54ec4`.
**Prerequisite landed:** `f2971b5f` (Phi-before-Region).

## What was tested

With the Phi-before-Region wall down, step 4 was: make void-branch construction
unconditional and see whether the producer's 2b-3 refusal is still needed.

Two probes, applied together in the producer:

1. `$mem_branch = ($op->flags & 3) == 1` — unconditional, no arm scans.
2. The 2b-3 refusal (`FromOptree.pm:509`) disabled, on the grounds that its
   stated reason is exactly what `f2971b5f` fixed:

   > with no element store advancing the memory chain the backend has no
   > Region/If in the Return's control path to place that Phi against
   > (Phi-before-Region)

## Result: the refusal is still needed, for a reason it does not state

The GAP goes away and the case translates — and then MISCOMPILES:

    my $n = 5;
    my $x = 0;
    $x = 1 if $n > 0;
    print $x, "\n";

    perl : "1\n"
    chalk: "0\n"        <- the rebind does not take effect

So `f2971b5f` removed the *die* but not the *defect*. The value-Phi is now
placeable — lowering no longer aborts — but the value it selects is wrong: the
merge takes the base binding rather than the arm's.

**That is a distinct bug from Phi-before-Region**, and the refusal has been
covering it. Its comment describes only the placement problem; the wrong-value
problem was invisible behind the die, because nothing ever got far enough to
observe it.

## Corrected chain, again

Each step measured. Step 4 does not simply follow from step 3:

1. ~~nested merge-Phi placement~~ — a missing pre-lowering descent (`67f0aba7`)
2. ~~collapse pass as prerequisite~~ — unreachable by its motivating case
3. ~~Phi-before-Region~~ — **landed** (`f2971b5f`); removes the die
4. **value-Phi on a control-path-invisible Region selects the WRONG ARM** —
   the current floor, newly visible
5. then unconditional construction
6. then the collapse pass
7. then delete the four predicates

## The RED, and why it must be backend-side

`docs/plans/` cannot hold a producer-dependent RED for this: reproducing it
needs both probes applied, and neither is landing. The durable form is a
hand-built IR test — a diamond whose arms rebind a scope slot with NO element
store, asserting the merged value is the arm's when the guard is taken.

`t/bootstrap/ir/llvm-empty-diamond-collapses.t` already builds nearly that
shape and PASSES its select assertion, which means the existing fixture does
not discriminate: its two arms are distinct constants feeding a Phi, and the
select picks correctly. The failing case differs in that the arm's value is a
REBIND of a slot that already had a binding — base vs arm, not two independent
constants. That distinction is what the next test has to encode.

## Method note

Third time in this arc a "prerequisite" turned out to be one layer above the
real floor, and the third time the correction came from RUNNING the probe
rather than reasoning from the previous fix. The pattern is consistent enough
to state as a rule: a fix that removes an error message has not been shown to
fix the condition the message described — run the case the message was
guarding.
