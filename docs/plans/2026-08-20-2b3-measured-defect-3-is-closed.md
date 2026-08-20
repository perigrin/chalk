# The 2b-3 refusal: defect 3 is CLOSED, and the failure count is 2, not 8

**Date:** 2026-08-20
**Status:** MEASURED. No code changed — the probe was a temporary guard
suppression, reverted. Both repos clean (chalk `6e7bf58a`, perl5-son `1752b9d`).
**Supersedes the status line of:**
`docs/plans/2026-08-18-the-2b3-refusal-still-earns-its-keep.md`, which records
defect 3 as **OPEN**.

## The question

That doc says the 2b-3 refusal masks three defects, two fixed and one open:

3. **Value (void call + rebind)** — arms inverted, both polarities. **OPEN.**

with a measured reproduction: `if ($x > 3) { print "call\n"; $n = 5 }` giving
`n=0` where perl gives `n=5`, and the false polarity giving `n=5` where perl
gives `n=0`. Both wrong, and inverted.

Re-measured on today's HEAD before designing a fix.

## Result: defect 3 does not reproduce

Suppressing the refusal (`FromOptree.pm:513`) behind an env probe and lowering
through the corpus gate's own path:

| shape | perl | chalk |
|---|---|---|
| `call-rebind` true | `call` / `n=5` | **MATCH** |
| `call-rebind` false | `n=0` | **MATCH** |

Both polarities of the doc's own repro now agree with perl.

Widened to 14 shapes, since one case passing is not the refusal's surface —
the statement-modifier spelling, two rebinds in one arm, if/else where BOTH
arms call and rebind, a rebind that READS the slot after the call, a string
rebind (different repr), and the already-fixed rebind-only shape, each
bilaterally:

**14 of 14 MATCH.**

## What actually closed it, and the guess I got wrong

My first reading was that `predecessors` (`05b99107`) closed it — the defect is
an inverted arm pairing, which is exactly what that field exists to prevent, and
the Phi in this graph does carry `predecessors: [8, 10]`.

**That is wrong.** Stripping `predecessors` back out of the producer JSON and
re-lowering gives the SAME correct answer on both polarities. The field is not
load-bearing here; the fallback search handles it.

The fix was `9ce43cdd` — "find a Region input's Proj through the control chain".
The doc predates it by hours and its defect-3 measurement was taken before it
landed. The doc even says so about defect 2 without noticing it covers this
shape too: an arm carrying a void call ends its control chain on the Call, not
on the Proj, which is precisely the case `9ce43cdd` taught the backend to walk
back through.

Recording the wrong guess because it was one strip-and-rerun away from being
recorded as fact.

## The failure count is 2, not 8

The doc reports 8 producer-test failures with the refusal lifted. Measured on a
clean build (`rm -rf blib`, `prove -Ilib -Iblib/lib -j1`):

**95 files, 515 tests, 2 failures** —
`from-optree-void-direct-call.t` subtest 4 and
`from-optree-arm-scan-bound.t` subtest 4.

Both assert that the GAP still fires. They are the "test fails because the thing
it guards against no longer happens" shape, which this project has learned to
treat as a claim to verify rather than an assertion to update — four times that
verification found a real defect. Here the verification is the 14-shape sweep
plus the gate, and it says the guard is what is stale.

The other 6 failures the doc counted are gone. Not investigated further: they
were measured against a producer six commits back, and re-deriving why each
disappeared is worth less than the sweep already done.

## The corpus gate does not move

With the guard fully disabled (`if 0 && $arm_rebinds`):

    TOTAL: gate-green=198 behavior=198 shape=198 invariant=198 worklist=0

exit 0, zero not-ok. Identical to HEAD with the guard in place. So lifting the
refusal costs nothing measurable and buys the 14 shapes above.

## What this does NOT establish

- **No corpus case covers these shapes.** The gate not moving means no
  REGRESSION, not that the shapes are pinned. Nothing in the corpus exercises a
  void-call-plus-rebind arm; that is why the refusal could go stale unnoticed.
- **The sweep is 14 hand-written shapes**, not a proof. `attempt 5` shipped a
  silent miscompile past a smaller check, which is why the guard exists.
- **`_arm_has_element_store` is untouched here.** The refusal has a second
  condition and this measurement only exercised the `$arm_rebinds` half.

## Recommended next step

Lift the refusal in a commit that ALSO lands the corpus cases pinning it —
bilateral pairs for at least `call-rebind`, `both-arms`, and `str-rebind`, using
the D1f/D1g pattern (effectful arms are what build a real merge Phi; a
pure-armed if/else collapses to TernaryExpr and pins nothing).

Order matters: the two producer subtests must be rewritten to assert the new
behaviour IN THE SAME commit that removes the guard, so neither a stale GAP
assertion nor an unpinned lift can land alone.
