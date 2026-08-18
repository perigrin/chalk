# 5a: the fix works, and I cannot prove it. Blocked on a missing oracle.

**Date:** 2026-08-18
**Status:** MEASURED, REVERTED. Producer clean on `pu`/`6c54ec4`.
**Predecessor:** `docs/plans/2026-08-18-step5-double-if-on-guarded-exit.md`

## What 5a was

Make the guarded-exit path REUSE the If that unconditional construction has
already built for the same `and`/`or`, instead of building a second one on the
first one's true-Proj.

## It works, structurally

The double-If is gone: `sub f { my $c = shift; return 99 unless $c; return 42 }`
goes from 2 If nodes back to 1.

And the graph it produces is RIGHT, checked on both polarities. Both emit
`Region(%6, %7)` with `Phi(99, 42)` — exit value in slot 0 — and the Projs
carry the alignment:

| source | `%6` is | so `99` lands on |
|---|---|---|
| `return 99 if $c` | Proj index 0 (true) | the TRUE arm |
| `return 99 unless $c` | Proj index 1 (false) | the FALSE arm |

Both correct. The `or` case needs no `Not(C)` when reusing, because the
existing node achieves the same alignment BY INDEX (it puts the `or` body on
Proj 1) rather than by negating. Negating as well would invert it back and
reintroduce the miscompile the original comment describes.

## Why it is reverted anyway

`t/from-optree-guarded-exit.t` subtests 1 and 3 fail, and they are CONVENTION
assertions that my change inverts:

    and-guarded exit continues on Proj index 1 (guard false)   GOT 0
    the unless guard tests Not(C), not C                       GOT PadAccess

So the question is whether the new convention is also correct — and **I cannot
answer that behaviourally**. Both shapes hit an unrelated inliner GAP:

    GAP: direct call to 'main::f': callee has effect(s) on its control chain
    (print/store/...) that inlining does not yet thread in program order

`lli` never runs them. perl says `42,99` and `99,42`; chalk says nothing.

That leaves the producer test as the only oracle for a change to the producer —
and passing it would mean editing the assertions to match my own edit. That is
not verification, it is agreement with myself. The whole arc has been about not
doing that.

## What would unblock it

An oracle that does not route through the inliner. Either:

1. **Fix the inliner GAP** (`Context.pm:5455`): a direct call whose callee has
   control-chain effects. Then `ge1`/`ge2` run and the polarity question is
   settled by perl, in the only currency that counts.
2. **Or find a guarded-exit shape that lowers today** — `return X unless C` at
   top level rather than inside a sub, if that shape exists and reaches the
   backend. Not yet checked; worth ten minutes before attempting (1).

Option 2 is cheap and should be tried first.

## What did NOT change

- The double-If diagnosis stands, and so does the fix's structure: reuse when
  `$if_node` is defined, in both polarities, taking `$false_proj` as the
  continuation. That code is in this document's git history via the revert, and
  can be reapplied verbatim once an oracle exists.
- Backend prerequisites (`67f0aba7`, `f2971b5f`, `44d1fa8c`) are landed and
  unaffected.
- Producer suite is green on `pu`: 95 files, 515 tests.

## Method note

Third time this arc that the honest move was to stop rather than make a test
agree with me. The first was reverting my own silent miscompile; the second was
declining to merge the parked branch on a scoreboard I had just got wrong.

The rule this one adds: **when the only oracle for a change is a test you would
have to edit, you do not have an oracle.** Find one, or leave the change out.
