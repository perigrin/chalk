# ABOUTME: Milestone plan for harvesting Perl's t/ test assertions into a
# ABOUTME: tri-fold-gated corpus that drives the -auto loop (on-ramp to lib/).

# Perl t/ conformance harvester (2026-07-17)

Status: PLAN — no code until reviewed (perigrin).

## The idea (perigrin, 2026-07-17)

Instead of growing coverage only against a hand-authored corpus, harvest
assertions from Perl's own `t/` test suite and run them through the existing
tri-fold gate. `t/` is a vast, pre-labeled behavior oracle: every
`is(EXPR, EXPECTED)` is a known-correct fact about core Perl semantics.

## Framing (DECIDED)

**On-ramp, lib/ still the goal.** This is NOT a pivot to a conformance target.
Self-hosting lib/ remains the Phase-5 definition-of-done and is finished last.
The `t/` corpus is a higher-throughput DRIVER: it builds the core runtime-free
(RF) semantics machinery faster and gives `-auto` a smooth coverage gradient
instead of lib/'s lumpy closed-set. The hard lib/ frontier (self-hosting
codegen, parked regex, deep OO) is unaffected and comes last.

## Why it is worth building (MEASURED, this session)

Source: `~/dev/perl5` @ blead `94e5086608` (pulled 2026-07-17). 620 `.t` files.

Core RF-relevant tiers and assertion counts:

| tier | files | is/ok/cmp_ok/like |
|------|------:|------------------:|
| t/op | 228 | 7820 |
| t/comp | 25 | 216 |
| t/opbasic | 5 | 282 |
| t/class | 12 | 124 |
| t/base | 9 | 6 (old print-style; low yield) |

Assertion-level harvestability in t/op (the decisive cut):

- 5,475 single-line `is(EXPR, EXPECTED)` matched.
- **~5,100 (93%) have a first arg free of eval/IO/pack/magic tokens** — the
  plausibly-in-subset slice.
- File-level filtering is MISLEADING: `eval` appears in 157/228 files, so
  "clean whole files" = only 47/228. But `eval` is one exception block sitting
  next to dozens of clean `is(2+2,4)` lines. **Harvest per-ASSERTION, skip
  out-of-subset assertions WITHIN a file** — that is where the ~50x-larger
  oracle lives (vs. the current ~98-case hand corpus).

Feature fit: t/op/t/opbasic exercise arithmetic, string, compare, control flow
— exactly Chalk's RF strength — not lib/'s self-hosting frontend.

## Perl's OWN test-ordering is the authoritative sequencing (t/README + t/TEST)

Do not guess tier order — Perl documents the dependency/capability ladder its
tests bootstrap in. `t/TEST:562` runs:

    base  comp  run  cmd  io  re  opbasic  op  uni  mro  class  perf  test_pl

and `t/TEST:556-559` explains why:
- **base first** — TEST *bails out* if base fails; base sanity-tests the rest.
- then **comp** — validates `require` works.
- then **run** — validates `-M` works.
- then everything else can `-MTestInit`.

The load-bearing constraint (`t/README:25-28`): **t/base tests must be runnable
with plain miniperl alone — they must NOT assume `require` works, let alone
`require Config.pm, strict, or warnings`.** That is EXACTLY Chalk's runtime-free,
no-runtime-`use`/`require` subset. `t/base` is definitionally the minimal-
interpreter ring, so it is the correct Mode-1 starting point — now authoritative,
not a friendliness guess.

Mapping Perl's ladder onto Chalk (they are NOT identical — Chalk has no runtime
module loading, so the ladder's `require`/`-M` rungs do not map):
- **base** — minimal-interpreter ring. START HERE. MEASURED: 6/9 files fully in
  subset (cond, if, num, pat, translate, while — no require/eval/open/modules);
  lex/rs/term reach past miniperl (eval/open) and loud-skip. Those 6 exercise
  print (98), string/num compare (eq 53, == 22, ne, !=, <=, >=), short-circuit
  (|| 11, && 4), if/unless/while, my — squarely RF. (One =~ in pat.t → skip.)
- **comp** — Perl's purpose here is "does require work"; for Chalk only the pure
  COMPILATION tests matter, not the require-validation. Cherry-pick, don't
  assume the whole ring maps.
- **run** — "does -M work" — largely N/A for Chalk (no -M). Mostly skip.
- **cmd** — control-flow commands; in-subset, a good early ring.
- **re** — regex; PARKED (019f6c68). Skip regardless of Perl's ordering.
- **opbasic, op** — the core-semantics motherlode; opbasic is framework-free
  (Mode 1), op is Test::More (Mode 2).
- **uni** — unicode; ties to G3 non-ASCII, mostly out-of-subset for now.
- **class** — modern `feature class` OO; Chalk supports it — a real later ring.

So the Chalk Mode-1 ring order is Perl's order minus the non-mapping rungs:
**base → cmd → opbasic → (cherry-picked comp) → op(Mode 2) → class**, with
re/run/uni skipped or deferred. This REPLACES the earlier guessed
t/base→t/opbasic→t/cmd→t/comp sequence.

## TWO HARVEST MODES (perigrin, 2026-07-17): the test file IS an oracle

Key refinement: a framework-free `.t` file is ALREADY an executable oracle — it
runs and prints a TAP stream, and TAP is machine-checkable. So for those files
we do NOT extract assertions at all; we compile the WHOLE FILE to LLVM, run it
under lli, and diff stdout against perl's stdout (identical TAP; every line
`ok`, none `not ok`). Dozens of in-context assertions validated in one lowering,
zero extraction, zero preamble-gathering — the extractor's hardest half deleted.

The gate is "does the file reach the TAP oracle without machinery Chalk cannot
lower." That is precisely the OLD-STYLE core tests: `print "ok $n\n"` /
`print "not ok $n\n"`, no framework. And — not a coincidence — the most
in-subset tier is ALSO the framework-free tier (these tests are written to run
on a barely-built perl before Test::More exists).

MEASURED framework-freedom (files that pull in NO test framework):

| tier | files | framework-free | mode |
|------|------:|---------------:|------|
| t/base | 9 | 9 (100%) | whole-file oracle — pure `print "ok"` |
| t/opbasic | 5 | 5 (100%) | whole-file oracle |
| t/cmd | 5 | 5 (100%) | whole-file oracle |
| t/comp | 25 | 22 (88%) | whole-file oracle |
| t/op | 228 | 4 | assertion-extraction (needs Test::More) |

So the harvester has TWO modes:

- **Mode 1 — whole-file oracle** (t/base + t/opbasic + t/cmd + most t/comp =
  ~41 framework-free files). Compile the `.t` file, run under lli, assert stdout
  == perl stdout. NO extraction. Higher fidelity (real in-context Perl). START
  HERE — it is easier AND better than extraction.
- **Mode 2 — assertion extraction** (t/op's ~5,100 `is()` slice, Test::More
  files). The original per-assertion pipeline, for files whose oracle is a
  framework Chalk cannot compile.

### Mode 1 PREREQUISITE (measured): `print`-to-stdout must lower

Today the backend lowers "a function RETURNING a value" — the epilogue
`printf`s the single return value's typed repr (`Int:7`) for the harness. There
is NO `print`-statement lowering and NO `Print` node in the producer. Mode 1
needs `print "literal\n"` to lower to real stdout.

Optree scope (measured): `print "ok 1\n"` = `pushmark -> const(PV) -> print`
(a listop defaulting to STDOUT). Contained work:
- Producer: a `print` handler emitting a `Print` node (like the existing
  statement-effect nodes RegexSubst/etc.); subject = the string arg.
- Backend: `_lower_print` emitting `write(1,ptr,len)`/`fputs` — the C-call +
  epilogue-printf machinery already exists.
- CAVEAT: `print "$x"` (interpolating) pulls in `multiconcat` (deferred decoder
  019ee838). LITERAL print is trivial; interpolating print is a follow-on. Many
  t/base lines are literal (`print "ok 1 - ...\n"`), so a literal-first `print`
  unlocks a real slice before multiconcat lands.

`print` is a genuine in-subset core feature (all over the RF slice), NOT harness
scaffolding — so this prerequisite is real capstone-relevant work, not throwaway.

## The core design problem (Mode 2 only): the SHAPE leg has no hand-written `ir` block

The existing tri-fold (`t/bootstrap/corpus/son-corpus-wide.t`) is:

1. **behavior**: `lli(lower(from_json(B::SoN(source)))) eq perl-oracle(source)`
2. **shape**: `shape_subset_check($case->{ir}, $loaded_graph)` — matches the
   loaded graph against a HAND-WRITTEN `ir` block (rooted-subset).
3. **invariant**: TypedInvariant over the loaded graph.

A harvested `t/` assertion supplies source + expected value (legs 1 and, via
the harvested expected, a BETTER oracle than the hand `return:` line). It does
NOT supply a hand-written `ir` block, so **leg 2 as written cannot run**. This
is THE design decision the plan must resolve. Options (to decide at review):

- **(A) Two-tier contract.** Harvested cases run behavior + invariant only
  (a "conformance" contract); hand-authored corpus keeps the full tri-fold
  (the "spec" contract). Honest, simplest, but drops shape coverage on the
  harvested slice — and shape is what catches lower-drops the gate exists to
  catch. Risk: a harvested case can behave-correctly-by-luck while the graph
  is wrong (the exact false-green the shape leg was added to kill).
- **(B) Auto-derive a shape skeleton.** For a harvested case, take the loaded
  graph itself, reduce it to a rooted op-signature, and assert the lowered
  graph is a subset of THAT (self-consistency). Weaker than a hand spec (it
  cannot catch "the producer built the wrong shape"), but it re-enables a
  structural check and a TypedInvariant anchor. Effectively behavior + invariant
  + "graph is internally well-formed."
- **(C) Behavior+invariant now, hand-promote high-value cases to full tri-fold.**
  Harvest gives behavior+invariant breadth; when a harvested case reveals a
  real feature gap, promote it into the hand corpus WITH an ir block. Keeps the
  spec contract meaningful and lets the harvest be the discovery engine.

DECIDED (perigrin): **(C)** — harvest is a discovery+breadth engine
(behavior+invariant), the hand corpus stays the spec (full tri-fold), and the
gate reports the two populations separately so gate-green never conflates
"conforms" with "spec-locked." This preserves the honest-number discipline
(gate-green today counts full tri-fold; harvested conformance is a SEPARATE
tally, not folded in).

Note: (C) governs Mode 2 (extracted assertions). Mode 1 (whole-file oracle) has
an EVEN STRONGER behavior leg — the file's real TAP stream vs perl's, dozens of
in-context assertions per file — plus the invariant leg over the loaded graph.
Both modes stay OUT of the hand-corpus gate-green number.

## Pipeline components (to build, in order)

### 1. Extractor (`t/lib/.../Harness/TCorpusExtractor.pm` — proposed)

Input: a `t/**/*.t` path. Output: a list of harvested cases
`{ subject, expected, cmp, source_file, source_line, skip_reason? }`.

- Parse each assertion form: `is(EXPR, EXPECTED [,name])`,
  `cmp_ok(EXPR, OP, EXPECTED)`, `ok(EXPR)`, `is_deeply` (list/agg — later).
- EXPECTED must be a compile-time-known literal (number/string/undef). A
  non-literal expected (a variable, a computed RHS) => SKIP (cannot form an
  oracle without running the file).
- SUBJECT (EXPR) must be self-contained: it may reference `my` lexicals
  declared earlier in the same test BLOCK, which the extractor must gather
  (the harvested "source" = the lexical preamble + the subject expression).
  This is the hard part — assertions are not hermetic; they lean on setup.
- **Out-of-subset SKIP is LOUD and COUNTED** (GAP-not-silent-skip invariant):
  an assertion whose subject/preamble touches eval/open/fork/tie/format/
  typeglob/local/pack/sprintf/syscall/XS/regex is skipped with a named reason
  and tallied. Never silently dropped. The skip histogram IS the coverage-gap
  map (which feature to build next), exactly like the regex scan.

### 2. Adapter — wrap a harvested case into the tri-fold runner

Reuse `son-corpus-wide.t`'s `run_through_bson` verbatim (B::SoN -> from_json ->
LLVM -> lli). Behavior = `lli eq harvested-expected`. The perl oracle is
REPLACED by the harvested expected value (it is already the known-correct
answer — no need to re-run perl). Invariant leg unchanged. Shape leg per the
(A)/(B)/(C) decision above.

### 3. Gradient runner (`t/bootstrap/corpus/t-conformance.t` — proposed)

Runs all harvested cases, tallies conformance% (lli==expected) + invariant% +
skip-histogram. Emits a coverage gradient the `-auto` loop reads. A floor
assertion (monotonic, like the gate floor) locks in gained conformance.

### 4. Skip histogram -> the next-feature signal

The counted skips, ranked by frequency, are the prioritized worklist of
in-subset features to implement — the same mechanism the regex scan used, but
now continuously regenerated as the driver.

## Guardrails (non-negotiable)

- **Loud, counted skips.** No silent drop of an out-of-subset assertion. The
  skip histogram is a first-class output.
- **Separate tallies.** Harvested conformance is NOT folded into the
  hand-corpus gate-green number. Two populations, two numbers. The honest-number
  rule (gate-green = full tri-fold) is preserved.
- **New milestone, own zhi chain.** Not folded into the parked regex axis
  (019f6c68) or the MOP axis. Filed fresh.
- **Pin the perl5 SHA.** Harvested cases are keyed to a blead commit; record it
  so the corpus is reproducible and re-harvest is a deliberate, reviewed step.
- **lib/ stays definition-of-done.** This driver does not move the capstone
  goalposts; it accelerates the machinery that gets there.

## Revised sequencing (Mode 1 first)

1. **`print`-to-stdout lowering** (literal args first): producer `Print` node +
   backend `_lower_print`. Real core-feature work, gates Mode 1. Corpus cases in
   the hand corpus (host/statements tier) with the full tri-fold.
2. **Mode 1 runner**: compile a framework-free `.t` file -> lli -> assert stdout
   == perl stdout. Proving ground = t/base (Perl's authoritative FIRST ring;
   6/9 files fully in-subset, pure literal `print "ok"`). The 3 miniperl-
   exceeding files (lex/rs/term) loud-skip.
3. **Widen Mode 1 in Perl's ladder order** (minus non-mapping rungs): t/cmd ->
   t/opbasic -> cherry-picked t/comp. re/run/uni skipped/deferred. Skip-histogram
   (loud, counted) names the next feature to build as each ring stalls.
4. **Interpolating print** (multiconcat decoder, 019ee838) — unlocks the
   `print "ok $n\n"` counter idiom that many files use.
5. **Mode 2 (extraction)**: only after Mode 1 is trusted and t/op (Test::More)
   is the remaining frontier. This is where the (C) shape-leg contract and the
   extractor's preamble-gathering live.

## Open questions for review

1. Shape-leg contract: DECIDED (C), governs Mode 2. Mode 1 uses the TAP stream.
2. Mode 1 proving-ground order confirmed t/base -> t/opbasic -> t/cmd -> t/comp?
3. `print` prerequisite: literal-only first (defer interpolation to multiconcat),
   or wait for multiconcat so the counter idiom works from day one?
4. Mode 2 preamble-gathering depth (deferred until Mode 2): block-local `my`
   only, or whole-file top-level lexicals?
5. is_deeply / list-context assertions: defer to a later pass, or in scope now?
6. Vendor the harvested corpus (checked-in) or regenerate from ~/dev/perl5 at
   test time? Pin the perl5 SHA either way (currently blead 94e5086608).
