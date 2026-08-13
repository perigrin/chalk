# Followups after the corpus-as-programs migration

**Date:** 2026-08-13
**Status:** OPEN items, filed not built

## Bool-as-Int adversarial guard (REMOVED, needs replacement)

`t/bootstrap/corpus/statements.t` SECTION 5 held a guard proving that a Bool
lowered as a raw Int gets caught. It is deleted, and this is the ticket to
replace it.

**What it proved.** Under the FRAGMENT contract its fixture built a graph
returning `Int:0` where the perl oracle returned `Bool:`. The type-tagged
oracle made that a tag mismatch, so `run_case` failed loudly. It covered a real
miscompile class: modelling perl's Bool as integer 0/1, or as the empty string.

**Why it is gone.** The corpus-as-programs migration made the FIXTURE correct.
Under the program contract the same graph `Coerce`s Int 0 to the string `"0"`
and prints it — honest lowering. There is no longer a miscompile for the guard
to detect, and all four of its assertions pass.

It was removed rather than left passing because a guard that cannot fail is
worse than no guard: it reads as coverage while proving nothing. That is the
exact vacuity class this project keeps having to dig out (the `sub corpus_case`
wrap, the `ag -q` ACs, the empty-to-empty comparison).

**What a replacement needs.** A fixture that genuinely misrepresents a Bool
under the PROGRAM contract — i.e. a graph whose printed output diverges from
perl's because the Bool was modelled wrongly. Perl prints `1` for true and the
empty string for false:

    perl -e 'use 5.42.0; say(1<2)'   ->  "1\n"
    perl -e 'use 5.42.0; say(2<1)'   ->  "\n"

so a graph that prints `0` for false (Int modelling) or `1`/`0` where the string
face is wanted would diverge. The bilateral pair matters: a guard that only
covers the false polarity passes against a lowering that always prints the
empty string.

This is a NEW adversarial case, not an edit to the old one — which is why it is
filed rather than rushed alongside the migration cleanup.

## Not yet diagnosed

Three files still failing in `t/bootstrap/corpus/`, none investigated:

- `mdtest.t` — 9 failures. Unchanged across the migration (9 before, 9 after),
  so probably genuinely pre-existing, but that has NOT been confirmed against
  the pre-migration commit 73a51600.
- `ring-worklist.t` — 1
- `shape-subset-check.t` — 1

Do not describe these as pre-existing until measured against 73a51600. An
earlier baseline in this session stashed the working tree rather than comparing
against that commit, and reported migration fallout as inherited red — twelve
failures that the migration had actually caused.
