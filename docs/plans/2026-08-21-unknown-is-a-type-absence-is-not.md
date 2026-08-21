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
