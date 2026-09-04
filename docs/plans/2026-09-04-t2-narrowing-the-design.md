# T2 narrowing: constraints, solve, default

**Date:** 2026-09-04
**Status:** DESIGN, agreed in conversation with perigrin. Not built.
**Producer pin:** perl5-son `b96087c`. Gate at design time: 224.

Supersedes the arrow-map design in
`2026-09-04-t2-is-a-functor-objects-and-arrows.md` on the question of WHERE the
solving happens, and takes the corrected lattice facts from
`2026-09-04-the-lattice-is-non-distributive-m3.md`.

## The shape, in one sentence

T2 is a functor from the Chalk lattice to LLVM types where each object maps to
a **set** of candidates; observations at use sites narrow those sets by
intersection; whatever is still unconstrained gets a **default**.

## Which space the solving happens in

This was the question that took longest to get right (perigrin: *"LLVM doesn't
have a lattice though? So we're still constraint solving in the Chalk space?"*).

**Neither.** The solving happens in LLVM space, but over the **powerset**:

    {double, i64}        <- nothing observed yet
       |         |
    {double}   {i64}     <- an observation pinned it
       |         |
          {}             <- conflict: no type satisfies all constraints

Ordered by `⊆`. Meet is intersection. This is a lattice for any finite set,
ordered or not — LLVM's types needing no order of their own is exactly why the
powerset is the right carrier.

An observation is intersection, never a comparison:

    fdiv wants double:   {double, i64} ∩ {double} = {double}
    a conflict:          {double} ∩ {i64}         = {}

`{}` means unsatisfiable. That is not hypothetical: forcing `Num -> i64`
globally was measured and `my $x = 1.5` emitted *"floating point constant
invalid for type"* — LLVM rejecting an empty solution set.

**Chalk's lattice is upstream and does one job: it generates the candidates.**
The rule is already written at `Context.pm:4670` — *"a Chalk type may be
represented by the representation of ANY OF ITS SUBTYPES, or by its own"* — so
`Num`'s set is `{double}` ∪ Int's = `{double, i64}`. After that, Chalk's
ordering plays no part in the solve.

| space | ordering | job |
|---|---|---|
| Chalk types | `Int <: Num <: Str` | T1 infers; the stamp seeds the candidate set |
| candidate sets | `⊆` over LLVM types | T2 solves here |

## The order of operations, which is the thing to get right

1. **Collect** constraints from observation sites.
2. **Solve** — propagate to a fixpoint.
3. **Default** whatever is still unconstrained.

Defaulting is LAST. Defaulting first invents constraints that were never there
and then solves against its own guesses.

**That is precisely the current bug.** `%_REPR_LLVM_TYPE` maps `Num -> double`
before any constraint is seen: step 3 executed as step 0. It is why flipping
the table to `i64` did not help — it moved the premature default rather than
removing it, and it is why `my $n = 9007199254740993; my $s = $n + 0.0` prints
`9.00719925474099e+15` against perl's `9007199254740993` (pinned GAP,
`t/corpus/mdtest/arithmetic.md`, commit `b7486a7f`).

## Why defaulting is forced, not pragmatic

A `Num` with `{double, i64}` and nothing observing it has NO most-general
answer: `double` is not more general than `i64`, nor the reverse, and LLVM
needs a concrete machine type to emit code. There is no principal
representation, so something must choose arbitrarily — that is what defaulting
IS. GHC states the impossibility directly: you cannot have both representation
polymorphism and principal types. GHC defaults an unconstrained `RuntimeRep` to
`LiftedRep`; V8's `GetOutputInfoForPhi` defaults to `kTagged`.

## Scope of version one

**In:** the spine collapse. `Num` chooses between `{double, i64}`. Everything
else keeps the single candidate it has today.

**Out, deliberately** (perigrin: *"In the first version we prove it works …
promote on overflow can come when we need it"*):

- width and sign selection (`Int` stays `i64`)
- range/interval analysis
- promote-on-overflow
- float narrowing (`double -> float`)

The seam that keeps this honest already exists in `T2.pm`: *"`_candidates` asks
the stamp for its candidate SET and `_choose` picks from it. Adding intervals
later shrinks Int's set without changing the pass's shape."*

## Perl has no width semantics, and that matters for later

Measured, and it corrects an assumption made earlier in the design
conversation. `perl -V:use64bitint` is `define` — a BUILD FLAG, not a language
guarantee; perl has been built with 32-bit IVs. And overflow does not wrap:

    my $x = 9223372036854775807;   # B::IV
    $x++;                          # B::PVIV, value 9223372036854775808

The SV changes REPRESENTATION and the value stays correct. So perl's contract
is "a number is a number"; width is an implementation detail it switches at
runtime, observable only through `Config`.

Consequences for the eventual expansion:

- There is no wrapping-i64 semantics to preserve, so narrowing is *more*
  available than assumed, not less.
- But perl's model is narrow-and-promote, so a narrowed integer carries an
  OBLIGATION: **narrowing below the default is only legal with an overflow
  check attached** (LLVM gives this directly via `llvm.sadd.with.overflow`).
  Without the check it is the 2^53 bug again — a representation quietly losing
  information the type said it had.
- Floats are genuinely different: `double -> float` loses precision SILENTLY,
  with no overflow bit. Float candidates may narrow only on a PROOF, never on a
  check.
- The default is therefore not "perl's width" (there isn't one) but the widest
  supported, narrowed only where provable.

## Three fences to build in from the start

Cheap now, expensive to retrofit, and each one prevents a silent failure:

1. **A conflict is loud.** `{}` GAPs with the conflicting constraints named. It
   must never silently pick a survivor. With 2 candidates a conflict is
   obvious; with 12 (post-expansion) intersections stay non-empty much longer
   and a genuine disagreement could resolve to a plausible-looking type.
2. **Defaulting is a named rule with its reason recorded**, not an
   `array->[0]`. `_choose` today returns `$candidates->[0]` unconditionally,
   which is a default wearing the costume of a choice.
3. **`_candidates` is the ONLY place sets are constructed**, so the expansion
   is a one-site change.

## Termination

Two different arguments for two different passes, previously run together:

- **T1** terminates on lattice HEIGHT, measured at 6
  (`None < Int < Num < Str < Scalar < List < Unknown`). A monotone join moves
  upward only. **No widening operator** — on an ACC lattice the join already IS
  a widening. My earlier claim that loop Phis need widening was wrong for this
  pass.
- **T2** terminates on SET SIZE: candidate sets only shrink under
  intersection, and the largest is small.

Neither is threatened by the M3 non-distributivity: meet stays monotone
downward with `None` as bottom. What M3 costs is the freedom to REORDER meets
and joins, which is what MLsub-style simplification would want. It rules out
Dolan's construction, not inference.

Chalk starts at `None` (bottom) and joins upward — a LEAST fixpoint, so
stopping early under-approximates: less precise, still sound. Click's hazard is
the opposite (start at TOP, descend to a greatest fixpoint, unsound if stopped
early) and does not apply.

## The piece that does not exist

**Backward propagation.** An observation at a use site must reach the node that
PRODUCED the value — an `fdiv` three nodes downstream has to constrain its
operand's producer. HM calls the mechanism substitution composition
(`S₃S₂S₁`); Chalk has no equivalent, and it is the same gap the
backward-inference work recorded as "requirements must thread THROUGH Coerce".

This is the actual work item. Everything else above is bookkeeping around it.

## Prior art to model on rather than re-derive

- **V8 `SimplifiedLowering`** — the closest working analogue:
  backward PROPAGATE phase, a `Truncation` lattice, and
  `GetOutputInfoForPhi(Type, Truncation) -> MachineRepresentation` defaulting to
  `kTagged`. Type × what-the-uses-observe -> representation, with a default.
- **Bitwise (PLDI 2000)** — SSA, backward requirement propagation, one
  bidirectional fixpoint. Near-exact structural precedent.
- **Rehof & Mogensen (SAS 1996)** — linear-time satisfiability for definite
  inequality constraints over a finite meet-semilattice, and a MAXIMAL
  tractable class. Note: the semilattice here is the POWERSET under `⊆`, not
  the Chalk lattice — an earlier draft of this design said otherwise.
- **Pottier** — keep readability simplifications strictly EXTERNAL, in a
  display-only pass. Substituting a variable by its bound is illegal during
  inference, valid for display.
- **Leroy 1997** (his own follow-up to the 1992 unboxing paper) is a NEGATIVE
  result on type-directed unboxing, objecting that it is *"highly systematic:
  all data having the same type must have the same representation."* That is
  exactly the 2^53 miscompile, and it is an argument FOR per-node observation
  rather than a table.

## MEASURED BEFORE BUILDING: there are currently ZERO observations

The design above assumes observation sites exist to collect constraints FROM.
Measured across all 255 loadable corpus programs (`scratchpad/obs.pl`):

    Num-stamped nodes: 54
    with an observation that would pin them: 0 (0%)
    RESIDUE: 54 of 54

**Every `Num` node would fall through to the default.** The pass as designed
would be a defaulting pass with a constraint solver attached to nothing.

### Why

The intended constraint source is
`TypeLibrary::operand_repr_for_ir_op($ir_op, $position)`, which reads the same
signature tables the parser uses. Measured directly:

    Divide   pos 0/1 -> (no opinion)
    Add      pos 0/1 -> (no opinion)
    Multiply pos 0/1 -> (no opinion)
    NumCmp   pos 0/1 -> (no opinion)
    Concat   pos 0/1 -> Str

Only `Concat` answers. The table is gated on `%IR_OP_SOURCE_NAME`, which
contains `Length`, the string comparisons, and `Concat` — ops whose operand
types are FIXED BY THE OPERATOR — and deliberately excludes ops where the node
type does not determine the operand types (BitAnd/BitOr/BitXor, because numeric
`&` and string `&.` share a node; Print, because it is variadic over a List).

For most arithmetic that exclusion is CORRECT: perl's `+` is genuinely
polymorphic, `Int+Int` and `Num+Num` are both valid, and a table answering
"what must this operand be?" should decline.

### The exception, which is the whole ballgame

**`Divide` has a fixed answer and is missing anyway.** Perl's `/` is float
division as a matter of semantics (`3/4 == 0.75`), and the backend ALREADY
asserts this — `Context.pm:2073` dies unless the Divide's repr is float, with
the comment *"If Num were ever mapped to an integral type, this site must FAIL
rather than quietly pick `sdiv`"*.

So the strongest observation in the language exists as a BACKEND ASSERTION and
is absent from the table that is supposed to publish it. `Divide` is not in the
"DELIBERATELY ABSENT" list — it simply was never added.

### What this changes about the plan

The order of work inverts. Building the solver first would produce a pass that
provably does nothing, and a green test proving it.

1. **First, publish the observations.** `Divide` is the one with a fixed answer
   today. Whether others exist is the measurement to run — candidates are the
   float-comparison predicates and anything the backend currently asserts
   rather than derives.
2. **Then the solver**, against constraints that exist.
3. **Then defaulting**, for a residue that is genuinely a residue.

And the residue number becomes the acceptance signal: 54/54 today, and the pass
is only worth building when it is meaningfully lower. If publishing `Divide`'s
requirement moves it very little, the honest conclusion is that this corpus
rarely divides — which would say the 2^53 bug needs a different lever than
observation-driven narrowing.

## Open questions

- Whether "any of its subtypes' representations" generates the right candidate
  set in EVERY case, or whether some type needs a candidate outside its
  downward cone. Not verified.
- What the residue looks like in practice. If defaulting turns out to touch
  many nodes, the observation sites are too sparse — that is diagnostic, and
  worth measuring once the pass runs.
- Whether F22 (`polymorphic callee: one sub called with Int and with Str`,
  currently on the worklist) is fixed by this pass or needs the separate
  monomorphize-by-join-plus-coercion decision at sub boundaries.
