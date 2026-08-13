# Who owns a post-merge statement? The collection and emission walks disagree

**Date:** 2026-08-13
**Status:** BLOCKED. The producer half is built and correct (uncommitted, perl5-son);
the backend half is not, after four failed attempts. This doc is the measured
state so it is not re-derived.
**RED:** `perl5-son/t/from-optree-modifier-effect-in-arm.t` (uncommitted, passes
with the producer fix applied)
**Predecessor:** `docs/plans/2026-08-13-node-type-and-typelibrary-as-authority.md`
(this is that plan's step 5)

## What was being fixed

An effect-bearing statement modifier inside an if/else arm
(`die "..." unless C` in an else arm — t/base/term.t's blocker) GAPped:

    GAP: statement modifier with a void effect / element store / die
    inside an if/else arm not yet lowered

## The producer half: BUILT AND CORRECT (do not re-derive)

Two changes in `~/dev/perl5-son/lib/SoN/FromOptree.pm`:

1. **The refusal site (~:4355) now builds real control flow.** When the modifier
   body carries an effect, build `If` + `Proj` before the body walk and
   `$sim->merge($mod_sim, $factory, $if_node)` after — mirroring what the
   TOP-LEVEL `and`/`or` handler already does at :377-395 / :493-526. The
   value-only merge is kept for a pure rebind.

2. **The `_arm_has_*` scans now descend into nested branches.**
   `_arm_has_element_store` walked `->next` only; `_arm_has_void_call` and
   `_arm_has_die` explicitly `return 0` on a nested `and`/`or`/`cond_expr`. A
   nested branch hides its body on `->other`, so an effect behind one was
   INVISIBLE to the enclosing arm, which then built no control flow.

**MEASURED, NOT ASSUMED — the key finding that kills the obvious design:**
a nested `if` compiles to the SAME void `and` op as a statement modifier.
B::Concise on `if($c){ if($d){ $a[0]=9 } }` gives `and(other->h) vK/1` nested in
the outer `and`, byte-identical to `$a[0]=9 if $d`. There is NO flag
distinguishing them. "Detect the modifier and treat it specially" is therefore
IMPOSSIBLE. Both shapes need control flow — which is why the earlier reverted
attempt, which gave them the value merge, silently dropped the nested store.

Verified after the producer fix: graphs are structurally correct — two nested
`If`s, properly nested `Region`s (`Region#12(Proj#5, Region#10)`), a memory-Phi
chain (`Phi#13(MemStart, Phi#11)`), `Return` on the outer Region, and every
`head`/`region` pointer wired (checked directly, not inferred).

## The backend half: BLOCKED

### The bug, instrumented rather than guessed

`_collect_branch_body(Proj#6)` — the INNERMOST taken arm — returns:

    COLLECT proj=Proj#6 -> [Assign#7(Assign), Print#14(Print)]

`Print#14` is the post-merge `print $a[0]`; its `control_in` is `Region#12`, the
OUTER Region. It does not belong to that arm. It is swept in because
`_collect_body_recursive` (Context.pm:3719-3751) recurses through a statement
node's **data** consumers:

    Assign#7 -> Phi#10 -> Phi#13 -> Subscript -> Print#14

The existing `Region` stop (:3733, zhi 019f2df7) cannot catch this — the data
path reaches the Print through Phis and never touches a Region.

Consequence: the Print is emitted inside `if.then.4`. With `$d=0` control routes
`if.else.5 -> if.merge.6 -> if.merge.3 -> ret` and it never fires.

    perl:  "1\n" exit 0        chalk: "" exit 0

**The $d=1 polarity PASSES** — a 1-element array agrees with the untaken answer
by coincidence. Only the bilateral pair discriminates. This is the same
coincidence that let the earlier attempt look correct.

### Why it is not a one-line fix (four attempts, all measured)

Baseline behavioral score: **PASS=5 FAIL=6** (11 cases, both polarities of
nested-if / mod-print / mod-die / mod-elem, plus the pure-rebind partner).

| attempt | change | result |
|---|---|---|
| 1 | producer scans descend into `->other` | 6 -> 5 (traded failures; fixed the discriminating `d=1` case) |
| 2 | recurse only into consumers whose `control_in` is this node | **3** (malformed IR, exit=1) |
| 3 | revert to baseline, comment only | 5 (confirms baseline) |
| 4 | skip `Phi` consumers when recursing | **3** (collection now correct: `Proj#6 -> [Assign#7]`, but nothing emits the Print at all — malformed IR) |

Attempt 4 is the crux. Cutting the data edge correctly removes the Print from
the arm — and then NOTHING emits it. The outer control chain does not pick it
up. **The collection walk and the emission walk disagree about who owns a
post-merge statement, and fixing one side alone produces either a
double-placement or a no-placement.** That is a change to the
collection/emission contract, not a targeted patch.

### The registry connection (why this may be blocked on the registry work)

`_collect_body_recursive`'s own comment says:

    # Recurse into consumers that have this node as a control predecessor.

The code recurses into **every** consumer. The comment describes a CONTROL-edge
walk; the implementation is an ANY-edge walk. Nothing in the graph declares
which edges are control, so the discrepancy is invisible and survived review.

Meanwhile `_reads_mutable_location` (Context.pm:329) walks the same graph and
answers "stop or descend" from two op-name registries — `%MUTABLE_READ_OPS` and
`%PURE_DESCEND_OPS` — whose header states:

    # ... Phi/Constant/VarDecl/ArrayRef/HashRef likewise produce a fixed SSA
    # value at a single program point.

So one walk STOPS at Phi on the premise that a Phi is a fixed value at a single
program point, and the other walks THROUGH Phi and thereby leaves the arm. Two
traversals of one graph, holding contradictory beliefs about what a Phi is,
each encoding the belief as a hand-maintained op-name list rather than asking
the node.

This is the predecessor plan's thesis landing on a live bug: the question
"is this edge control or data?" is a property of the edge/type, and it is
currently answered by three different mechanisms that do not agree. **Deciding
the Phi-tracing rule before that is settled risks encoding a fourth.**

Note the honest limit: this is a MOTIVATION, not a proven dependency. It is
possible to fix the ownership contract without touching the registries. But the
four failed attempts were all attempts to patch one walk without a shared
definition of a control edge, and that is exactly the failure mode the registry
work exists to remove.

## Corrections to earlier claims in this session

- I said "the backend can't lower nested Regions." **FALSE.** `t3.pl`
  (`if($c){ if($d){ print "in" } } print "after"`) lowers correctly and PASSES —
  `print "in"` in `if.then.4`, `print "after"` in `if.merge.3`. The
  discriminator is a post-merge AGGREGATE READ whose multi-block expansion
  (bounds check + Stringify loop) opens continuation blocks, not nesting.
- I reasoned for several steps from a behavioral run taken BEFORE the scan fix
  and concluded a case still failed when it had started passing. Re-measure
  after every change; do not carry a score forward.

## Next step, when picked up

1. Decide the ownership contract explicitly: for a statement whose `control_in`
   is a Region, WHICH walk emits it — the arm collection (never) or the outer
   control chain (always)? Write that as a testable invariant before editing.
2. Then make `_collect_body_recursive` follow control edges only, and make the
   outer chain pick up what it drops. Both halves in one commit; attempt 4
   proves either alone is broken.
3. Re-run the 11-case bilateral behavioral suite
   (`scratchpad/behav.pl`, uses the shared `ProgramRunner` so stdout, exit
   status AND TypedInvariant all count). Baseline to beat: PASS=5.
4. Then the corpus gate, all four legs, self-verified on committed HEAD.

## State

- chalk: CLEAN at `b8f3c507`. Gate `gate-green=194 behavior=194 shape=194
  invariant=194 worklist=0`. No backend changes survive.
- perl5-son: `lib/SoN/FromOptree.pm` modified + `t/from-optree-modifier-effect-in-arm.t`
  untracked, both UNCOMMITTED. Correct work, but **must not land alone**: on its
  own it converts a loud GAP into a silent miscompile, which is the
  GAP-not-miscompile invariant. Park on a branch, not `pu`.
