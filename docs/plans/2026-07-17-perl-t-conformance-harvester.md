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

## The core design problem: the SHAPE leg has no hand-written `ir` block

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

Recommendation to discuss: **(C)** — harvest is a discovery+breadth engine
(behavior+invariant), the hand corpus stays the spec (full tri-fold), and the
gate reports the two populations separately so gate-green never conflates
"conforms" with "spec-locked." This preserves the honest-number discipline
(gate-green today counts full tri-fold; harvested conformance is a SEPARATE
tally, not folded in).

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

## Open questions for review

1. Shape-leg contract: (A) two-tier, (B) auto-skeleton, or (C) behavior+inv +
   hand-promote? (recommendation: C)
2. First harvest scope once the pipeline is trusted: t/opbasic (5 files) as the
   proving ground, then t/op? (the pipeline must be validated on the small tier
   before scaling to 5k assertions.)
3. Preamble-gathering depth: how far back in a test block does the extractor
   walk to make an assertion self-contained? (block-local `my` only, or the
   whole file's top-level lexicals?) This bounds extractor complexity and the
   skip rate.
4. is_deeply / list-context assertions: defer to a later pass, or in scope now?
5. Do we vendor the harvested corpus (checked-in .md/.json) or regenerate it
   from ~/dev/perl5 at test time? (vendoring = reproducible + reviewable diffs;
   regenerate = always-fresh but depends on the perl5 checkout.)
