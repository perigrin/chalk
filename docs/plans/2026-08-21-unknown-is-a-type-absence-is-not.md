# `Unknown` is a type. An absent `representation` is not.

**Date:** 2026-08-21
**Status:** MEASURED, not fixed. Raised by perigrin while scoping step 5.
**Corrects:** my own prose in `2026-08-21-step5-the-inliner-miscompiles-today.md`,
which wrote `repr=UNDEF` and "typed UNDEF" as though that were a type.

## Three things, and the code conflates two

| | meaning |
|---|---|
| `Undef` | a REAL type: the value `undef`. A legitimate inference answer. |
| `Unknown` | SOUND TOP: inference failed. Nothing may be done until narrowed. |
| Perl `undef` in `representation` | the field was never written. Not a type at all. |

`Undef` and `Unknown` are already separated correctly in `TypeLibrary`
(`:86-106`), and the comment there states the distinction exactly -- it is
TypeScript's `unknown` vs `any`:

> `Any` opts OUT of checking. A legitimate static answer.
> `Unknown` is SOUND top: inference has not determined the type, and nothing may
> be done with the value until it is NARROWED.
> ... an `Any` reaching the backend is a design fact, an `Unknown` reaching it is
> an inference failure.

It also records that this lesson was already learned once: `Scalar` used to
double as the "I do not know" placeholder, so the backend's Scalar GAP could not
tell "this scalar type is not lowered yet" from "nothing ever typed this".

## The measurement

    nodes ever STAMPED Unknown:              0
    sites hand-checking for a missing repr:  24
      (12 in IR/Serialize/JSON.pm, 12 in Target/LLVM/Context.pm)

**The type exists and nothing produces it.** Instead an unstamped node carries
Perl `undef` -- an ABSENCE -- and two dozen consumers each re-derive "no answer"
from it with `defined $node->representation` or `// `.

That is the failure shape this session has hit repeatedly: an absence standing
in for a decision, so the failure mode is silence rather than a refusal. Same
class as the defaulted `sigil`, the vacuous `exists` assertion, and the 0-file
`find`.

## Why it matters for the recursion cycle

`_join_repr` bails on `fib` because it is handed a Perl `undef`, which is not a
lattice point and cannot be joined over. Measured on `main::fib`'s Return:

    TernaryExpr  (unstamped)
      arm NumLt  Bool
      arm Call   Int          <- base case, typed from the argument
      arm Add    (unstamped)  <- recursive arm

If the recursive `Call` were stamped `Unknown` rather than left unstamped, the
join would have a real top to work with -- and `is_subtype` is true in both
directions between `Unknown` and `Any`, so joining `Int` with `Unknown` has a
defined answer instead of a bail.

So "the fixpoint bails early" and "we use absence where we mean `Unknown`" are
the same defect seen from two ends.

## What this does NOT establish

- The size of the change is not measured. 24 hand-check sites is the count of
  places that would eventually read `Unknown` instead of testing definedness;
  it is not a claim that all 24 must change at once, nor that stamping
  `Unknown` is sufficient to close the recursion cycle.
- Whether the backend should GAP on `Unknown` (an inference failure reaching
  codegen) or whether some consumer can narrow it is undecided.
- No claim that `Undef` is used wrongly anywhere. The measured problem is the
  ABSENT case, not a confusion between `Undef` and `Unknown` in stamped values.

## Filed, not fixed

Independent of step 5's call emission. Worth doing before or alongside the
recursion work, since the recursion cycle is the first place the distinction
becomes load-bearing rather than hygienic.

---

# TWO bugs in the ternary's typing, and the second survives fixing the first

perigrin: there are at least two bugs -- one is that it is not typing things
`Unknown`; the second, once that is fixed, is that it types things `Unknown`
rather than a type that can coerce to a target type.

Both confirmed by measurement.

## Bug 1: absence, not `Unknown`

The recursive `Call` is left unstamped -- Perl `undef`, not a lattice point --
so `_join_repr` cannot run over it at all. This is the finding above.

## Bug 2: `Unknown` swallows the join

Measured directly against `TypeLibrary`:

    join(Int, Int)      = Int
    join(Int, Unknown)  = Unknown        <- the known type is DISCARDED
    join(Int, Str)      = Str

    is_subtype(Int, Unknown) = 1
    is_subtype(Unknown, Int) = 0

`Unknown` is TOP, so everything is a subtype of it and it wins every join. Fix
bug 1 alone and `fib`'s ternary types `Unknown` -- the base case's `Int` is
taken and thrown away.

The join is not malfunctioning. Least-upper-bound is the right operation for a
MERGE of two known types and the wrong operation for "one arm is known and the
other has not been inferred yet".

## The fix: `Unknown` must not participate in a join

It contributes no constraint. Drop `Unknown` arms, join the rest, and `fib`'s
ternary types `Int` from its base case alone.

**There is precedent in this exact file.** `_join_repr`'s callers already drop
`Undef` for the `//` case: "Undef contributes no value to widen, so it is
dropped before the join and the defined arm's type wins."

The justifications differ and both are worth keeping straight:

- `Undef` is dropped for a SEMANTIC reason -- `$a // $b` never yields undef when
  `$a` is defined, so undef is not a possible result.
- `Unknown` must be dropped for an EPISTEMIC one -- it is not a claim about the
  value at all, it is an admission that inference has not finished.

## The deeper shape

perigrin's phrasing -- "a type that can coerce to a target type" -- points past
the immediate fix. What a recursive callee needs is not a widening but a
HYPOTHESIS: assume the return type is the join of the arms that ARE known, then
check the recursive arm is consistent with it. That is ordinary fixpoint
inference over a recursive definition, and it is exactly why a base case exists.

Dropping `Unknown` from the join is the first iteration of that hypothesis. It
is sufficient for `fib` (one typed arm, one recursive) and it is NOT a general
solution -- mutual recursion where no arm is typed on the first pass would still
need real iteration to a fixpoint.

## What this does NOT establish

- Not established: that `fib` compiles once both are fixed. Call emission is
  still required for the recursion itself; this is only the typing half.

---

# `Unknown` is useful in INFERENCE and useless as a REPRESENTATION

perigrin: it is useful in inference, it is useless for building a program with
correct value representation.

That is the rule, and it resolves the caveat this doc left open.

`Unknown` is a good inference value: a real lattice point, it composes, it is
the sound top, and it lets a fixpoint say "not yet" without lying.

A REPRESENTATION is a machine-level commitment -- how many bits, which register
class, what a `phi` and its coercions must agree on. **There is no encoding of
`Unknown`.** `%x = phi Unknown` is not a thing. So an `Unknown` reaching codegen
means inference did not finish, and the compiler must refuse rather than pick.

## This answers the open question above

I recorded "a Phi over a genuinely unknown arm may want to stay unknown rather
than adopt the other arm's type" as unmeasured. It is not a real option: a Phi
arm still `Unknown` at codegen time is **not a type to preserve, it is a failure
to report**. Staying `Unknown` is not conservative -- it defers a refusal to a
layer that cannot make one.

## The shape

    inference   MAY hold Unknown, join over it, iterate to a fixpoint
    the boundary into codegen  MUST narrow every Unknown, or GAP
    codegen     must NEVER see one, and must say so if it does

The field is called `representation` but currently holds an INFERENCE RESULT.
Those coincide exactly when inference succeeds, and diverge exactly when it does
not -- which is the case that matters, and today shows up as an absent field
that 24 sites each answer for themselves.

`_require_repr` is groping toward this boundary already. Its message ("fix
TypeInference to annotate this node") names a subsystem that is not on this path
and describes an absent field rather than an undischarged obligation. The
boundary check is the right idea; the message and the representation of "not
known" are both wrong.

---

# CORRECTION: the obligation is at the FORCING OPERATION, not a phase boundary

perigrin: it is an option until we need a representation -- like a Store (as an
SSA operation).

I stated this rule two different wrong ways before this. First "a Phi over a
genuinely unknown arm may want to stay unknown" (too permissive, filed as an
open question). Then "an arm still Unknown at codegen is a failure to report"
(too strict -- it treats codegen as one moment). Neither is right.

## The rule

**`Unknown` is legal until an operation must ENCODE it.**

A representation is a machine-level commitment -- width, register class, what a
`phi` and its coercions must agree on. The demand for one arrives at the
operation that has to emit something, not at the edge of a compilation phase.

FORCING operations -- must have a concrete representation, must GAP without one:

- `Store` -- writes a value to a location; both sides need a width
- `Phi` -- reconciles values across control edges into one register class
- a `call` -- the ABI names types
- arithmetic -- must choose int vs float
- a coercion -- its target IS a representation

NON-forcing: a pure computation with no consumer yet demanding a width may carry
`Unknown` indefinitely, and it costs nothing.

`Store` and `Phi` are the same family: the ops that RECONCILE values are the ops
that force them to agree.

## Why `_require_repr` feels misplaced

It fires at LOWERING -- "reached LLVM backend with NO representation" -- which is
a phase, not a commitment. That is why its message cannot name a real cause: it
asks "why is this untyped?" at a point where the honest question is "which
operation needed a type and did not get one?"

## Two consequences

**For `fib`:** the ternary must narrow because its value flows into a `Return`
and into arithmetic, both forcing. So dropping `Unknown` from the join is
narrowing exactly when required -- not an early guess.

**For the 24 hand-check sites:** they are NOT all the same, and today they look
identical. Some are forcing points that should GAP with a specific message
naming the operation; others are pass-throughs that should propagate `Unknown`
unchanged. Testing `defined` at all of them erases the distinction, which is
why it is currently invisible.
