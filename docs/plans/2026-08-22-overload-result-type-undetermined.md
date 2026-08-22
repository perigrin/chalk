# Filed: overloaded operators have an undetermined result type

**Date:** 2026-08-22
**Status:** FILED, not scheduled. A constraint on future inference work.
**Source:** the type-lattice thread; resolved paper-side in
`~/dev/types-paper/2-perl-types-formal.md` under "Overloaded Objects".

## The constraint

An overloaded operator's result type is **not constrained by the language**.

    package Money { use overload '+' => \&add, ... }
    my $sum = $m + 1;      # returns whatever add() chose to return

Measured: this class returns a `Money`, but nothing requires it. A `'+'`
overload may return a number, a string, a different class, or undef.

**For inference this means `$obj + $x` is `Unknown` unless the class is known
and its overload table has been read.** It cannot be typed from the operator,
which is the usual route for arithmetic.

## Why it is not a problem today

Chalk types arithmetic from operand reprs, and an overloaded operand would have
repr `Object` — which has no arithmetic rule, so it GAPs rather than guessing.
GAP-not-miscompile holds. The hazard appears only when inference starts
answering for `Object` operands.

## What the paper settled

An overloaded object is an **Object with a user-defined table of OUTBOUND
coercion edges** (`0+` to Num, `""` to Str, `bool` to Boolean). It is NOT a
member of the types it coerces to: it passes semantic fulfilment and fails
syntactic preservation, because `overload` declares no INBOUND edge and the
round trip cannot be attempted.

Two consequences that bite compiler work specifically:

1. **Coercions out of an overloaded Object are one-way.** No inbound edge
   exists, so a value coerced to Num cannot be recovered as the object. Any
   pass that coerces and later expects the object back is unsound. This
   constrains the inliner and CSE.

2. **The edge set is not just the declared keys.** `fallback` decides which
   further coercions Perl synthesizes. Measured: `fallback => 0` refuses
   `0 + $m` outright; `fallback => 1` derives arithmetic from `0+`. A reader of
   an overload table must read `fallback` with it.

## In SSA terms

An overload table is a set of `Coerce(Object -> T)` edges supplied by the
programmer rather than by the language. Chalk needs no new node type — the
frontend would learn to read `%OVERLOAD` as coercion edges, and `Coerce`
already exists and already lowers.
