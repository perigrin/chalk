# 5a works, verified against a real oracle. 8 shape assertions remain — your call.

**Date:** 2026-08-18
**Status:** Producer change PARKED in a `git stash` on `pu` (message:
"step5: unconditional construction + 5a If reuse + 2b-3 deletion"). Not
committed; the decision below is not mine to make.
**Supersedes:** `docs/plans/2026-08-18-step5a-blocked-on-missing-oracle.md`,
whose blocker is resolved.

## The oracle exists after all

That doc said 5a could not be verified because both `return X unless C` shapes
hit an unrelated inliner GAP, leaving only a producer test I would have had to
edit to match my own change. It proposed spending ten minutes looking for a
shape that lowers today before attempting an inliner fix.

Ten minutes was enough. **`exit N unless C` at top level lowers and runs**, on
both polarities, with DIFFERENT exit codes — fully discriminating:

    my $c = 0;  print "before\n";  exit 7 unless $c;  print "after\n";
      perl "before\n" exit 7   chalk "before\n" exit 7    PASS

    my $c = 1;  print "before\n";  exit 7 unless $c;  print "after\n";
      perl "before\nafter\n" exit 0   chalk same          PASS

That settles the polarity question the producer test could not: **the new
convention is behaviourally correct.**

## What is in the stash

1. **Unconditional void-branch construction** (`$mem_branch = OPf_WANT_VOID`),
   deleting three of the four arm scans at that gate.
2. **5a: the guarded-exit path reuses the existing If** instead of stacking a
   second one on its true-Proj. The `or` case needs no `Not(C)` when reusing,
   because the existing node achieves the same alignment BY INDEX (it puts the
   `or` body on Proj 1). Double-If confirmed gone: 2 nodes back to 1.
3. **The 2b-3 refusal deleted**, both halves of its rationale now false
   (placement by `f2971b5f`, value by `44d1fa8c`).

## Behaviour: 15 cases, PASS=10 SKIP=5, ZERO miscompiles

Including every shape the failing producer tests cover:

| case | result |
|---|---|
| `$x = 1 if $n > 0` / `unless` / `$x += 1 if $c` | PASS |
| one-armed `if ($n > 0) { $x = 1 }`, both polarities | PASS |
| `exit 7 unless $c`, both polarities (exit codes 7/0) | PASS |
| pure-rebind, mod-print, mod-elem | PASS |
| nested-if-store, postmerge-read, voidcall | SKIP (unrelated modifier GAP) |

## The remaining 8 failures are SHAPE assertions

`prove t/` on a clean build: 4 files, 8 subtests. Every one asserts the OLD
node shape, and each has correct behaviour measured behind it:

| test | asserts | now gets | behaviour |
|---|---|---|---|
| `postfix-modifier` 1-4 | `TernaryExpr` | a diamond | correct (`pm1`/`pm2`/`pm4` PASS) |
| `nested-if` 5 | `TernaryExpr` | `Phi` | correct (`onearm1`/`onearm0` PASS) |
| `guarded-exit` 1, 3 | continuation on Proj 1; `If(Not(C))` | Proj 0; `If(C)` | correct (`ge3`/`ge4` PASS, exit codes match) |
| `void-direct-call` 4 | old GAP still fires | it lowers | not yet behaviourally checked |
| `program-return` 2 | "found the program Return" | no Return | **structural, NOT checked** |

## THE DECISION, and why it is not mine

Six of those eight are tests pinning a select-shaped merge that unconditional
construction replaces with a diamond. That is the expected consequence, and the
collapse pass (step 5c) is what makes them green again. Updating them now would
mean editing tests to match my own change — the thing this arc has repeatedly
stopped to avoid — while landing the change with them red means a red suite
until 5c.

**Two are NOT in that category and should be resolved before either option:**

- `program-return` 2 reports NO program Return at all. That is structural and
  could be a real regression; I have not checked it behaviourally.
- `void-direct-call` 4 asserts an old GAP still fires. It now lowers, which may
  be an improvement or may be the silent void-call miscompile from attempt 5
  returning. Attempt 5's miscompile was exactly "a case that used to GAP now
  lowers, wrongly" — so this one needs a bilateral behavioural check before it
  is called progress.

## Recommendation

1. Check `program-return` 2 and `void-direct-call` 4 behaviourally. If either
   is a real regression, the stash is not landable as-is.
2. If both are clean: land the stash WITH the six shape tests marked TODO
   naming step 5c, rather than rewriting their assertions. A TODO records that
   the shape changed and is expected to change back; a rewritten assertion
   records nothing.
3. Then 5c (collapse pass) turns the diamonds back into selects and the TODOs
   into passes.

## Method note

The previous doc's blocker was real but I stopped one search short of the
answer. The rule it stated still holds — when the only oracle is a test you
would have to edit, you do not have an oracle — but the corollary is: **look
harder for an oracle before concluding there is none.** A different SHAPE of
the same construct (`exit` instead of `return`) reached the backend when the
obvious one did not.
