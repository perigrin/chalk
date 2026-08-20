# The mixed-effect refusal was also a stale pairing claim

**Date:** 2026-08-20
**Status:** LANDED. Corpus gate 202 -> 206, four new bilateral cases.
**Follows:** `docs/plans/2026-08-20-2b3-measured-defect-3-is-closed.md`, which
lifted the PRODUCER's 2b-3 refusal. This is the BACKEND's.

## The refusal

`Target/LLVM/Context.pm`, `_wire_region_phis_with_preblock`: when an arm both
rebinds a scalar (a value-Phi) and stores an element (a memory-Phi), the two
merge on the same Region and the backend refused outright.

Its stated reason:

> The value-Phi's arm order for this shape is not yet reconciled with the
> element store, and wiring it produces a wrong value (the scalar reads the
> wrong arm).

That is a **pairing** claim, and pairing stopped being a search. Twenty lines
below the die, the same function already reads arm identity off the Phi:

    my $then_slot = _phi_slot_from_predecessors($phi_node, 0)
                 // _phi_slot_for_proj($region, 0);

Measured: for this shape the producer emits BOTH Phis with
`predecessors: [15, 13]` — the field is there, so the arm is a field read, not
an inference. The refusal was reasoning about a problem that had been solved.

That makes **two** refusals in two days whose premise had expired, both cited as
current in their own comments. The pattern is worth naming: a refusal states a
reason at the moment it is written, and nothing re-checks that reason when the
cause is fixed elsewhere.

## The measurement

Fourteen shapes, each bilateral, lowered through the corpus gate's own path with
the die suppressed:

| shape | result |
|---|---|
| store then rebind | MATCH |
| rebind then store (order swapped) | MATCH |
| print, then store, then rebind | MATCH |
| Str rebind beside the store | MATCH |
| two stores in one arm | MATCH |
| if/ELSE, both arms store and rebind | MATCH |
| HASH element store beside a rebind | MATCH |

**14 of 14 MATCH** on stdout and exit status.

Corpus gate with the die fully disabled: `gate-green=202 behavior=202 shape=202
invariant=202 worklist=0`, exit 0, zero not-ok — unchanged from HEAD.

## What landed

- The die is gone, with the history and the measurement written where it stood.
- `@mem_phis` became write-only once the die left; the partition collapses to
  one `grep`. The memory-Phi is still excluded from value wiring — that part was
  never the refusal.
- **R21–R24** in `t/corpus/mdtest/references.md`: two bilateral pairs, array
  (R21/R22) and hash (R23/R24). Both aggregate kinds because array and hash take
  different payload paths, and a memory-Phi correct for one only would pass a
  single-kind test.

Floor 202 -> 206.

## The cases bite

Verified rather than assumed: restoring the die takes all four RED with the
exact GAP message (`gate-green=202 ... worklist=4`) and fails the floor. They
pin the lift.

## What this does NOT establish

- **The 14 shapes are hand-written, not a proof.** Both lifted refusals were
  guarding against real defects when written; only the causes moved.
- **`_has_branch_guarded_store`'s refusal is untouched** and still fires — an
  element read across a branch-guarded store with no memory-Phi. Different
  condition, different phase, not measured here.
- **Nothing was measured about nested branches** — every probe is one branch
  deep.

## Verification

- corpus gate, self-verified on committed HEAD: exit 0,
  `gate-green=206 behavior=206 shape=206 invariant=206 worklist=0`, zero not-ok
- IR tier: 80 files / 728 tests PASS
