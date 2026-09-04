# The scalar lattice contains M3, and that rules out MLsub — not inference

**Date:** 2026-09-04
**Status:** MEASURED against `TypeLibrary`'s own `join_types`/`meet_types`/
`is_subtype`. Reproduce: `scratchpad/m3.pl`.
**Producer pin:** perl5-son `b96087c`.

## The measurement

`Int`, `Undef` and `Boolean` are three pairwise-incomparable elements sitting
between `None` and `Scalar`:

    Int     vs Undef   : Int<:Undef=0   Undef<:Int=0     incomparable
    Int     vs Boolean : Int<:Boolean=0 Boolean<:Int=0   incomparable
    Undef   vs Boolean : Undef<:Bool=0  Boolean<:Undef=0 incomparable

    join(Int, Undef)     = Scalar    meet(Int, Undef)     = None
    join(Int, Boolean)   = Scalar    meet(Int, Boolean)   = None
    join(Undef, Boolean) = Scalar    meet(Undef, Boolean) = None

`{None, Int, Undef, Boolean, Scalar}` is **closed under both join and meet** —
a genuine sublattice, not an arbitrary subset — and it is non-distributive:

    Int ∧ (Undef ∨ Boolean) = Int ∧ Scalar = Int
    (Int ∧ Undef) ∨ (Int ∧ Boolean) = None ∨ None = None

6 violating triples in total. Three incomparable elements with common top and
common bottom, closed: that is **M3** by definition.

Note the threshold. Adjoining ⊤ and ⊥ to an antichain stays distributive for
ONE or TWO incomparable elements and fails at THREE. Chalk has exactly three,
so the "it's fine, it's just a diamond" intuition is wrong by one element here.

## What it rules out, and what it does not

**Rules out:** Dolan's MLsub construction as a target. *Algebraic Subtyping*
builds on a distributive lattice; M3 is the canonical counterexample.

**Does NOT rule out:** principal type inference. SimpleSub (Parreaux, ICFP
2020, Fig. 10) states that the extra subtyping rules giving distributivity
*"can be added to give desirable properties to the system ... but they are not
strictly required for principal type inference."* Distributivity is
load-bearing for MLsub's extensibility argument and its aggressive
simplification, not for principality as such.

**And MLsub is aimed at a harder problem than ours.** Dolan Ch. 10.1.1:
*"systems with structural subtyping have nontrivial subtyping relationships
only between base types, allowing `int ⩽ real` ... The advantage of structural
subtyping is that type inference is made much easier."* MLsub needs its
machinery because RECORDS force non-structural subtyping. Chalk's lattice has
no records. Worth noting MLsub's base types are mutually incomparable — it does
not even model `Int <: Num`.

So: retarget the reading from MLsub to the **structural/atomic** line —
Mitchell, Fuh & Mishra (compact principal types for exactly the
"inclusions between type constants only" setting), and:

**Rehof & Mogensen, "Tractable constraints in finite semilattices," SAS 1996**
— linear-time satisfiability for *definite* inequality constraints over a
finite meet-semilattice, and a MAXIMAL tractable class (any strict extension is
NP-hard). **Hoang & Mitchell, POPL 1995** is the bridge: for a fixed subtype
order, typability is polynomial-time equivalent to constraint satisfiability
over that order.

## Two cost warnings that outrank the tractability result

- **Entailment is coNP-complete even over a finite lattice** (Henglein & Rehof,
  LICS 1997). The lattice structure does not rescue it. Keep simplification on
  the satisfiability side.
- **Principal typings can be exponential in DAG size even when typability is
  PTIME** (Rehof): *"All known frameworks for atomic subtyping lead to worst
  case exponential dag-size of principal typings."* That is a fourth cost
  category — OUTPUT SIZE, not time — and it needs an explicit bound.

## The most transferable design rule

Pottier's hardest-won lesson: efficiency and readability are contradictory
goals, so keep readability simplifications **strictly external**, in a
display-only pass. Substituting a variable by its bound is *illegal during
inference* (it violates the mono-polarity invariant) but valid for display. His
measured outcome: ~400 lines/sec, within 2× of Caml-Light, with simplification
not the bottleneck.

## What the M3 actually signals for Chalk

Not an emergency — a modelling signal. It says `Undef` and `Boolean` are doing
something structurally different from the `Int <: Num <: Str` chain: they are
siblings hanging off `Scalar` rather than links in it.

That is the same question as *"does `Int` mean an i64, or an i64-or-undef?"*,
and Chalk has already answered it the right way (measured):

    Undef <: Int ?     no
    join(Int, Undef) = Scalar

`Int` means exactly `i64`. Absence lives in `Scalar`, which encodes as `%Slot`
— the tagged cell carrying a defined bit. The unpointed/pointed split that SPJ
and Julia both name as the PRECONDITION for legal unboxing is therefore already
structural here, and it is why `i64` is available as a default representation
for an unobserved `Num`.

## Corrections carried in from the research

Flagged so they are not re-derived: Tiuryn '92 is PSPACE-**hard** (completeness
needs Frey, SAS'97 / TCS 2002); Pottier's thesis is in **French** (defended
1998-07-03, advisor Rémy); ESOP'05 settles worst-case hardness and explicitly
does *not* restrict to lattices.

## What is NOT established

- Whether the M3 has ever caused a wrong answer. It is a structural property;
  no miscompile is attributed to it here.
- ~~Whether `meet_types` has any production caller.~~ **MEASURED, and the
  memory note is stale.** `[[t1_t2_split_and_bidirectional_inference]]` records
  ZERO callers for `meet_types` and `narrow_type`; `meet_types` now has FOUR
  production callers:

      lib/Chalk/IR/Analysis.pm:1333
      lib/Chalk/IR/Transform/BackwardInference.pm:125
      lib/Chalk/IR/Transform/BackwardInference.pm:147
      (plus the doc reference at BackwardInference.pm:31)

  `narrow_type` still has none outside its own definition. So the meet IS
  reachable and this is not design-space-only.

  **And the M3 shape is already anticipated at the reachable site.**
  `Analysis.pm` folds the node's own stamp into the meet expressly *"so a later
  round cannot move the stamp SIDEWAYS between two incomparable types and the
  loop need never settle"* — that antichain is `Int`/`Undef`/`Boolean`, this
  document's M3. A meet yielding `None` is treated as *"a real defect somewhere
  upstream, not something to paper over by picking one"*: the stamp is left
  alone and the backend GAPs on whatever consumes it.

  That is the right handling, and it is worth stating why: over a
  non-distributive lattice, meet is still monotone downward with `None` as
  bottom, so termination is safe. What M3 costs is not termination but the
  ability to REORDER meets and joins freely — which is exactly what MLsub's
  simplification would want to do.
- Fuh & Mishra full texts, Rehof POPL'97, and HM(X)'s arrow-variance axiom were
  paywalled; MATCH/SIMPLIFY descriptions are secondary.
