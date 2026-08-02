# Milestone son-ir-divorce Postmortem

**Date:** 2026-08-01
**Milestone:** `son-ir-divorce` (5 issues, 34/34 ACs passing)
**Cross-repo:** chalk `phase5-capstone` + perl5-son `pu`
**Corpus gate:** held at gate-green=156 / worklist=0 throughout, coordinator-run
on committed HEAD at every step
**Commits:** perl5-son `82e97cc`, `dc11e03`, `d838da6`, `83fbf0a`, `9a8f464`,
`6637402`; chalk `dd2eeb3c`, `cb386c1c`, `febbda45`, `83544223`, `fcdd6c93`,
`77001b8f`

**Headline:** the milestone bought **zero coverage** (0.00% → 0.00%, 47 own
units, 0 lowered) and was still worth doing, because the old measurement was
actively lying about where the work is.

## What Worked Well

**The double-assess pattern — which I almost skipped.** I ran `crochet:assess`
only. perigrin asked "did ponytail push back on this too?" It had not. Ponytail
then cut roughly 40% of the plan — the standalone contract doc and the
cross-repo conformance test with its checksum-pinned fixtures — as drift
insurance bought before any drift exists (measured drift: zero, 104 files
byte-identical). Its decisive argument was one I had missed entirely: **the
mechanical rename copies the walk-order comment blocks automatically**, so a
separate doc would be a third and fourth copy of prose that is not the
enforcement anyway. Assess validated the plan was TRUE; ponytail asked whether
it was the SMALLEST TRUE THING. Both artifacts survived the first lens and died
to the second.

**Falsifying the diagnosis before building on it.** Before committing to a
104-file rename, the plan's central claim was tested by copying `Graph.pm` with
only its class NAME changed: 4 methods became 7, and `_seed` appeared with a
Return. That 15-minute test is what turned "we think it's a collision" into
"the collision is the sole cause, and the fix is sufficient, not merely
necessary." The assessor then reproduced it independently, to the digit.

**Reading the diff, not just the ACs.** i1's subagent reported 7/7 ACs passing
and the clean-build suite green. A real regression sat in the diff anyway. It
surfaced only because I read the change and asked why a comment referenced a
deleted sub. On a deletion or replacement issue, AC coverage is bounded by test
coverage — and the paths worth deleting are frequently the untested ones.

**The completion gate re-running everything.** Per-issue green was not
sufficient. The milestone-completion pass found 5 regressions, then 2 more after
the first fix round. Every one was real, and every one was mine.

## What Didn't Work

**Five coordinator errors, none caught by tests.**

1. **An imprecise instruction reproduced faithfully.** I wrote "replace the
   `classes` branch with a loud die" from the plan without reading the branch.
   That branch does live field-type inference first, so every classful payload
   computed its inference, threw it away, and died — never reaching the
   universal repr-inference below. A capable agent executing a precise-sounding
   instruction reproduces the coordinator's imprecision exactly.
2. **My own tooling dance broke the DAG.** The `verify --dry-run`
   inspect-and-restore left an issue in `reopened`, which **hides it from
   `git zhi list` and drops its graph edges**. An `-auto` executor would have run
   RENAME before TRIM — corrupting the dangling references TRIM exists to
   prevent. Caught by the chain-review pushback lens, not by me.
3. **Cross-repo tooling confusion.** I told a subagent to run `git zhi issue
   show` while it worked in perl5-son. git-zhi is per-repo; the issue lives in
   chalk's store. Its recovery attempt (`git fetch origin refs/zhi/*`) deleted
   perl5-son's local zhi refs.
4. **Prose where a machine-readable line was required.** i4's AC greps a
   specific format; I wrote a narrative section instead. Accurate, unparseable.
5. **A wrapped sentence, and an ironic self-inflicted one.** I broke the contract
   sentence across two comment lines so the grep AC could not match it. Worse:
   while writing the note explaining that perl5-son must carry **no `Chalk::`
   reference**, I wrote two `Chalk::` references into perl5-son. The i2 carve-out
   existed to catch precisely that class of mistake in other people's edits.

**I half-fixed the point-in-time AC hazard.** Chain-review caught three ACs in
i1 asserting `lib/Chalk` paths that i2 renames away, and I made them
namespace-agnostic. I made the PATHS durable and never considered the COUNT: the
`%INC` guard expected 92 and became 91 after i2, because the `_all_nodes_topo`
copy dropped the producer's `use` of the vendored loader, removing it from
B::SoN's load graph entirely. Legitimate — arguably an improvement — but it
failed the milestone. I amended the AC **with a written justification in the
issue body**, because silently editing a number to match reality is how a gate
stops meaning anything.

## What Puzzles Us

**How long was the measurement lying?** The harness reported `_seed` as the top
blocker for 21 of 47 units. `_seed` was never a blocker — the class simply never
compiled. The harness's printed DIAGNOSIS paragraph (dated 2026-07-13) is stale
prose that its own stored `fails` array contradicts, and I repeated that prose as
a finding earlier the same day. How much other analysis rests on it?

**Why does the corpus gate not catch the mainline-`die` miscompile?**
GAP-declared cases are skipped before the triple-contract legs run, so T2c bumps
`gap-declared` rather than going RED. A silent miscompile that is *known* and
*documented* still reads as "not a failure" to the gate. That may be correct, or
it may be a hole worth closing.

**Is `_remove_trivial_phi` (15 units) actually the top target?** It is the
largest bar in the new histogram, but the blame is still shared-MOP poisoning —
a unit fails if any method the backend reaches GAPs. Fixing it may unblock 15
units, or may reveal the next layer.

## What Will We Change

1. **On a deletion or replacement issue, read the diff — always.** ACs are
   bounded by test coverage. Write the instruction against the *code*, not
   against the plan's summary of the code.
2. **Re-count issues after any git-zhi state churn.** `reopened` silently
   removes an issue from listings and drops its edges. `--state start` restores
   visibility; there is no transition back to `pending`.
3. **For cross-repo execution, pass the issue body as a FILE and forbid touching
   `refs/zhi/*`.** git-zhi is per-repo; a subagent querying the wrong store finds
   nothing and may "fix" it destructively.
4. **Anchor grep-based ACs on a short distinctive fragment**, never a full
   sentence — line wrapping silently defeats them.
5. **Run BOTH assessment lenses before refinement, every time.** Assess asks "is
   it true"; ponytail asks "is it the smallest true thing." This milestone's plan
   passed the first and lost 40% of its scope to the second.
6. **When amending an AC, write the justification into the issue body.** An
   amended number without a reason is indistinguishable from moving the
   goalposts.
7. **Ask, per issue: did the VERIFICATION land, or only the FIX?** (perigrin,
   post-milestone: "did we add tests for the regression specifically?" — we had
   not.) The i1 `classes`-branch regression was fixed and hand-verified with a
   one-liner, then left. But that regression existed BECAUSE no test drove
   `from_json` with a `classes` section; fixing it without adding a test left the
   identical hole open, so the next edit could re-break it and still go green.
   Closed by `t/from-json-classes-branch.t` (perl5-son `245f485`), proven
   RED→GREEN by reintroducing the exact `die` (3 failures back, all pass
   removed). **The test asserts the inference RAN, not merely that `from_json`
   lives** — a no-die check would pass even if the branch were skipped entirely,
   which is the failure mode being guarded. Audit of the other four issues found
   their verification genuinely present (i2 verified by construction — a
   half-renamed tree does not load; i3 is verification; i4 is recording; i5's
   corpus cases ARE the tests).

   Generalised: **"fixed" and "guarded against recurrence" are different states,
   and a fix discovered by reading a diff is by definition in a place tests do
   not reach.** That is exactly when the guard matters most.

## Postscript: the cheapest issue found the biggest bug

i5 (TryCatch/Unwind corpus cases) existed only as the consolation replacement
after the conformance test was cut. Adding case T2c surfaced a **real silent
miscompile**, independently reproduced: a mainline `die` lowers with NO GAP, and
lli exits 0 printing `Int:1` where perl aborts with exit 255. That is a
GAP-not-miscompile **invariant violation** — the class this project's entire
design discipline exists to prevent. Root cause: `process_control_node` ignores
`Unwind` on the control chain unless it is found via `_find_unwind_consumer` on
an If-arm `Proj`, so a `die` outside a branch arm is dropped. Filed as
`019fbf8d` in `tbase-drain`.

The elaborate machinery that got cut would not have found this. Two corpus cases
did.
