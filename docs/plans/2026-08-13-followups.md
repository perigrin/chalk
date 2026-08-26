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

## C backend: a genuine crash in parked code, exercised by a legacy-comparison test

**Filed 2026-08-26. Not fixed, deliberately — see "why not now".**

`t/bootstrap/c-analysis-helpers-schedule.t` dies:

    Can't locate object method "value" via package "Chalk::IR::Node::Start"
    at lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm line 803

**The bug is real, and small.** `:803` reads a `VarDecl`'s name:

    my $vname = ref($name) ? $name->value : "$name";

It assumes the name is a plain string or something answering `->value`. It is
neither: a `Start` node arrives, `ref()` is true, and `->value` does not exist.
Either a `VarDecl` is being built with a control node where its name belongs,
or this helper is reading the wrong input slot. Both are worth knowing; neither
is diagnosable without deciding what that path is supposed to receive.

**Why not now.** Two reasons, and the second is the binding one:

1. The test compares a Schedule-consuming rewrite against a LEGACY
   implementation ("Verifies the 6 schedule-substrate helpers produce
   equivalent results to legacy") — its own ABOUTME. A test whose oracle is a
   superseded implementation reports drift from something already replaced.
2. **The C backend is parked.** `CLAUDE.md` records it: `Target::C`'s public
   `generate($mop)` is a stub, its real entry is
   `_generate_c_files($ir, $sa, $ctx)` — the last surviving `($sa,$ctx)`
   backchannel, "the same 'literal moved, contract didn't' pattern
   `compat_class` had" — and per the LLVM-first decision it parks near-capstone
   with the C/XS axis.

Fixing a crash inside parked code, found by a test measuring against a legacy
oracle, is work on the axis that was deliberately deferred.

**What it is evidence FOR.** The C backend needs rethinking rather than
patching, which is what the parking decision already says. Record this crash as
one datum in that case, not as a bug to chase.

**Do not** silence the test to make the suite green. It is failing honestly,
and a red test that names a real crash is worth more than a green one that
hides it — the failure mode this project has already had to dig out repeatedly
(`red_tests_hide_real_bugs`).
