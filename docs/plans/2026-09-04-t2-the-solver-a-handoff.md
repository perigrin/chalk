# T2: the solver. A handoff.

**Date:** 2026-09-04
**Status:** DESIGN DRAFT. Nothing in `lib/` changed to produce it.
**Audience:** a fresh session picking this up.
**Supersedes the build order of:** `2026-09-04-t2-narrowing-the-design.md`
(correct about constraints, wrong about where they attach) and one of the three
open questions in `2026-09-04-t2-is-a-functor-objects-and-arrows.md`, which is
now answered by measurement -- see THE ATTRIBUTION IS SETTLED.

## Read this first: what is true right now

- **The corpus gate reads 223** against producer `b96087c`, four residual
  worklist entries. Same figure as commit `175a18dd`. **Chalk has not
  regressed.**
- **`lib/` is untouched** by the session that wrote this document.
- **The pinned producer is a git worktree now**, not a copied directory:
  `scratchpad/son-pin-b96087c` -> detached at `b96087c`. It was previously a
  plain directory, it got deleted, and the gate then answered `1..0 # SKIP`
  with **exit code 0** -- a vacuous pass. If it goes missing again, recreate
  it with `git worktree add --detach <path> b96087c` from `~/dev/perl5-son`.
- **The live producer has moved 54 commits ahead** to `8085f51` and introduces
  a node op `EntryWrite` that Chalk's loader does not know. Against live the
  gate reads 205 and the worklist jumps 4 -> 22, with 15 entries failing
  identically at `from_json: Unknown data node operation: EntryWrite`. That is
  a producer/consumer contract gap, INDEPENDENT of T2, and it is why the gate
  must stay pinned until the loader learns the op.

### A measurement discipline note, because it cost this session real time

Do not treat "all four legs show the same number" as an invariant. It is not
one. `gate-green` is the CONJUNCTION of behavior/shape/invariant, so it is
always <= each of them; 223/225/224/226 is the healthy shape. The AC pattern
`gate-green=N +behavior=N +shape=N +invariant=N` from earlier milestone work
was a POINT-IN-TIME coincidence, not a law. Reading the spread as damage sent
this session chasing a regression that did not exist.

The real signal in a bad run is the MAGNITUDE of the spread plus the worklist
count moving.

## THE ATTRIBUTION IS SETTLED: it is the OBJECT map

`2026-09-04-t2-is-a-functor-objects-and-arrows.md` lists as unresolved
"whether kind (2) -- the `Num |-> double` precision failure -- is fixed by the
arrow map or by the OBJECT map". **It is the object map, and the evidence is a
control experiment already in the tree**, added by `6a174bad` after that doc
was written.

`t/bootstrap/ir/coercion-composition-law.t:179-183`:

> With Scalar enumerated: `Int->Str->Scalar` 7/7 AGREE, `Num->Str->Scalar` 3/3
> AGREE, `Int->Num->Scalar` 5 AGREE + 2 DIFFER (the 2^53 pair). ZERO upcast
> compositions that avoid Num differ, on any probe. That isolates kind (2) to
> the OBJECT map choice `Num |-> double` rather than to the arrow map.

Every route avoiding `Num` composes. Only routes through `Num` break. The
arrow map is exonerated BY MEASUREMENT, not by argument.

Consequence: **do not fix the 2^53 case by adding a coercion at the mixed
`Add`.** That is a 20th hand-written arrow site, and the existing ones (26
`_emit_coercion` references in `Target/LLVM/Context.pm`) are already recorded
as debt for being N independent decisions. This session proposed that fix and
it was wrong.

## Why `_choose` is the wrong hook

`_choose` (`T2.pm:325`) is called from `_narrow_node` (`:173`), which is called
from `run`'s single unordered pass over `->nodes` (`:127-130`). Wiring
`narrow_num` into `_choose` fails for three independent reasons:

**1. It commits during traversal, destroying its own input domain.**
`_narrow_node` calls `set_stamp` at `:173` as it walks. `narrow_num`'s
constraint source (c) reads `$v->stamp eq 'Int'` on its operands (`:275`).
Once an operand has been narrowed its stamp says `i64`, not `Int` -- so source
(c) fires or does not fire DEPENDING ON VISIT ORDER. The pass consumes the
source vocabulary it is written against.

**2. It can only look down.** `narrow_num` reads `$node->inputs` (`:266`,
`:275`) and nothing else. There is no `consumers` access anywhere in `T2.pm`.
Constraint source (a) -- "a consumer states a requirement" -- has no route to
travel. That is the backward-propagation gap
`2026-09-04-t2-narrowing-the-design.md` calls "the piece that does not exist",
still open.

**3. It decides per node in isolation.** Two nodes joined by an edge can get
incompatible answers with nothing positioned to notice. That is exactly
`Add(i64, double)`.

So `narrow_num` is not a solver. It is the decision procedure for ONE
unification variable once its constraints are known -- phase 3 of 4, and the
only phase built.

## The functor is underspecified, and this is the sharper form

The arrow map as designed maps the five SOURCE-category arrows (the subtype
edges in `%PARENT`). That is not sufficient, because the arrows that actually
break have **no source-category preimage**.

Measured, the 2^53 graph as the producer emits it:

    %3 = Constant(9007199254740993) [Int]
    %4 = Coerce(%3)                 [Num]
    %5 = Constant(0)                [Num]     <- this is `0.0`
    %6 = Add(%4, %5)                [Num]

`%4` and `%5` are BOTH `Num`. The subtype arrow between them is the identity;
there is nothing in `%PARENT` to map. Yet their images diverge -- `%4` has an
all-Int input so it wants `i64`, `%5` is a float literal so it wants `double`.
The functor is well-defined on the type poset and still admits this.

**The missing law is not `F(g.f) = F(g).F(f)`.** It is that `F` must be a
functor on the GRAPH, not merely on the type poset: every IR edge is a
morphism obligation, and `F` owes each one either an identity or a conversion.
The five subtype edges are a SUBSET of the obligations, not the whole set.

This is why "wire `_choose` to `narrow_num`" reproduces the failure at a new
address -- it is still the object map answering in isolation.

## The shape: four phases, currently collapsed into one

1. **GENERATE.** Walk every edge; emit constraints. Mutate nothing.
2. **SOLVE.** Fixpoint over the POWERSET of candidates ordered by inclusion,
   meet = intersection. Terminates on finite height -- each variable's set only
   shrinks, and `%CANDIDATES` sets have at most 4 members.
3. **DEFAULT.** Variables still free take `_default_num_repr`. Forced, not
   chosen: `double` and `i64` are incomparable, the emitter needs a concrete
   type, so something must pick. GHC states the impossibility directly -- you
   cannot have both representation polymorphism and principal types.
4. **SUBSTITUTE.** Only now `set_stamp`, all at once.

Phase 4 going last is what fixes defect (1). Phase 1 over EDGES is what fixes
(2) and (3). `narrow_num`'s three sources survive as constraint GENERATORS,
not as a decision procedure called mid-walk.

**Use-def is already bidirectional and needs no new infrastructure:**
`Chalk::IR::Node.pm:47` declares `field $consumers :reader = []`, populated by
`NodeFactory::_register_consumers` (`:189`). Backward edges are available
today.

## TWO QUESTIONS TO SETTLE BEFORE WRITING CODE

Both are cheap to get wrong and expensive to unwind. This is the actual
handoff.

### Q1. What is a constraint, and what does an unsatisfiable one MEAN?

Is a constraint a required repr per NODE, or an agreement per EDGE?

The forcing case: a fractional literal feeding an otherwise all-Int `Add`.
Intersection is empty. Two readings, and they lead to different compilers:

- **Empty means insert a conversion.** The arrow map is consulted DURING
  solving; an unsatisfiable edge is discharged as a `sitofp` and solving
  continues. Matches what perl does.
- **Empty means GAP.** The arrow map is consulted AFTER; an unsatisfiable edge
  is a program T2 refuses. Safer, smaller, and probably wrong for real Perl.

This decides whether the arrow map is part of the solver or downstream of it.
**It is the load-bearing question in this document.**

### Q2. Can the corpus express the image at all?

The `ir` blocks assert SOURCE-category facts (`:Int`, `:Scalar`). Rewriting
stamps in place destroys the domain they are written against -- measured, not
hypothetical: wiring T2 in took the gate **224 -> 0, with the shape leg at 0 in
every section**.

`ir-t2` is named in both prior docs and **does not exist** (grep: four
mentions, all in docs). Until the harness accepts a second vocabulary a solver
lands unverifiable by the gate -- the same shape as F2 nearly shipping
unexercised.

**Recommendation: build `ir-t2` support in the harness BEFORE the solver.** It
is the difference between a pass that can be shown correct and one that cannot.

## Suggested build order

1. Settle Q1 with perigrin. Do not guess.
2. `ir-t2` blocks in `MdtestCorpus.pm` + `son-corpus-wide.t`. A handful of
   cases carrying both vocabularies. Gate must still read 223.
3. Phase 1 alone: generate constraints, mutate NOTHING, assert the collected
   set on the 2^53 graph. This is where `narrow_num`'s three sources move.
4. Phases 2-4 behind a flag, off by default. Compare against 223.
5. Only then retire `%_REPR_LLVM_TYPE`'s premature substitution.

## What the session that wrote this got wrong, and how it was caught

Recorded because each error is REACHABLE FROM THE ARTIFACTS a fresh session
will read. These are not confessions; they are traps still sitting in the tree.

### 1. Proposed adding a Coerce at the mixed `Add`

Having measured `Add(%4:i64, %5:double)`, this session concluded "blocker (1)
is a missing coercion, not a propagation gap" and was about to insert a
conversion node at the merge point.

That is a 20th hand-written arrow site, in a codebase where the existing ones
are already recorded as debt for being N independent decisions. **The reasoning
error was reasoning in the SOURCE category**: "narrow the wider operand and
convert at the point of use" is a subtype-lattice argument, and `i64`/`double`
have no order for it to run on. There is no "narrower operand" to promote.

Caught by perigrin naming the frame -- T2 is a functor guided by a constraint
solver, not by the subtype lattice.

### 2. Treated a stale doc as authoritative

`2026-09-04-t2-is-a-functor-objects-and-arrows.md` lists the 2^53 attribution
as unresolved. This session read that, concluded the question was open, and
stopped -- when `6a174bad` had ALREADY ANSWERED IT by adding `Scalar` to the
composition enumeration.

**The doc is older than the measurement that settles its own open question.**
A fresh session reading it will hit the same trap. That is why THE ATTRIBUTION
IS SETTLED is placed near the top of this document.

Caught by grepping the composition test instead of trusting the prose.

### 3. Invented an invariant and read a healthy gate as damage

This session twice called the leg spread 205/207/208/210 evidence of a
problem, citing "last session all four agreed at 223". They did not.
`gate-green` is the conjunction of the other three, so it is always <= each of
them, and a spread is the NORMAL shape.

The `gate-green=N +behavior=N +shape=N +invariant=N` AC pattern in the
milestone history is a point-in-time coincidence that this session promoted
into a law. Cost: a regression hunt for a regression that did not exist.

Caught by running the gate against the restored pin and seeing 223/225/224/226
-- a spread, on a run that is unambiguously healthy.

### 4. Accepted an exit code instead of reading output

The first gate run of the session reported `exit code 0` and was very nearly
taken as a pass. It had printed `1..0 # SKIP perl5-son not found`. A skipped
file exits 0.

Same family as the recorded `grep -c "^not ok"` reading 0 for a file that
DIES. Caught only by reading the tail of the output.

### The pattern across all four

Three of the four are the same error in different clothes: **an artifact was
read as authority when it was only evidence** -- a stale doc, a historical AC,
an exit code. The one that is not (the Coerce proposal) is the mirror image:
reasoning confidently in a category whose structure the target does not have.

The defence in both directions is the same and it is cheap: MEASURE THE CASE
THAT LOOKS DIFFERENT IF YOU ARE WRONG. The composition test's `Scalar` control
is exactly that, and it is why the attribution above is settled rather than
argued.

## Do not repeat these

- **Do not add a coercion at the mixed `Add`.** 20th arrow site; the
  attribution above says the object map is the defect.
- **Do not flip `Num |-> i64` wholesale.** Measured: the composition table
  collapses 224 -> 53 rows, because `my $x = 1.5` then emits `floating point
  constant invalid for type`. Same mistake with the other value.
- **Do not trust a gate run's exit code.** Read the output. `1..0 # SKIP`
  exits 0.
- **Do not run the gate unpinned** while the loader lacks `EntryWrite`.

## Open, and NOT addressed here

- `EntryWrite` in the loader (15 cases, independent of T2).
- Whether `Str -> Scalar` and `Undef -> Scalar` are one arrow or two sharing an
  implementation.
- F18 (sort comparator), F22 (polymorphic callee) -- the other two residual
  worklist entries. F22 may be a T2 boundary question or may need
  monomorphize-by-join at sub boundaries; unsettled.

## Provenance of every claim above

VERIFIED (command run or file read this session): the 223 and 205 gate
readings and their leg splits; `producer=b96087c` / `8085f51` in
`paad/worklist.json`; the 15 identical `EntryWrite` failures; `EntryWrite`
introduced by `a6a09a1` and absent from Chalk `lib/`+`t/`; the `1..0 # SKIP`
exit-0 behaviour; `Node.pm:47` `field $consumers :reader`; the four `ir-t2`
doc mentions and zero code; the 2^53 graph shape from the live producer; the
composition-law control experiment at `coercion-composition-law.t:179-183`;
all `T2.pm` line numbers cited.

ASSESSED (argument from the above, not independently measured): that phase 4
ordering fixes defect (1); that edge-level generation fixes (2) and (3); the
recommendation to build `ir-t2` first.

Also VERIFIED, for the four errors recorded above: the `1..0 # SKIP` run and
its exit code 0; the 205/207/208/210 and 223/225/224/226 leg splits; that
`6a174bad` postdates the functor doc and adds the `Scalar` enumeration that
settles its open question. The characterisation of WHY each error happened is
ASSESSED -- it is this session's reading of its own reasoning, not a
measurement.

UNVERIFIED: the 224 -> 53 composition collapse and the 224 -> 0 gate figure
are quoted from prior docs, not re-run here.
