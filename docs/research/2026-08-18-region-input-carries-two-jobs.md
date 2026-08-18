# The Region input carries TWO jobs, and that is why the pairing is a search

**Date:** 2026-08-18
**Status:** MEASURED. The proposed producer fix is WRONG and was reverted.
Producer clean on `pu`/`6c54ec4`.
**Amends:** `docs/research/2026-08-18-phi-pairing-should-not-be-a-search.md`,
whose diagnosis holds but whose proposed fix does not.

## What was proposed, and why it fails

That doc concluded: make a Region's control inputs be Projs always, then the
backend's backward walk collapses to `$controls[$slot]->index` — a field read.
The reasoning was sound (every production SoN IR stores a stable per-edge
carrier there) and one of Chalk's two frontends already does it.

Implemented in the producer (`StackSim::merge`, walking each arm's control back
to its Proj at construction) and it **breaks a bare block**:

    sub { my $c=0; { print "first\n" if $c; print "after\n"; } print "end\n"; 1 }

    t/from-optree-bare-block.t: all three prints reachable on the control chain
      expected 3, got 2
      control chain = [Return Print Print Region Proj Proj]

Two Projs adjacent in the chain. Substituting the Proj for the arm's last node
**severed the effects behind it**, dropping a Print off the control chain
entirely — a silent miscompile, and that test exists because this exact class
happened before.

## The actual structure

A Region input is doing TWO jobs at once:

1. **Arm identity** — which branch does phi slot *i* correspond to?
2. **Control-chain link** — what ran last on that path, so the chain from
   Return reaches every effect?

The prior art satisfies both because its carrier sits at the END of the arm:
Graal's `EndNode` terminates its block and is what the merge points at, so it
identifies the edge *and* is the chain link. Chalk's `Proj` sits at the
BEGINNING of the arm — it is what the arm hangs off, not what the arm ends on.

So "use the Proj" trades job 2 away for job 1. They are not interchangeable
in this IR, and that is a real structural difference from Graal, not a
producer oversight.

## What this means for the walk

The backend's `_proj_index_of_control` walk (`9ce43cdd`) is **not** removable by
that route. It is recovering job-1 information from a node that is carrying
job 2, and only one of the two can occupy that slot.

The options that remain, unattempted:

- **A. Store the pairing explicitly**, LLVM-style: keep the Proj alongside each
  phi value so arm identity is data rather than convention. LLVM chose exactly
  this because predecessor order is not stable — which is Chalk's situation
  between two producers. Costs a parallel array; makes the misordering
  unrepresentable. **Does not disturb job 2 at all**, which is why it is now
  the leading candidate.
- **B. Add an end-of-arm carrier**, Graal-style: a node that terminates each
  arm and is what the Region points at, with the Proj remaining the arm's head.
  Structurally closest to the prior art and the largest change — it adds a node
  kind to the IR.
- **C. Keep the walk**, and add the missing invariant so a future divergence
  fails loudly rather than miscompiling.

## The invariant is still missing, and is worth doing under any option

`TypedInvariant.pm` mentions Region once, in a comment, and Phi not at all.
Every surveyed system asserts phi arity against region arity: C2's
`"broken Phi/Region subgraph"`, Graal's
`phiPredecessorCount() == valueCount()`, TurboFan's
`CHECK_EQ(value_count, control->op()->ControlInputCount())`.

Chalk has had THREE phi-pairing miscompiles in this arc and no assertion that
would have caught any of them. That is independent of which option above is
chosen.

## Method note

The proposal came from prior art that was correctly read and a Chalk-side
divergence that was correctly measured — and it was still wrong, because both
observations were about job 1 and neither was about job 2. The producer test
caught it in one run.

Fifth instance this arc of the same lesson: the full suite catches what a
targeted check cannot. Here the targeted check would have been "does the phi
pair correctly now" — and it would have said yes.
