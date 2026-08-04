# Postmortem: effect-chain-fix

**Completed:** 2026-08-03/04 · 8/8 issues · 26/26 unique ACs passing (coordinator-run)
**Plan:** `docs/plans/2026-08-03-effect-architecture-subtraction.md` (v3)
**Rejected predecessor:** `docs/plans/2026-08-02-effect-world-token-design.md` (DEFERRED)
**Repos:** chalk `phase5-capstone`, perl5-son `pu`

## Outcome

| | before | after |
|---|---|---|
| F1 mainline die | drops every preceding effect | exact vs perl |
| F2 die-after-effect-in-arm | wrong stdout **and** exit 0 | exact vs perl |
| F3 inlined effect | reordered | ordered |
| F4 inlined effect | dropped, no GAP | present |
| corpus gate | 156 | 157, worklist 0 |
| **executable gate** | **0/5** | **1/5** |
| control/effect assertions | **none anywhere** | leg on all 157 cases |

`die-aborts` is the first program in this project's history to compile *as itself*
and match perl on stdout **and** exit status.

## 1. The headline is the review arc, not the fix

The first design was a **world token**: effect ordering as a typed graph edge, world
arity a property of node class, correctness-by-construction. Two independent reviews
killed it **from opposite directions**, and that convergence is what made the verdict
decisive rather than arguable.

- **PAAD — unsound.** Sibling branch arms share an incoming world (the design left
  `If`/`Proj` non-world-carrying), so two identical `Print`s hash-cons to one node.
  Corpus case D1e (`control-flow.md:218`) is exactly that shape and is gate-green
  today. Retiring `%STATEMENT_EFFECT_OPS` on the strength of the world input would
  have **reintroduced the miscompile that table was written for** (019eb6ff item 1).
- **Ponytail — unnecessary.** All four bugs close in ~20 lines. The token closes
  **one of four**.

**The finding that gutted the justification: arity is not ordering.**
`Print(w0)→w1; Unwind(w0)` has perfect world arity and *is* the F1 miscompile. The
validator the design proposed could not see the bug the design existed to prevent. If
the edge made the bad state unrepresentable, the validator would be redundant — it
wasn't, which proves the edge didn't.

**Process lesson:** the two lenses ask different questions — *is it true?* and *is it
the smallest true thing?* — and neither substitutes for the other. Running both, on
both revisions, cost four review rounds and prevented a two-repo migration across
~300 sites that would have closed one of four bugs and reintroduced a fifth.

## 2. A plan titled "subtraction" that was net line-positive

v2 claimed 6 mechanisms → 4. Counted honestly it deleted M6 in full plus **one of
three** M5 sites, left M1 intact and *extended* it, and **added** a table to the M3
family — the invariant itself. ~36 lines deleted against >100 added.

A fresh ponytail caught it. The retitle mattered: a doc titled "subtraction" that is
net-additive is exactly how the cut steps walk back in later under a title that
already promised them.

## 3. Four AC-format defects, every one a silent vacuous pass

| # | Defect | Effect | Caught by |
|---|---|---|---|
| a | **`ag` has no `-q` flag** — errors rc=1 regardless of content | 6 positive ACs could never pass; 8 `! ag -q` guards passed **vacuously** | chain-review |
| b | corpus gate prints **double** spaces (`gate-green=156  behavior=156`); pattern used single | every issue's primary AC could never match — milestone uncompletable | **me, smoke-testing** |
| c,d | two doc ACs grepped lowercase against prose written in caps | silent fail at completion | the manual AC re-run |

(a) is the sharpest: the global instruction says *use `ag` not `rg`*, and `-q` was
written as if it were grep. The flag does not exist.

**The generalizable rule: an AC must be tested for DISCRIMINATION in both
directions** — one that should pass *now* and one that should fail *now*. Testing only
that it parses is how (b) survived until a pass-case unexpectedly failed.

## 4. The floor-pinning hazard is structural

i4 adds a green corpus case → floor 156 → 157 → **every AC pinned at exactly 156
breaks at milestone completion, including i4's own**, because git-zhi re-runs every
issue's ACs at the end. Chain-review flagged it BLOCKING.

**Fix that generalizes:** assert the legs *agree* via a backreference —
`gate-green=([0-9]+) +behavior=\1 +shape=\1 +invariant=\1` — and let the test file's
own `cmp_ok` carry the floor. Never hardcode a count that later work legitimately
changes.

## 5. Parallel dispatch contaminated a verification; a subagent misdiagnosed it

`son-corpus-wide.t:17` resolves the producer as a **live filesystem path** with no
version pin, so "chalk first" is a wall-clock fact, not a repo-state property.
Chain-review warned about this (finding I6). I applied the caution to i7/i8 and then
dispatched i1/i2 in parallel anyway.

i1's agent reported *"gate-green=155, pre-existing B::SoN race in test 56 (T2 die
inside a branch arm)"* — test 56 being precisely the code path i2 was mid-rewrite on.
Its control experiment was invalid: it stashed in **chalk**, which does nothing to the
**producer's** uncommitted state. Two clean consecutive runs after i2 committed proved
the gate is **not** flaky.

Had that report been accepted, "the gate is flaky" enters the record permanently and
every future 155 gets waved off as the known flake. That is how a real regression
hides.

## 6. My own scratch tool lied twice

`probe.pl` reported `Int:2` where the authoritative corpus gate reported `Int:3` for
the same program, and separately showed an effect **present** pre-i4 that was provably
dropped. I chased a suspected return-value regression through a baseline producer
worktree before resolving it against the gate.

In the same investigation I claimed the new corpus case had a **truncated source** —
that was my own `grep` dropping a bare-digit line, not a real defect.

Two rules: **verify against the authority before reporting**, and **re-read the raw
artifact before claiming it is malformed.**

## 7. A guard on one side of a boundary does not close a class

`2026-07-23-slice-b-inliner-effect-ordering.md:259` claimed the silent effect-drop
miscompile class was CLOSED. Commit 1's guard inspected only the **callee's**
attachment paths. F4 is a live **caller-side** drop with no GAP possible, because the
producer DCE'd the unpinned Call before chalk ever saw it.

Re-scoped in place, not deleted. **"CLOSED" in a plan must name the side it closes**,
or it will be read as the whole thing — including by whoever wrote it.

## 8. What the new check actually buys, stated honestly

The TypedInvariant control-chain leg would have caught **one** of the four bugs (F1).
It cannot catch F4 (the whole `Call` node was missing — nothing to flag) nor F2 (a
backend-scan bug, not a graph property at all). The other three needed the unit tests
that landed with their fixes.

That limit is written at the check site. A check whose scope is overstated is worse
than none.

## 9. Execution-surfaced findings not in the plan

- **`Assign` is pinned at 8 of 9 producer build sites.** The generic list-assign
  fallback (`my ($a,$b) = LIST`, `FromOptree.pm:2067`) is unpinned. No corpus case
  exercises it, so the leg is green — but "Assign is always pinned" holds only for
  corpus-exercised shapes.
- **i2's fix required two files beyond its authorized scope** (`Render/Text.pm`,
  `Serialize/JSON.pm`): passing args as a real arrayref made `Unwind.inputs[0]` a
  shape generic `inputs->@*` walkers had never seen. Found by **running the clean
  build**, not by guessing — and one of them was a topo-order bug that let a Constant
  serialize *after* the Unwind referencing it.

## 10. Process friction

- **`git zhi verify <milestone>` extracted ZERO commands** despite 8/8 done, correct
  headings, and 8 issues linked. Likely cause: the milestone **object** was created
  *after* issues were tagged with its name — `issue add --milestone` silently accepts
  a nonexistent milestone, and `verify` then loads an empty one. Undiagnosed. Ran the
  39 ACs by hand instead. **Create the milestone object first.**
- **`--state done` needs `--force`** when the issue was started *after* its commit
  landed (0-commit window). **Start the issue before dispatching.**
- **The 8-char ID display truncates**: all eight issues rendered identically as
  `019fc8e1`. Long refs are mandatory.

## Still open (filed in `2026-08-03-effect-chain-followups.md`)

1. **Shape leg does not check operands of control-reachable nodes** — a wrong `If`
   condition and a wrong branch-arm store both PASS. Prerequisite for the cut
   `If`/`Loop` normalization.
2. **No exit-code oracle** (`Mode1Runner.pm:167`) — why F1 was invisible and why the
   die-in-arm corpus case can only be a marker. Adding it is small but **not free**.
3. **Unpinned list-assign path** (producer).
4. **Two remaining M5 sites**, one inside a fenced sub.
5. **The world token** — DEFERRED, revival trigger is **GCM design**
   (`chalk-parse-perl-plan.md:763`, Phase 9). Fire it when GCM is *designed*, not when
   it ships: retrofitting an IR under a working optimizer is strictly worse than
   building the optimizer on the right IR.
