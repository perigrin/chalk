# The parked producer branch: +4 PASS, and an infinite loop. Do not merge as-is.

**Date:** 2026-08-16
**Status:** MEASURED. Verdict: do not merge; the construction code is
salvageable, the branch is not.
**Branch:** `~/dev/perl5-son` `modifier-effect-in-arm-parked` (`98d7d24`)
**Prerequisite landed:** the backend dominance fix (`67f0aba7`), without which
this branch produces malformed IR on the nested-store shapes.

## Why it was being considered

Scored honestly — counting a GAP as the compilation failure it is, not as
neutral — the branch is a clear improvement on the 9-case shape suite, once
the backend dominance fix is in:

| | PASS (of 9) |
|---|---|
| producer `pu`, backend before `67f0aba7` | 4 |
| producer parked, backend before | 6 |
| **producer parked, backend after** | **8** |

Two checks were outstanding before merging: the full producer suite on a clean
build, and the chalk corpus gate cross-repo. The first one settles it.

## The blocker: `t/b-son-backend.t` never terminates

Measured, same machine, same perl, clean build of each:

| branch | `t/b-son-backend.t` |
|---|---|
| `pu` | **passes, ~seconds**, `1..12` |
| `modifier-effect-in-arm-parked` | **hangs** — killed at 39 minutes, then reproduced with a 120s timeout: no test output at all |

The full-suite run had to be killed. This is not slowness; the test produces
its seed line and then nothing.

**What makes it a real signal rather than a test-fixture problem:** subtests
8-10 of that file run an UNFILTERED discovery pass, which walks every loaded
package including the producer's own vendored `SoN::IR::*`. So the loop is
being hit on ordinary production code, not on a contrived fixture. A
`package=X` filter narrows discovery enough to miss it, which is why the
targeted probes I ran earlier — and the 9-case shape suite — all looked clean.

## Verdict

**Do not merge.** A branch that does not terminate on the producer's own source
is not a net improvement however many cases it fixes: it converts a bounded
failure (a GAP, or a wrong answer) into an unbounded one. That is worse on the
same axis the +4 PASS is better on.

This is also the answer to "why not just merge it, GAPs are failures too" —
the honest scoring stands, and the branch still fails, on a check the shape
suite could not see.

## What is salvageable

The construction code, which is measurably better than mine. My own attempt 5
turned the void-call case into a silent miscompile; this branch handles it
correctly on both polarities. Diffing the two is the cheapest way to find what
I got wrong, and that diff is the input to the real fix — not the branch.

Its gate remains the `_arm_has_*` disjunction the prior art rejects, and it
EXTENDS those predicates to descend into nested branches (the fifth-scan trap),
so it was never mergeable as a final shape regardless.

## What this establishes about the work

The backend dominance fix (`67f0aba7`) stands on its own and is landed: nested
merge-Phi placement was never the wall — a missing pre-lowering descent was.
Four attempts read it as a backend limit because the malformed IR looked like a
Phi-placement failure.

So the remaining producer work is:

1. Take the parked branch's CONSTRUCTION, not its gate.
2. Find and fix the non-termination before anything else — it is on real code
   and will resurface in any branch that reuses this construction.
3. Then the unconditional rewrite, which is the shape the prior art actually
   recommends.

## Method note

The 9-case shape suite said 8/9. The targeted probes said clean. The FULL SUITE
ON A CLEAN BUILD said infinite loop. That is twice in one session the full
suite caught something a curated subset could not — the first was the silent
miscompile my own attempt introduced. Curated suites measure what you thought
to ask about.
