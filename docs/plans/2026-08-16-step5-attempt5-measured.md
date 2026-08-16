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

## What this establishes

**Unconditional construction is necessary but NOT sufficient**, and the
blocker is in the backend, not the producer:

1. A nested merge needs the ENCLOSING branch to have built control flow too,
   or its memory-Phi is stranded. Fixing one nesting level at a time cannot
   work — the levels are coupled.
2. Making every void branch build control flow exposes that **the backend
   cannot place a Phi whose incoming value is itself a merge**. That is the
   wall attempts 2, 4 and now 5 all hit, from three different directions.
3. A void CALL in a modifier body needs more than control flow: the call must
   also be pinned so it is emitted on its arm. Building the If is not enough
   if nothing places the effect.

So the prior art's recommendation stands and its ORDER is now measured: the
collapse pass is not the only missing piece. **Nested merge-Phi placement in
the backend is a prerequisite for unconditional construction**, not a
consequence of it.

## What the next attempt needs, before touching the producer again

1. **Backend: place a Phi whose incoming value is a nested merge.** Build the
   RED at the IR level (hand-built graph, no producer), since the producer
   currently refuses to emit the shape. This is the actual blocker.
2. **Then** unconditional construction at both sites, together — they are
   coupled and cannot be staged.
3. **Then** the collapse pass, to remove the redundant diamonds unconditional
   construction creates.

Do NOT attempt the producer half again before (1). Three attempts have now
produced malformed IR at exactly that point.

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
