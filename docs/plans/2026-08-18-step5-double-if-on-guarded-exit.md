# Step 5: unconditional construction builds a DOUBLE If on a guarded exit

**Date:** 2026-08-18
**Status:** MEASURED, producer change REVERTED. Clean on `pu`/`6c54ec4`.
**Prerequisites landed and unaffected:** `67f0aba7`, `f2971b5f`, `44d1fa8c`.

## What was attempted

Land the producer half for real: void-branch construction unconditional, 2b-3
refusal deleted. Both were probe-verified in step 4 and the three backend fixes
they needed are in.

## Behaviour is correct; SHAPE is not

The 10-case behavioural suite: **PASS=5 SKIP=5, zero miscompiles**, including
`pure-rebind` which step 4 fixed. Spot-checked the three postfix-modifier
shapes the producer tests cover, all correct:

| case | perl | chalk |
|---|---|---|
| `$x = 1 if $n > 0` | `1` | `1` |
| `$x = 1 unless $n > 0` | `0` | `0` |
| `$x += 1 if $c` | `11` | `11` |

So `t/from-optree-postfix-modifier.t` 1-4 fail on SHAPE (they assert
`TernaryExpr` and get a diamond), not on answers. Those are the tests the
collapse pass exists to satisfy, and they are expected to fail until it lands.

## The blocker: a real structural regression on `return X unless C`

`t/from-optree-guarded-exit.t` subtests 2-3 are a different matter. Measured on
`sub f { my $c = shift; return 99 unless $c; return 42 }`:

    pu:                   1 If node
    with this change:     2 If nodes

    %5  = If(%1, %4)        <- built unconditionally, on the RAW condition
    %6  = Proj(index: 1, %5)
    %7  = Proj(index: 0, %5)
    %8  = Not(%4)
    %9  = If(%7, %8)        <- the exit handler's own negated If
    %10 = Proj(index: 1, %9)

The guarded-exit path (`FromOptree.pm:~402-437`) builds its OWN `If(Not(C))`
for `return X unless C`, on the documented premise that no If exists yet — the
negation is what puts the exit on the TRUE branch so it aligns with the exit
value in the single-exit Phi. Unconditional construction breaks that premise:
a diamond is already there, and the handler stacks a second one on top of its
true-Proj.

**Not verifiable behaviourally today** — that shape hits an unrelated inliner
GAP (`direct call to 'main::f': callee has effect(s) on its control chain`), so
`lli` never runs it. The producer test is the only oracle, which is exactly why
it must not be edited to accommodate the change.

## What this establishes

Unconditional construction cannot simply replace the gate: **sites downstream
assume no If was built for a void `and`/`or`**, and the guarded-exit handler is
one of them. The prior art's "build the diamond everywhere" is right, but in
Chalk it requires the exit handler to CONSUME the already-built diamond rather
than construct its own.

So step 5 splits again:

- **5a. Make the guarded-exit path reuse an existing If** instead of building
  one. Its RED is `t/from-optree-guarded-exit.t` subtests 2-3, which already
  discriminate and are green on `pu`.
- **5b.** Then unconditional construction lands, with postfix-modifier 1-4
  still red pending the collapse pass.
- **5c.** The collapse pass turns the pure-rebind diamond back into a select,
  making those four green and completing the sequence.
- **5d.** Delete the four predicates.

## Method note

The full producer suite has now caught three distinct problems this arc that a
curated behavioural suite did not: the silent void-call miscompile (attempt 5),
the infinite loop (parked branch), and this double-If. In each case the
behavioural numbers looked fine — here they were PASS=5 with zero miscompiles
while the graph was structurally wrong.

Behavioural checks measure the cases you thought to write. The producer's own
tests measure invariants somebody established when they built the thing.
