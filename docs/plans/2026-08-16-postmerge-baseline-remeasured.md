# Post-merge ownership: the baseline is stale, and there is a LIVE MISCOMPILE

**Date:** 2026-08-16
**Status:** FINDING, measured. Blocks nothing from being *started*, but changes
what should be started first.
**Parent:** `docs/plans/2026-08-13-post-merge-statement-ownership.md` (step 5)

## Why this was measured

That plan's step 1 says: "Decide the ownership contract explicitly ... Write
that as a testable invariant before editing." Correct, and the first thing a
testable invariant needs is a current baseline. The plan's recorded baseline is
**PASS=5 FAIL=6 over 11 cases**, taken 2026-08-13.

It is now stale in two ways, and one of them is serious.

## 1. The producer half is GONE

That plan's State section records:

> perl5-son: `lib/SoN/FromOptree.pm` modified + `t/from-optree-modifier-effect-in-arm.t`
> untracked, both UNCOMMITTED. Correct work, but **must not land alone**.

Measured today: `~/dev/perl5-son` is on `pu` at `6c54ec4`, working tree CLEAN.
`t/from-optree-modifier-effect-in-arm.t` does not exist. `_arm_has_die` still
bails on a nested branch (`FromOptree.pm:3961`, `return 0 if $name eq 'and' ||
$name eq 'or' || $name eq 'cond_expr'`) — the pre-fix state.

So the "producer half is BUILT AND CORRECT, backend half is blocked" framing no
longer describes reality. **Both halves are now unbuilt.** Anyone picking up
step 5 who trusts the plan's State section will look for work that is not there.

Whether that change was deliberate (parked, as the plan advised) or lost is not
established here. The plan said to park it on a branch; no such branch was
found, but I did not exhaustively search reflogs.

## 2. A LIVE SILENT MISCOMPILE, not previously recorded

Measured through the real harness (`ProgramRunner->run_file`, which compares
stdout AND exit status against a perl oracle), on chalk `a1338ec4`:

    my @a = (1);
    my $c = 0;
    if (1) { $a[0] = 9 if $c; }
    print $a[0], "\n";

    perl : stdout "1\n"  exit 0
    chalk: stdout ""     exit 0        <-- WRONG, and SILENT

The `print` is dropped entirely. Exit status matches, so nothing flags it; there
is no GAP. This is a GAP-not-miscompile invariant violation, the class this
project treats as most serious.

**Its opposite polarity PASSES.** `$c = 1` gives "9\n" from both. So a
single-polarity test would show green — the exact vacuous-polarity trap the
parent plan warns about, firing on a case the parent plan does not list.

### Full re-measured baseline (7 cases, both polarities where applicable)

| case | verdict | detail |
|---|---|---|
| nested-if-store-d0 | SKIP | GAP: statement modifier with a void effect / element store / die inside an if/else arm |
| nested-if-store-d1 | SKIP | same GAP |
| mod-print-c0 | PASS | |
| mod-print-c1 | PASS | |
| **mod-elem-c0** | **FAIL** | **perl "1\n" vs lli "" — silent, both exit 0** |
| mod-elem-c1 | PASS | |
| postmerge-read | SKIP | same GAP |

**PASS=3 FAIL=1 SKIP=3.** Not comparable to the parent plan's PASS=5 FAIL=6 —
that was 11 cases including shapes not reproduced here, and it was taken with
the producer change applied. Do NOT compare the two numbers; re-measure the
parent's own 11-case suite before using its scores for anything.

Note that `mod-print-c0`/`c1` both PASS. So the void-effect modifier is not
uniformly broken — a void `print` in a modifier inside an arm works today, while
an element store in the same position silently drops a later read. That
distinction is new information and narrows where to look.

## What this changes about step 5

1. **There is now a concrete RED that is a MISCOMPILE, not a GAP.** The parent
   plan's cases are mostly GAP-declared, which the corpus gate `pass()`es
   without running. `mod-elem-c0` is different: it compiles, runs, and produces
   the wrong answer. It is the strongest available test target and it did not
   need the ownership contract to be decided first.
2. **The contract work still stands**, but it is no longer the only entry
   point. Fixing a silent miscompile is higher priority than a refactor by this
   project's own stated ordering (correctness > simplicity), and this one has a
   discriminating bilateral pair already written.
3. **The parent plan's State and baseline sections must be corrected** before
   anyone acts on them. They describe a producer change that is not present and
   a score that cannot be reproduced.

## What was NOT determined

- **Why** the print is dropped. No instrumentation was run; this records the
  observation only. Do not assume it is the same mechanism as the
  collection/emission disagreement the parent plan diagnoses — that is a
  hypothesis, and the parent plan's own history is four hypotheses that
  measured worse.
- Whether `mod-elem-c0` reproduces with the producer change reapplied.
- Whether the parent's other four cases (not reproduced here) still behave as
  recorded.

## Reproduction

Cases and driver are in the session scratchpad (`case_*.pl`, `baseline5.pl`,
driving `Chalk::CodeGen::Harness::ProgramRunner`). They are seven files of four
lines each and are cheaper to rewrite than to preserve; the sources are quoted
above and in the parent plan.
