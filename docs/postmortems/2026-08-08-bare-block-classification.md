# Postmortem: bare-block-classification

**Completed:** 2026-08-08 · 4/4 issues · 24/24 ACs (23/24 on the first verification pass;
the failure was a defective AC of mine, corrected)
**Plan:** `docs/plans/2026-08-07-bare-block-misclassification.md` (v2, double-assessed)
**Commits:** perl5-son `2162f8e`; chalk `f3377a7f`, `650d1b00`, `f133d240`

## Outcome

| | before | after |
|---|---|---|
| silent miscompile (statements dropped after a conditional in a bare block) | live, no GAP | **closed** |
| segfault (other polarity) | lli signal 11 | **closed** |
| corpus gate | 157 | **161** (4 new GREEN executing cases) |
| `"loop without a lowerable condition"` | 5 ring files | **1** |
| executable gate | 4/5 | 4/5 (held) |
| regressions | — | **zero** (per-file baseline comparison, detached worktree) |

The fix is **6 lines**: a back-edge-less `enterloop` (`nextop == lastop`) is a lexical
scope, not a loop (`SoN/FromOptree.pm:567`).

## 1. The headline is the ordering, not the fix

**Two designs died before six lines shipped.** Both were mine, both were killed by
measurement, and both were bigger than the problem.

**The world token** — effect ordering as a typed graph edge. Killed from opposite
directions by two independent reviews: **unsound** (sibling arms share an incoming
world, so corpus D1e's two identical `Print`s hash-cons — retiring
`%STATEMENT_EFFECT_OPS` reintroduces miscompile 019eb6ff item 1) *and* **unnecessary**
(closed 1 of 4 measured bugs where ~20 lines closed all four). The decisive finding:
**arity is not ordering.** `Print(w0)→w1; Unwind(w0)` has perfect world arity and *is*
the F1 miscompile — the validator I proposed could not see the bug the design existed
to prevent.

**F3** — reshape `Call` as a memory transformer. Killed because its *motivation* was a
proxy metric: measured **0 of 40** ring files and **0 of 5** executable-gate programs
unblocked. Worse, `define` emission **already existed** in `_emit_class_registry_ir`
(I proposed building shipped machinery), and the kill-set lattice I built the design's
spine around had **no consumer anywhere**.

Meanwhile the largest single movement of the product metric available was **two `if`
guards** suppressing a debug type-tag epilogue: executable gate **1/5 → 4/5**.

## 2. The proxy-metric error is a reflex, not an incident

**Three occurrences in one session.** Ranked by t/-file-unblock counts (occurrence 1,
recorded 2026-08-02); by "N parallel mechanisms with no authority" (the world token);
by GAP-site count inside one function (F3). Every time the north star is *"does this
file become a program that runs"* and I ranked by **internal structure**.

**The damning part:** the gate that measures the real thing (`executable-gate.t`) was
*built in response to occurrence 1* — and I still did not consult it before designing
occurrences 2 and 3.

**Building the metric was not sufficient. Consulting it has to be an explicit step
before ranking any work.**

## 3. Six AC defects, every one silent, and one new species

| | defect | effect |
|---|---|---|
| a | **`ag` has no `-q` flag** — errors rc=1 regardless of content | 6 ACs unpassable; 8 negated guards **vacuously true** |
| b | corpus gate prints **double** spaces | single-space pattern could never match |
| c,d | two doc ACs grepped lowercase against prose written in CAPS | silent fail |
| e | producer pretty-prints `"op" : "Print"` | `'"op":"Print"'` could never match |
| f | **NEW SPECIES:** `prove t/bootstrap/corpus/` as an AC for a directory that has **never** been green (5 pre-existing failures) | an AC that can **never pass** — a false RED where the other five were false GREENs |

Both directions of one root cause: **I write patterns from what I assume output looks
like, not from output I have looked at.**

(e) was caught by the executing subagent, which flagged my AC as defective rather than
working around it. (f) was caught by the verification pass on its first working run.

## 4. I recorded a guess as a cause, and it cost the next milestone its verification layer

When `effect-chain-fix` extracted **zero** AC commands, I diagnosed it as
milestone-creation order, "fixed" it by creating the milestone object first, and
**wrote that into memory as the cause.**

Chain-review found the real cause: `git-zhi-verify` extracts **only `- [ ]` checkbox
bullets**. Measured across the whole store — checkbox milestones extract 100%
(son-ir-divorce 34/34, ir-node-unification 59/59); the two using plain `- ` bullets
extracted **0 of 39** and **0 of 20**.

I created *this* milestone object first and still got zero, which should have told me
immediately. **A guess recorded as a cause is worse than an open question** — it sent
the next milestone down the same hole with a false sense of having fixed it.

## 5. The verification layer worked for the first time and immediately earned its keep

**24 commands extracted** (vs 0 last milestone), reported **23/24**, and the single
failure was a real defect in my own acceptance criterion. First working run, and it
caught something I had missed.

## 6. I created a false-done

b3 was marked complete while I was testing whether AC extraction worked, and the state
stuck — **its work was never done.** Caught by running the issue's own ACs rather than
trusting the state field, which is exactly why those ACs exist.

**Never flip issue state to test tooling. Use a scratch milestone.**

## 7. Subagents caught things I would have missed — and one caught itself

**b1's executor caught its own false green.** Its first test counted `Print` nodes
*present* in the graph and passed against the buggy code — because hash-consed nodes
stay in the graph even when disconnected from control. It rewrote the test to walk the
control chain backward from `Return`, and *that* produced the correct RED. Present vs
control-reachable is the exact subject of this milestone, and it found the distinction
unprompted.

**b2's executor refused my plan's wording.** It drafted two cases as GAP because the
plan said so, measured the real producer output, found they already lowered correctly,
and corrected them to GREEN before commit. Had they shipped as GAP they would have
pinned **nothing** — forever — while reading as coverage.

## 8. Every prediction about the payoff was wrong, including the reviewers'

- v1: the fix collapses "7 messages plus a `StackSim` internal error" into 1.
- A reviewer: baseline is 4, expect 7 after.
- **Measured: 20 distinct blocker messages remain**, because each newly-reachable file
  reveals its own next blocker.

`StackSim`/"Stack underflow" is observed **zero** times in the ring — but the string
*does* exist (`StackSim.pm:25`), so **"not observed" is the correct claim, not "does
not exist."** A reviewer corrected my framing on that.

**The number that actually mattered — `"loop without a lowerable condition"` falling
from 5 files to 1 — was predicted by nobody.**

Also corrected: my *"159 of 166 lib files / sits under the entire self-hosting path"*
**overstated the lib axis.** The GAP always lands on `main::__PROGRAM__`, which
`Phase5LibCoverage.pm:94` does not count — so this fix buys **zero Phase-5 lib
coverage**. Where it *is* load-bearing is `__PROGRAM__` itself: the bare-file
executable path. Truer and stronger.

## 9. A third gate blind spot

`son-corpus-wide.t:133-139` `pass()`es a GAP-declared case **without running its
source**. So GAP-message drift is undetectable (T4c declares one message, the producer
emits another), **and** a GAP-declared case that has silently started working is
undetectable.

That second consequence **fired during this milestone** — two cases drafted as GAP
already lowered correctly.

Three blind spots now recorded together in
`docs/plans/2026-08-03-effect-chain-followups.md`:

1. the shape leg does not check operands of **control-reachable** nodes
2. there is **no exit-code oracle** (`Mode1Runner.pm:167`)
3. GAP-declared cases **pass without executing**

Individually small; collectively they mean the gate's green number is weaker than it
looks in three independent ways.

## 10. The empty-audit chain

The characterisation audit that started this milestone reported its findings **in its
return message and never wrote the file**. I staged the path without checking it had
content, committed a **0-byte doc**, and cited it as the plan's source. Its unbacked
numbers propagated into v1 and I repeated them. Caught by `crochet:assess` trying to
check them and finding nothing to check.

Fixed: the doc now marks every claim **VERIFIED / ASSESSED / UNVERIFIED** by provenance.

**The deeper error:** I verified the *miscompile* myself and took the *payoff table* on
faith. **Verifying the dramatic claim and trusting the boring one is not a verification
discipline.**

## What to carry forward

1. **Consult `executable-gate.t` and `ring-worklist.t` before ranking any work**, and
   state the number the work moves. If it is zero, say so and justify on other grounds.
2. **Smoke-test every AC in both directions** before dispatch — one that should pass
   now, one that should fail now.
3. **Use `- [ ]` checkbox bullets** or the verification layer silently does nothing.
4. **Check a subagent's file actually has content** before staging it.
5. **Never flip issue state to test tooling.**
6. **A guess is not a cause.** Label it as a guess or leave the question open.
