# ABOUTME: PRD for the Perl t/ conformance harvester — a t/-driven corpus that
# ABOUTME: drives the -auto loop as an on-ramp to the lib/ self-hosting capstone.

# PRD: Perl t/ conformance harvester

**Status:** DRAFT for crochet:assess. Design doc + measurements:
`docs/plans/2026-07-17-perl-t-conformance-harvester.md`.

## Problem

Chalk's Phase-5 capstone driver is the hand-authored mdtest corpus
(`t/corpus/mdtest/*.md`, ~98 cases). Coverage grows at authoring speed and
reflects the author's guesses about which idioms matter. The `-auto` loop needs
a larger, pre-labeled, smoothly-graded fitness function to build core
runtime-free (RF) semantics faster.

Perl's own `t/` suite is a vast behavior-labeled oracle: every assertion is a
known-correct fact about core Perl. Measured (`~/dev/perl5` @ blead
`94e5086608`): `t/op` alone has 7,820 assertions; ~5,100 of 5,475 single-line
`is(EXPR, EXPECTED)` are plausibly in-subset (93%). 41 core files are
test-framework-free.

## Goal & non-goals

**Goal:** harvest Perl `t/` into a tri-fold-gated corpus that drives `-auto`,
building core RF semantics with a smooth coverage gradient.

**Non-goals (DECIDED, perigrin):**
- NOT a pivot to a conformance product. Self-hosting `lib/` remains the Phase-5
  definition-of-done and is finished last. This corpus is a DRIVER, not the gate.
- NOT folded into the parked regex axis (019f6c68) or the MOP axis. New chain.
- NOT built on the parked atom-list regex compiler; `t/re` is skipped.

## Two harvest modes (DECIDED: build BOTH)

- **Mode 1 — whole-file TAP oracle.** A framework-free `.t` file is already an
  executable oracle: it prints TAP. Compile the WHOLE FILE to LLVM, run under
  lli, assert stdout == perl stdout (every line `ok`, none `not ok`). No
  assertion extraction. Applies to the 41 framework-free core files.
- **Mode 2 — assertion extraction.** For `Test::More` files (t/op), extract each
  `is(EXPR, EXPECTED)` into a corpus case (subject + expected). Governed by the
  (C) shape-leg contract below.

## Authoritative sequencing (Perl's own, t/README + t/TEST:562)

Perl documents its bootstrapping ladder:
`base comp run cmd io re opbasic op uni mro class perf`. `t/base` MUST run under
plain miniperl (no `require`/`strict`/`warnings`) — exactly Chalk's RF subset.
The Chalk ring order (Perl's minus non-mapping rungs — Chalk has no runtime
module loading, so `require`/`-M` rungs and `re` do not map):
**base → cmd → opbasic → cherry-picked comp → op (Mode 2) → class.**

## Requirements

### R1 — print-to-stdout lowering (literal args first) [FIRST BRICK]
`print LIST` must lower to real stdout. Today the backend only printf's the
single return value in the epilogue; there is no `Print` node in the producer
and no `_lower_print` in the backend.
- **R1.1** Producer (perl5-son `SoN::FromOptree`): a `print` handler emits a
  `Print` IR node (statement-effect, like RegexSubst). Subject = the string arg.
- **R1.2** Backend (`Chalk::Target::LLVM`): `_lower_print` emits a libc write of
  the string bytes to fd 1 (`write(1,ptr,len)` or `fputs`).
- **R1.3** Ordering: `print` output precedes the epilogue `TYPE:value` line, on
  both the perl oracle and lli sides (the corpus gate already captures full
  stdout via `qx`). `print "hi\n"; 1` → combined stdout `hi\nInt:1`.
- **R1.4** `print` returns `1` (its own truth value) — usable as a value.
- **Acceptance:** hand-corpus cases at FULL tri-fold (behavior+shape+invariant),
  bilateral: bare-literal print; print-then-return; two-prints-ordering;
  print-as-value(1). Corpus gate-green floor rises; worklist=0.
- **Out of scope (R1):** interpolating `print "$x"` — pulls in multiconcat
  (019ee838). Filed as a follow-on requirement R1b, not R1.

### R1b — print with a coerced value (`print "ok $n\n"`)
The counter idiom pervasive in t/base. In Chalk this is NOT interpolation — it
is COERCION (perigrin): `"ok $n"` is `Concat(Str "ok ", Coerce[Int→Str]($n))`,
and the coerced Str carries a string length like any other Str. So there is no
"Int has no length" problem — the Int is coerced to a Str which HAS a length.
- **CORRECTED (pushback + perigrin, verified 2026-07-17):** NOT blocked on
  multiconcat (019ee838 is DONE). Two REAL gaps, both about the Int→Str
  coercion:
  1. **Producer gap.** The multiconcat/interpolation decoder does NOT currently
     emit the dynamic operand as `Coerce[Int→Str](PadAccess)`. Measured: for
     `"ok $n"` the producer emits `Concat(Constant, Constant)` with the `$n`
     PadAccess DANGLING (not wired into the Concat) — the dynamic arg is
     mis-folded to a bare Constant. This is the residual "general multiconcat
     decoder" the 019ee838 body noted "remains."
  2. **Backend gap.** Even given `Coerce[Int→Str]`, the backend `Coerce` switch
     has arms for Int↔Num and *→Bool and Bool→Int/Num, but NO `Coerce[Int→Str]`
     (integer→decimal-string) arm that emits the digits and records the length
     in `_str_len_table`. (Confirmed at `Context.pm:80` — the length table
     explicitly notes untracked-length cases like `Coerce(Bool→Str)`.)
  These are SEPARATE prerequisites (both useful beyond print); R1b blocks behind
  both.
- **Acceptance:** producer emits `Concat(Str, Coerce[Int→Str]($n))` for
  `"ok $n"` (PadAccess wired, no dangling); backend lowers `Coerce[Int→Str]` to
  digits + tracked length; `my $n=3; "ok $n"` → `Str:ok 3` (tri-fold); then
  `print "ok $n\n"` lowers.

### R2.0 — source-prep: wrap the top-level program body in a sub [pushback]
A `t/base` file is TOP-LEVEL statements, not a `sub`. B::SoN emits `methods: {}`
for a bare program body — no lowerable graph (verified 2026-07-17). So R2 must
first wrap the file body in a synthetic `sub __main__ { ... }` before B::SoN,
then lower that graph — reusing the existing `corpus_case`-wrap pattern the
harness already proves (`son-corpus-wide.t:52`). Producer untouched (DECIDED,
perigrin).
- **Acceptance:** a wrapped t/base body produces a `main::__main__` graph B::SoN
  lowers; an unwrapped bare program correctly yields no graph (documents why the
  wrap is needed).

### R2 — Mode 1 whole-file oracle runner
A test harness that, given a framework-free `.t` path, wraps it (R2.0), compiles
through B::SoN → from_json → LLVM → lli, and asserts lli stdout == perl stdout.
- **R2.1** Reuse the `run_through_bson` pipeline SHAPE (source → JSON → graph →
  LLVM → lli), but with the deltas below — it is NOT a drop-in reuse.
- **R2.2** Behavior leg = **full MULTI-LINE stdout equality** (a TAP stream is
  many lines), not the chomped single-line repr `run_through_bson` compares.
- **R2.3** **NO epilogue type-tag.** A `.t` file's real output is raw TAP
  (`ok 1\n`), not `Int:1`. The Mode-1 runner must lower the wrapped body so its
  `print`s go to stdout directly and NOT append the `TYPE:value` epilogue the
  corpus harness adds. (Contrast: R1's hand-corpus cases DO use the epilogue,
  because they test a returned value alongside the print.)
- **R2.4** Invariant leg = TypedInvariant over the loaded graph(s).
- **R2.5** A file that fails to lower produces a LOUD, COUNTED skip naming the
  first unsupported construct — never a silent pass or silent drop
  (GAP-not-silent-skip invariant). The skip histogram is a first-class output.
- **Acceptance:** the runner passes on ≥1 fully-in-subset t/base file end-to-end
  (candidate: `cond.t` or `if.t`) and loud-skips a miniperl-exceeding one
  (`lex.t`) with a named reason.

### R3 — Mode 1 proving ground: t/base
Run Mode 1 over t/base (Perl's authoritative first ring). Measured: 6/9 files
in-subset (cond, if, num, pat, translate, while); lex, rs, term loud-skip.
- **Acceptance:** the 6 in-subset files each either PASS (stdout==perl) or
  produce a counted skip histogram entry naming the missing feature. No silent
  drops. A monotonic floor locks the passing count.

### R4 — Mode 1 widening (Perl ring order)
Extend Mode 1 to t/cmd → t/opbasic → cherry-picked t/comp. The skip histogram
drives which feature to implement next as each ring stalls.
- **Acceptance:** each ring added with its own floor; skip histogram published.

### R5 — Mode 2 assertion extractor
Parse `Test::More` `.t` files (t/op), extract `is(EXPR,EXPECTED)` /
`cmp_ok` / `ok` into `{subject, expected, cmp, file:line, skip_reason?}`.
- **R5.1** EXPECTED must be a compile-time literal; else counted-skip.
- **R5.2** SUBJECT must be self-contained; gather the block-local `my` preamble.
- **R5.3** Out-of-subset subjects (eval/open/fork/tie/format/typeglob/pack/
  sprintf/syscall/XS/regex) → LOUD COUNTED skip. Histogram is the worklist.
- **Acceptance:** extractor over t/opbasic (proving ground, 5 files) yields
  valid cases; skip histogram published; no silent drops.

### R6 — Mode 2 tri-fold adapter (shape-leg contract C)
Wrap extracted cases into the tri-fold runner. Behavior = lli == harvested
expected (the expected IS the oracle; no re-run of perl). Invariant unchanged.
- **R6.1** Shape leg per (C): harvested cases run behavior+invariant; a case that
  reveals a real gap is PROMOTED into the hand corpus with an `ir` block (full
  tri-fold). Harvested conformance is tallied SEPARATELY from hand-corpus
  gate-green (honest-number discipline: gate-green stays full-tri-fold only).
- **Acceptance:** two tallies reported (hand gate-green; harvested conformance%);
  they are never conflated.

### R7 — Reproducibility
Pin the perl5 blead SHA the corpus is harvested against (currently
`94e5086608`). Decide vendor-vs-regenerate (checked-in corpus vs regenerate from
`~/dev/perl5` at test time). Re-harvest is a deliberate, reviewed step.
- **Acceptance:** the pinned SHA is recorded; the corpus is reproducible.

## Cross-cutting guardrails

- **Loud, counted skips everywhere.** No silent drop of an out-of-subset file or
  assertion. Skip histograms are first-class outputs and ARE the next-feature
  worklist.
- **Separate tallies.** Harvested conformance never folds into hand-corpus
  gate-green.
- **lib/ stays definition-of-done.** This driver does not move the capstone
  goalposts.

## Dependencies & ordering

R1 (print) is the FIRST BRICK — it gates R2 (Mode 1 cannot run a `.t` without
print) and is a real RF core feature. Order:
**R1 → R2.0 → R2 → R3 → R4 → R5 → R6**, with R7 spanning and the R1b chain
(Concat-Int-stringify → interpolating print) sequenced when the `$n` counter
idiom becomes the gating skip in R3/R4. R5/R6 (Mode 2) can proceed in parallel
with R4 once R1/R2 land (they share only the tri-fold adapter).

## Pushback findings applied (2026-07-17, paad:pushback + reality check)

The spec-quality gate ran against the codebase and corrected three items:

1. **[Serious/feasibility] Top-level program has no graph.** A t/base file is
   top-level statements; B::SoN emits `methods: {}` for a bare program. Added
   **R2.0** (wrap the body in `sub __main__`, producer untouched — perigrin).
2. **[Moderate/stale-dep] R1b named the wrong blocker.** multiconcat (019ee838)
   is DONE and irrelevant. In Chalk `"ok $n"` is COERCION not interpolation
   (perigrin): `Concat(Str, Coerce[Int→Str]($n))`, and the coerced Str HAS a
   length. The two real gaps: (a) producer doesn't emit the `Coerce[Int→Str]`
   (the `$n` PadAccess dangles, mis-folded to a Constant), (b) backend has no
   `Coerce[Int→Str]` arm. R1b corrected to depend on both.
3. **[Ambiguity] "Reuse run_through_bson" understated the delta.** R2 clarified:
   multi-line stdout comparison + NO epilogue type-tag + the R2.0 wrap — it is
   not a drop-in reuse.

Reality check otherwise clean: print confirmed absent (0 `_lower_print`, 0
`Print` node); the corpus gate confirmed to capture full stdout via `qx`.
