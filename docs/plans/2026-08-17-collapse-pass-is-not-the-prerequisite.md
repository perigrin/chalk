# The collapse pass is NOT the prerequisite either — Phi-before-Region is

**Date:** 2026-08-17
**Status:** MEASURED. Probe reverted, producer clean on `pu`/`6c54ec4`.
Supersedes the sequencing conclusion in
`docs/plans/2026-08-17-unconditional-probe-measured.md`.

## What I set out to build, and why it was wrong

Yesterday's probe showed unconditional construction breaks 4 of 7 subtests in
`t/from-optree-postfix-modifier.t` — `$x = 1 if $c` must stay a `TernaryExpr`
and got a diamond instead. I concluded the collapse pass was the prerequisite:
build the diamond unconditionally, then collapse an empty-armed one back to a
select.

**Measured, that could not have worked.** With unconditional construction, a
pure rebind does not reach the backend at all:

    B::SoN: skipped main::__PROGRAM__: GAP: void-context 'and' arm combines a
    void call with a scalar rebind (2b-3 mixed effect not yet lowered)
    at lib/SoN/FromOptree.pm line 509

The producer refuses it before any IR is emitted. A backend collapse pass
operates on graphs that exist; this graph never gets built. I was about to
build a pass that could not have been reached by the case it was for.

Caught by running the probe and reading its actual output rather than reasoning
forward from the test failure.

## The real blocker, in the producer's own words

`FromOptree.pm:495-502`:

> A void-call arm that ALSO rebinds a scope var is 2b-3 territory: `merge()`
> would build a value-Phi for the rebound slot, but **with no element store
> advancing the memory chain the backend has no Region/If in the Return's
> control path to place that Phi against (Phi-before-Region)**. An
> element-store arm is the supported 2b case (the memory-Phi carries it). GAP
> loudly rather than emit an unplaceable Phi.

So: a value-Phi on a Region can only be placed if something ELSE put that
Region on the Return's control path. Today only a memory-Phi from an element
store does that. A pure rebind advances no memory chain, so its Region is
control-path-invisible and its Phi is unplaceable.

**That is a backend limitation, and it is mine to fix** — the same shape as
this morning's dominance bug, which also read as "the producer can't" until it
turned out to be twenty backend lines.

## Corrected chain

Each step here has been measured, and each previous "prerequisite" I named
turned out to be a symptom of the next one down:

1. ~~nested merge-Phi placement~~ — was a missing pre-lowering descent, fixed
   (`67f0aba7`).
2. ~~the collapse pass~~ — cannot be reached by the case that motivated it.
3. **Phi-before-Region: place a value-Phi on a Region that no memory-Phi pins
   to the control path.** This is the current floor.
4. Then unconditional construction stops GAPping on pure rebinds.
5. Then the collapse pass — still wanted, to turn the now-buildable empty
   diamond back into a select so `postfix-modifier` keeps passing.
6. Then delete the four predicates.

Note 5 does not disappear; it moves after 3. The postfix-modifier tests pin the
select form and unconditional construction will still produce a diamond for
them.

## What NOT to do next

Do not build the collapse pass first. It is step 5, its input does not exist
until step 3, and building it now repeats the error this document records.

Do not touch the producer before step 3. Three producer attempts have now
failed against backend limits (attempts 2, 4, 5), and a fourth against the
2b-3 GAP. The pattern is that the producer change is small and the backend is
where the work is.

## The RED that exists

`t/bootstrap/ir/llvm-empty-diamond-collapses.t` (uncommitted, written for
step 5) currently fails for a THIRD reason worth recording: its hand-built
pure diamond dies with "Phi node encountered in lower_value before its
enclosing if/loop structure was processed", which is the same
Phi-before-Region wall from the backend side. So the test accidentally
reproduces step 3's blocker at the IR level, without a producer — which is
exactly the RED step 3 needs. Keep it; retarget it at Phi placement rather
than collapse.
