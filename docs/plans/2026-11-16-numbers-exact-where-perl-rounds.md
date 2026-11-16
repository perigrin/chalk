# Numbers: exact where perl rounds

Status: direction agreed with perigrin, 2026-11-16. Nothing here is built yet
except the UV form and T1's integer intervals (step2-uv).

## The ruling

Perl's IV / UV / NV forms are perl5's implementation, not Perl the language,
and they leak: the same value prints two ways depending on how it was made
(`9007199254740993` vs `2**53 + 1`). So:

- **Where they live.** The forms, and perl5's promotion rules between them,
  are T2's business alone. T1 holds only representation-free facts (an
  integer's interval). The wire carries a literal's exact value, never a form.
- **Chalk may break with perl when its answer is provably correct.** That is a
  second legitimate ground for a declared deviation, beside "static compilation
  cannot do what perl does". The reason states the proof; a deviation is only
  ever more exact or more consistent than perl, never less; "chalk has not
  yet" stays illegitimate. Declared in the corpus (`L: DEVIATES`) and the
  census alike, and reported as DEVIATES, never as SAME.

## What the ruling opens, in order

1. **i128 integers in T2** (proposed, awaiting perigrin's go-ahead). Exact up to
   2**127, then a double -- one rule, where perl's is exact to 2**64. Bitwise
   ops, `sprintf "%d"`, `pack "Q"` and the like keep perl's widths: widening
   them changes the answer rather than sharpening it. Range analysis keeps
   proven loop counters on plain i64.
2. **Rationals, after chalk's own front end replaces B::SoN.** Raku's model: a
   decimal literal is an exact fraction (`0.1 + 0.2 == 0.3` holds), falling
   back to a double when the denominator passes a cap or an op is irrational
   (sqrt, sin, exp, fractional **). It needs the literal's source text, and
   B::SoN reads perl's optree, where `0.1` is already a rounded double -- so it
   waits for Chalk::Grammar::Perl. Open questions for its design doc: whether
   ground (b) covers a changed branch as well as changed output; the
   denominator cap; printing to perl's 15 significant digits where perl's
   output is already right. Needs i128 underneath.
