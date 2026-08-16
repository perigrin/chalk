# A GAP is a compilation failure, not a resting state

**Date:** 2026-08-16
**Status:** FINDING. Changes a scoring assumption I have been applying
unexamined all session, and reverses one recommendation.

## The correction

I have been treating a loud GAP as a safe state and scoring it as neutral —
"PASS=4 SKIP=3, zero miscompiles" read to me as a clean result. perigrin:

> You've been treating GAPs as better / more correct than miscompiles but GAPs
> are also compilation failures, just usually ones we are expecting … they're
> still literally a GAP in the expected output.

That is right, and the distinction I was collapsing is:

- **For debugging**, a GAP is much better than a miscompile: it names the
  construct and stops, instead of producing a wrong answer nothing reports.
- **As product**, they are the same outcome: the program did not compile
  correctly. A user with a GAP and a user with a miscompile both do not have a
  working program.

GAP-not-miscompile remains a real invariant — reporting beats silence. But it
is a rule about HOW to fail, not a licence to count failures as zero.

## What it changes, measured

The step-5 shape suite, scored two ways. Nine cases, both polarities where
applicable, run through `ProgramRunner` (stdout AND exit status vs a perl
oracle).

| | PASS | did NOT compile correctly |
|---|---|---|
| `pu` (current) | **4** | 5 — all GAP |
| `modifier-effect-in-arm-parked` (`98d7d24`) | **6** | 3 — malformed IR, `lli` exit 1 |

Per-case:

| case | pu | parked |
|---|---|---|
| mod-print c0 / c1 | PASS | PASS |
| mod-elem c0 / c1 | PASS | PASS |
| **voidcall-taken / untaken** | **GAP** | **PASS** |
| nested-if-store d0 / d1 | GAP | malformed IR |
| postmerge-read | GAP | malformed IR |

**The parked branch compiles two more programs correctly than `pu` does.**

I had scored this as "pu is safe at 4 PASS, parked has 3 FAILs" and recommended
staying on `pu`. Counting GAPs honestly, parked is +2 PASS and −2 failures. The
three it does not fix are `lli exit 1` — loud, and no worse as product than the
GAP they replace. Both are "this program does not run."

**So my recommendation to revert and wait for the backend was wrong on the
merits.** The parked branch is strictly better than `pu` today and has been
sitting unmerged since 2026-08-13 partly because this scoring treated GAPs as
free.

## What does NOT change

The revert of MY attempt still stands, and for a reason that survives the
correction: my change turned the void-call case from a GAP into a SILENT
miscompile while fixing nothing. Both columns had 4 failures; mine just moved
one from reported to unreported. Strictly worse on both axes.

The parked branch is different in kind: it converts failures into PASSes.

## What the parked branch still needs before merging

Not a blocker list — a review list. It is better than `pu` as it stands.

1. **Its gate is still the `_arm_has_*` disjunction** the prior art rejects,
   and it EXTENDS the predicates to descend into nested branches — the
   fifth-scan trap. That is a reason to follow it with the unconditional
   rewrite, not a reason to withhold a net improvement.
2. **The full producer suite has not been run on it** on a clean build. That is
   the check that caught my miscompile, and it must run before merge.
3. **The chalk corpus gate has not been run against it.** Cross-repo, no
   version pin, so this must be serialized and self-verified.
4. Its three remaining failures are malformed IR on the nested-store shape —
   the backend Phi-placement wall that attempts 2, 4, 5 and this branch all
   hit. Merging does not fix that and does not make it worse.

## The general lesson

A scoreboard that counts one failure mode as neutral will rank a change that
converts failures into successes BELOW a change that converts nothing. I ran
that scoreboard for an entire session without examining it, and it produced a
recommendation to keep a worse producer.

When measuring "did this help", count what the user gets: programs that
compile and run correctly. Every other state is a failure, however politely it
announces itself.
