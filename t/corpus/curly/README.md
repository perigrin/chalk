# Stevan's curly examples

The 54 programs in `examples/` of [stevan/curly](https://github.com/stevan/curly)
(commit 389ca0ee, 2026-11-28), by Stevan Little, used here with his blessing as
a corpus of real programs a Perl programmer writes. Each `.pl` is his; each
`.expected` is perl 5.42's output for it, as his `t/checks.py oracle` recorded
it (checked against perl 5.42 when copied: all 54 match).

His `BENDS.md` records where a first draft was bent to fit curly; the programs
here are the bent versions.

`t/bootstrap/corpus/curly-examples.t` runs each through B::SoN, T2 and lli and
compares with perl: none may print a different answer, and each keeps the
verdict `VERDICTS.tsv` records (SAME, REFUSED by name, or LOUD). On copying,
2026-11-28: SAME 9, REFUSED 43, LOUD 2 (binomial dies where perl does not; gcd
emits IR lli rejects), WRONG 0.
