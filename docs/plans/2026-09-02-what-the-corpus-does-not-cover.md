# ABOUTME: Idioms lib/Chalk uses that no corpus case exercises, measured not guessed.
# ABOUTME: The gap between what the gate covers and what the code uses is where live miscompiles hid.

# What the corpus does not cover

A live miscompile was found on 2026-09-02 in an idiom with ZERO corpus
coverage, and neither this project's gate nor perl5-son's registered the bug or
its fix. This records the general form of that gap so it is a map rather than
an anecdote.

## How the slice case surfaced

Not by measurement. It came from reporting a NEGATIVE result -- "zero corpus
cases use a slice" -- next to where the idiom actually lives: 10 uses in
`lib/Chalk`, including `@_[-2, -1]` in the LLVM backend itself. **Neither
number means anything alone.** A count of zero is unremarkable until it is
paired with a count of ten in the code that has to compile itself.

perl5-son then found two producer bugs in that idiom, one of which chalk had
independently in its own element-typing (fixed in 6f1f9d1d: a `Slice` occupies
one input slot but holds many elements, so a slot-count bounds check stamped a
real read `Undef`).

Both gates were blind to it:

    chalk       gate-green 214 -> 214, worklist 8 -> 8, fixed 0, broken 0
    perl5-son   base/cmd/comp unchanged at 37 OK / 366 Unknowns

Two independent metrics, neither able to see a live wrong-answer bug. The only
thing guarding it now is a unit test.

## The measured gap

Idioms present in `lib/Chalk/**/*.pm` and absent from every file in
`t/corpus/mdtest/`:

| idiom      | lib/Chalk files | corpus files |
|------------|-----------------|--------------|
| `reverse`  | 17              | 0            |
| `delete`   | 13              | 0            |
| `@$...[`   | 5               | 0            |
| `index(`   | 2               | 0            |
| `eval {`   | 1               | 0            |
| `lc(`      | 1               | 0            |
| `uc(`      | 1               | 0            |
| `local $`  | 1               | 0            |

`reverse` and `delete` are not exotic. They are ordinary list and hash
operations used across a seventh of the library.

For contrast, the idioms that ARE covered -- and note that "covered" here means
at least one topic file mentions them, not that they are covered well:

| idiom      | lib/Chalk files | corpus files |
|------------|-----------------|--------------|
| `map {`    | 32              | 1            |
| `grep {`   | 21              | 1            |
| `keys %`   | 21              | 2            |
| `sprintf`  | 11              | 2            |
| `sort {`   | 11              | 1            |
| `local `   | 9               | 1            |
| `wantarray`| 4               | 1            |

## ZERO IS NOT THE ONLY EXPOSURE, and this table missed that at first

The list above was built by looking for idioms with NO corpus file. That found
the slice case, but it is the wrong shape for the biggest surface. High usage
with THIN coverage is the same risk one step less obvious:

| idiom     | lib/Chalk files | corpus files |
|-----------|-----------------|--------------|
| `join(`   | 44              | 2            |
| `ref(`    | 34              | 2            |
| `map {`   | 32              | 1            |
| `grep {`  | 21              | 1            |
| `keys %`  | 21              | 3            |
| `split`   | 17              | 2            |
| `sort {`  | 11              | 1            |
| `substr`  | 10              | 1            |

`join` at 44 library files against 2 corpus files is a larger surface than
`lc(` at a single occurrence. And "one corpus file" is not one case, but it is
thin enough that a SECOND POLARITY probably is not there -- which is exactly
the shape that let the `exists` miscompile survive: the present-key case agreed
with the broken mapping by coincidence, and only the absent-key case
discriminated.

So the ranking is not "zero first". It is roughly usage-weighted, and the
question to ask of a covered idiom is whether the corpus has the case that
would FAIL if the implementation were wrong -- not whether it has a case.

## What this is not

It is NOT a claim that each row is a bug. It is a claim that each row is a
place where a bug would be INVISIBLE to the gate -- which is the condition the
slice miscompile needed in order to exist, and to survive a fix on the producer
side without either project noticing.

Nor is it a work list in priority order. `reverse` leading on file count says
nothing about whether reverse lowers today; that has not been measured.

## What to do with it

1. When adding corpus cases, prefer an idiom from this table over another
   variation of something already covered.
2. When a case IS added, exercise what is DOWNSTREAM of the construct, not just
   the construct. The slice bug is the worked example: the `Slice` node was
   byte-identical before and after perl5-son's fix, and the damage was one node
   later in the indexed read. A case checking only the slice would have passed
   throughout.
3. Re-measure this table rather than trusting it. It was produced by `grep -l`
   over source text, so it counts textual occurrences and cannot tell a use
   from a mention in a comment.

## Method

    for pat in ...; do
      lib=$(grep -rl -- "$pat" lib/Chalk --include=*.pm | wc -l)
      cor=$(grep -l  -- "$pat" t/corpus/mdtest/*.md     | wc -l)
    done

Crude by design -- the point is the PAIRING of the two counts, and a crude
measure that gets reported beats a precise one that does not.
