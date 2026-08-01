# Milestone coercion-slice-b Postmortem

**Date:** 2026-08-01
**Milestone:** `coercion-slice-b` (4 issues, all closed)
**Gate:** 153 -> 156 (behavior 156 / shape 156 / invariant 156, worklist 0, gap-declared 19)
**Commits:** `9365bc76`, `94451e45`, `fb364029`, `05b27379`, `bcbb8303`, `d8d16187`, `affd7129`

**Headline:** Slice B is **PARTIAL, not green.** C5 (an inlined callee's effects
stay in program order) is proven for the STRAIGHT-LINE PRINT shape only. The
loop+effect shape -- the slice's own title subject -- is PARKED, and the C4
shape-assertion was never built. The registry decision gate is NOT met. Full
record: `docs/plans/2026-07-23-slice-b-inliner-effect-ordering.md` "## OUTCOME".

## What Worked Well

**Pointing a reviewer at ONE named mechanism beat a generic sweep.** The
second review was scoped to a single question -- "is the `local $self->{cache}`
swap sound?" -- with the framing *construct a failing shape or state the
invariant that prevents it*. The reviewer empirically built the double-lower
shape (shared Concat = 2 mallocs / 4 memcpys; shared nested effectful call =
double-emitted print), then proved it gated closed by Call's per-call identity
plus the Print-only guard. That produced a load-bearing precondition now
recorded in-code. A broad "review this commit" would not have gone that deep.

**The review gate caught two things alignment missed.** Pass 1: Commit 1's
guard checked only `Return.control_in` and missed the `Return.inputs[1..]`
trailing-void-effect path -- a hole in the commit's OWN contract (convert the
silent drop to a loud GAP on BOTH paths). Pass 2 produced the double-lower
precondition above. Neither was an out-of-scope nitpick; both were in-charter.

**The mandatory self-verified gate held, three times.** The corpus gate was run
by the coordinator on committed HEAD after every issue, never accepted from a
subagent report. AC greps were hand-run rather than trusted to `git-zhi verify`
(the heading-case extraction gotcha). A subagent's factual claim (perl5-son
`344fc075` proving the inputs[1..] shape has no live producer) was independently
verified rather than taken from the code comment citing it. Fix *placement* was
also verified independently -- grepping `resolved_graph` to confirm
`_lower_call_direct` is the only foreign-graph inline entry and that both of its
paths funnel through the fixed function.

**Recording the partial outcome at BOTH sites.** The honest "PARTIAL GREEN"
record went into the slice doc *and* a STATUS block inline at the parent plan's
decision gate. A future reader hitting the gate from either direction cannot
mistake "milestone complete" for "gate satisfied." This is the direct
countermeasure to the project's documented 80-90%-declared-done failure mode.

## What Didn't Work

**I fixed one instance of a systemic pattern instead of sweeping for all of
them.** The slice's real technical content was: Chalk keeps several caches keyed
by node STRING id, while each graph numbers nodes from its own factory, so
cross-graph inlining collides. `_arg_bind` had already dodged this years ago by
keying on refaddr -- the precedent was sitting right there. Commit 2-print fixed
`{cache}`. Only when a reviewer named `_mut_read_memo` did the THIRD table
surface -- and it was REACHABLE, RED-proven as a genuine stale-value miscompile
(`Int:3` leaked vs `Int:2` correct). I should have grepped for sibling id-keyed
tables the moment I understood the root cause, not waited to be told.

**"Corpus green" masked a latent miscompile.** The `_mut_read_memo` fix moved
the gate 156 -> 156. A real miscompile existed that no corpus case exercised.
Gate-green is evidence about the cases in the corpus, never evidence of absence
for a cross-cutting hazard.

**Scope grew after the milestone was nominally done.** Three of four issues were
closed before the `_mut_read_memo` issue was even filed. It was filed as an
out-of-scope review finding, then promoted to must-fix-before-completion. That
was the right call, but it means the milestone's shape was not knowable at
refinement time.

## What Puzzles Us

**Why is the memo consulted only on a second lookup?** `_reads_mutable_location`
is reached only from `lower_value`'s cache-gated check, so an id is memoized
only when looked up twice -- the repro needed `Subtract(add, add)` to force it.
That is a subtle coupling between two caches, and it is not obvious whether the
narrow reachability is deliberate or incidental. If incidental, other id-keyed
state may be similarly half-exercised.

**How many more id-keyed tables are there?** Three found (`_arg_bind` by
precedent, `{cache}`, `_mut_read_memo`). `_str_len_table` was checked and is
safe (SSA-ref-keyed). No systematic inventory exists.

**Was the go/no-go budget actually tested?** Commit 2-print landed inside its
window, so the sanctioned PARK outcome was never exercised. We do not yet know
whether the budget discipline holds under a genuinely stuck slice.

## What Will We Change

1. **On finding a systemic bug, inventory the pattern before fixing the
   instance.** Concretely: grep for sibling state with the same keying before
   declaring a cross-graph isolation fix complete. Had this been done at
   Commit 2-print, `_mut_read_memo` would have landed in the same commit.

2. **Scope reviews to named mechanisms.** When a commit has one genuinely risky
   mechanism, point the reviewer at it by name and demand either a constructed
   failing shape or an explicitly stated invariant. This produced the highest
   value of any gate step in the milestone.

3. **Write the PARTIAL/PARKED outcome at the decision-gate site, not only at
   the work site.** Deferrals decay into drift when only the doing-doc records
   them. Every park now names where it is deferred TO and what gate it leaves
   unmet.

4. **Budget the parked loop-store slice as capstone-path work.** Conversation
   history surfaced that the bare-file protocol's unbudgeted INTER-GRAPH CALLS
   item is exactly "the inliner INLINES ONLY, SILENTLY DROPS effectful callee
   bodies" -- what Commits 1 and 2-print addressed. Real lib/ methods contain
   loops and stores, so `Commit 2-loop-store` sits on the path to lib/
   self-hosting (the North Star), not merely on the coercion registry's path.

5. **Tooling friction to route around** (all re-confirmed this milestone):
   `git zhi list --state X` returns 0 for every state and `list` hides done
   issues, so per-milestone counts silently under-report -- use `issue show`.
   `issue add` needs BOTH a title argument AND `--body`. `--state done` exceeds
   a 120s foreground timeout; background it. zsh heredocs break multi-line
   commit and doc bodies -- write to a file and use `-F` / `cat >>`. The JSON
   `acceptance_criteria` field is still not the verify set.
