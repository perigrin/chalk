# The arm-scan predicates do not partition; they overlap

**Date:** 2026-08-13
**Status:** MEASURED. No fix proposed here — this is the evidence a design decision rests on.
**Method:** instrumented the four predicates in `perl5-son/lib/SoN/FromOptree.pm`,
ran perl's own `t/base`, `t/cmd` and `t/opbasic` through the producer, recorded
every call with the arm's op sequence. Instrumentation reverted afterwards.

## What the walker does today

Translating an `if/else` — or a statement modifier, which compiles to the same
`and`/`or` op in void context — the producer chooses a merge strategy by
SCANNING THE ARM'S OPS:

    _arm_has_void_call      a void print / void sub call?
    _arm_has_element_store  a store to an array/hash element?
    _arm_has_die            a die (aborts, never rejoins)?
    _arm_has_field_store    a store to an object field?

Any hit → build real control flow (If + Proj + Region + memory Phi).
No hit → merge the arms as a pure VALUE select, no control flow at all.

Four predicates, **15 call sites**, **4 distinct decision points**.

## Measured

866 predicate calls over **117 distinct arm shapes**:

| | |
|---|---|
| shapes scanned by MORE THAN ONE predicate | **101 of 117** |
| shapes scanned by ALL FOUR | **60** |
| arms carrying MORE THAN ONE effect kind | **44 of 117** |
| most-scanned single shape | 128 times |

## What that means

**The predicates do not partition the space.** They each walk the same arms
asking a different question; 60 shapes are walked four times over.

**The structural mistake is in the question, not the answers.** The code asks
"is this arm a void call OR an element store OR a die?" as though those were
alternatives. For 44 shapes they are SIMULTANEOUSLY TRUE, so the first predicate
to answer wins — and which one that is depends on call-site ordering, not on
anything about the arm.

**The arms are not small.** The most common shape is

    const,null,print,nextstate,pushmark,pushmark,const,gv,null,null,
    entersub,const,eq,cond_expr,const

That is an arbitrary statement sequence, not "an arm with an effect".

## Three bugs this month, all in the gaps BETWEEN predicates

1. **The bounds overrun** (perl5-son 77a0f32). Every predicate bounded its walk
   with `$$op != $stop`, and every one of the 11 call sites passed a B::OP
   OBJECT rather than an address, so the bound never fired and each scan ran to
   the end of the sub — reporting effects belonging to LATER statements.

2. **Terminating arms dropped** (perl5-son b0f3425). A single-branch `if` whose
   arm only `die`s or `exit`s matched no predicate in the void-branch gate, so
   no control flow was built, the terminator sat off the control chain, and the
   statement after the branch ran unconditionally. Measured: `exit 4 if $c`
   printed the following statement and exited 0 where perl exits 4.

3. **My nested-if miscompile** (reverted, uncommitted). Routing effect-bearing
   modifier bodies through control flow ALSO caught nested ifs, because a nested
   `if` inside an arm compiles to the SAME `and` op as a statement modifier and
   is indistinguishable at that point in the walk. Measured:
   `if ($c) { if ($d) { $a[0] = 9 } }` printed 1 where perl prints 9 — the store
   silently dropped. The untaken polarity passed, which is why a one-sided test
   would have missed it.

Each was a gap BETWEEN predicates, not a defect inside one. That is the
signature of a decomposition that does not fit the problem.

## The heuristic this trips

From CLAUDE.md, on the precedence semiring: *if implementing a rule needs more
than ~5 special-case sites, the rule is probably not the rule.* Four predicates,
fifteen call sites, four decision points, and three miscompiles in the seams.

## The question this poses

Not "what is the right discriminator" but **whether a translator should inspect
an arm's contents to choose a merge strategy at all**.

The alternative: build control flow UNCONDITIONALLY at every void-context
branch, and collapse effect-free diamonds into selects in a LATER pass that can
see the finished graph. That is how the question is posed to the prior-art
research (`deep-research`, 2026-08-13) — the load-bearing sub-question being
what such a collapse must CHECK to be sound (LLVM's
`isSafeToSpeculativelyExecute` is the concrete comparator).

## Reproducing

The instrumentation is not committed. To redo it: after each predicate's
`my %seen;`, log the arm's op walk keyed by predicate tag; write per-call rather
than in an END block, since `B::` compilation exits before END runs; place the
tracer INSIDE the class block or the call will not resolve.
