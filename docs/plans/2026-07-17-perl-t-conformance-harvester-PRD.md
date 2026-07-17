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

### R1 — print-to-stdout lowering (literal LIST, bare STDOUT) [FIRST BRICK]
`print LIST` must lower to real stdout. Today the backend only printf's the
single return value in the epilogue; there is no `Print` node in the producer
and no `_lower_print` in the backend. (Verified: `print` maps to a generic
`Call` in perl5-son `OpMap.pm:258`; not in `%STATEMENT_EFFECT_OPS`
`NodeFactory.pm:155`; no `Print` dispatch branch in `Context.pm:395-470`.)
- **R1.1** Producer (perl5-son `SoN::FromOptree`): a `print` handler emits a
  `Print` IR node and ADDS `Print` to `%STATEMENT_EFFECT_OPS` (so it gets
  per-call identity + Block control-threading, exactly as RegexSubst does — this
  threading is load-bearing for R2.0, see there). Subject = the LIST of print
  args: **walk the whole `pushmark..print` span and emit each literal element**,
  not a single input. (`print "ok ", 1, "\n"` is `pushmark→const→const→const→
  print` — multiple stack args.)
- **R1.2** Backend (`Chalk::Target::LLVM`): `_lower_print` emits a libc write of
  the arg bytes to fd 1 (`write`/`fputs`/`printf` — the C-call declare path at
  `LLVM.pm:1085` is proven). Add an `elsif ($op eq 'Print')` branch alongside
  the RegexSubst branch (`Context.pm:418`).
- **R1.3** Ordering: `print` output precedes the epilogue `TYPE:value` line, on
  both the perl oracle and lli sides (the corpus gate captures full stdout via
  `qx` — verified `son-corpus-wide.t:83` lli, `:101` oracle, byte-compared
  `:145`). `print "hi\n"; 1` → combined stdout `hi\nInt:1`.
- **R1.4** `print` returns `1` (its own truth value) — usable as a value.
- **R1.5 (LOUD GAP)** The filehandle form (`print STDOUT ...`, `print $fh ...`)
  has a different optree (`gv[*STDOUT]→rv2gv`, flags `vKS`) and is a LOUD COUNTED
  skip in R1 — bare-STDOUT `print LIST` only. Without this a `print STDOUT "x\n"`
  would silently misroute. (t/base/cond.t is bare `print`, safe; R3/R4 widening
  will hit STDOUT-qualified prints — hence the explicit GAP.)
- **R1.6** `$,` (output field sep) and `$\` (output record sep) are assumed
  default (empty) for the literal slice; a t/base file that sets them is a named
  GAP.
- **Acceptance:** hand-corpus cases at FULL tri-fold (behavior+shape+invariant),
  bilateral: bare-literal print; print-LIST (multiple args); print-then-return;
  **two-prints-ordering (BOTH survive — `print "a\n"; print "b\n"; 1` →
  `a\nb\nInt:1`, the anti-statement-drop check)**; print-as-value(1); and a
  `print STDOUT` case that loud-GAPs. Corpus gate-green floor rises; worklist=0.
- **Out of scope (R1):** `print` of a COERCED value (`print "ok $n\n"`) — needs
  the Int→Str coercion gaps in R1b. Filed as R1b, not R1. (NOT a multiconcat
  dependency — see R1b's correction.)

### R1b — print with a coerced value (`print "ok $n\n"`)
The counter idiom pervasive in t/base. In Chalk this is NOT interpolation — it
is COERCION (perigrin): `"ok $n"` is `Concat(Str "ok ", Coerce[Int→Str]($n))`,
and the coerced Str carries a string length like any other Str. So there is no
"Int has no length" problem — the Int is coerced to a Str which HAS a length.
- **CORRECTED (pushback + reassess + perigrin, verified 2026-07-17):** NOT
  blocked on multiconcat (019ee838 is DONE; the decoder correctly produces plain
  `Concat` nodes for `"ok $n"`). The target model is coercion, but perl5-son has
  **NO Coerce node type at all** (verified: `lib/SoN/IR/Node/` has `Concat.pm`,
  `Interpolate.pm`, `Stringify.pm` — no `Coerce.pm`). So this is NOT "wire an
  existing Coerce"; it is a two-repo core feature. Two deliverables, sized
  honestly:
  - **R1b-a (producer, perl5-son):** add an Int→Str coercion node (or reuse the
    existing `Stringify`) and wire the interpolation decoder to emit
    `Concat(Str, Coerce[Int→Str](operand))` for BOTH foldable and dynamic
    operands. Measured today: a foldable `$n` folds to a bare `Constant` (no
    wrapper); a dynamic operand is consumed RAW by `Concat` with no Int→Str
    wrapper. Acceptance: node dump shows the wrapper present, no raw Int operand
    into `Concat`.
  - **R1b-b (backend, chalk):** add the `Coerce[Int→Str]` arm to `_lower_coerce`
    (verified: 10 arms today, none Int→Str — falls through to `die`). It must
    BOTH emit the decimal digits AND record the **runtime** length in
    `_str_len_table` (the length is the integer's digit count, computed at
    runtime — this is the non-trivial part; there is no "Int has no length"
    problem, but the length is dynamic, not static). Acceptance: `Coerce[Int→Str]`
    lowers to digits + a runtime length ref.
  Both are SEPARATE prerequisites (useful beyond print); R1b (print of a coerced
  value) blocks behind both.
- **Acceptance (R1b end-to-end):** `my $n=3; "ok $n"` → `Str:ok 3` (tri-fold);
  then `print "ok $n\n"` → `ok 3\n` on stdout.

### R2.0 — source-prep: wrap the body in a sub AND thread the statement sequence
A `t/base` file is TOP-LEVEL statements, not a `sub`. Two facts, both verified
2026-07-17:
- B::SoN emits `methods: {}` for a bare program body — no lowerable graph. So
  the body must be wrapped in a synthetic `sub __main__ { ... }` before B::SoN
  (reusing the `corpus_case`-wrap the harness proves, `son-corpus-wide.t:52`).
- **BUT the wrap ALONE yields a MISCOMPILE (reassess-critical finding).** B::SoN
  lowers a `sub` body as a value-returning method that keeps ONLY the last
  statement threaded into `Return`; preceding VOID statements not captured
  through control flow are silently dropped. MEASURED: `sub __main__ { print
  "1..2\n"; print "ok 1\n"; print "ok 2\n"; }` lowers to 4 nodes (Start,
  Constant, ONE Call, Return) — the plan line and `ok 1` are GONE. A gate that
  accepted "a graph exists" would report GREEN on a graph that runs one print,
  not the test.

**Resolution (supersedes "Producer untouched"):** faithful multi-statement
lowering is delivered by **R1's effect-op threading** — adding `Print` to
`%STATEMENT_EFFECT_OPS` gives each `print` statement a control edge, so a
sequence of top-level void prints all survive (same mechanism that keeps a
sequence of `Assign`s). So R2.0 depends on R1; the earlier blanket "producer
untouched" is WRONG and is replaced by: **no NEW producer node types beyond
R1's `Print`** (the wrap is source-prep; the threading is R1's Print effect-op).
- **R2.0.1 (anti-statement-drop):** a wrapped body of N independent top-level
  void statements must produce a graph where ALL N are control-threaded (none
  dropped as a discarded value).
- **Acceptance:** `sub __main__ { print "a\n"; print "b\n"; print "c\n"; }`
  lowers so lli stdout is `a\nb\nc\n` (NOT just `c\n`). An unwrapped bare program
  correctly yields no graph (documents why the wrap is needed).
- **KNOWN GAP (measured):** a `print` in a logical short-circuit ARM
  (`$x==$x && (print ...)`) or a statement-modifier (`print ... if ...`) is a
  DISCARDED-VALUE expression, not a top-level statement — the producer drops it
  even with R1's threading (verified: cond.t's 8 `&&`/`||`-arm prints yield a
  3-node Start/Constant/Return graph). Effect-threading a void print nested in a
  logical-op arm is a SEPARATE requirement (R2.0.2 below), filed as a GAP, NOT
  assumed by R2.0.

### R2.0.2 — void effect inside a logical short-circuit arm (GAP, filed)
`EXPR && (print ...)` / `EXPR || (print ...)` — the print is the RHS arm of a
logical op, evaluated for effect but modeled as a discarded value and dropped.
This blocks cond.t and the `&&`/`||`-arm assertion idiom. Filed as a named GAP;
R3 does NOT depend on it (R3 picks top-level-print files instead).
- **Acceptance:** `$x==$x && (print "y\n")` fires the print when the condition
  is true; a bilateral case where it does NOT fire when false.

### R2 — Mode 1 whole-file oracle runner
A test harness that, given a framework-free `.t` path, wraps it (R2.0), compiles
through B::SoN → from_json → LLVM → lli, and asserts lli stdout == perl stdout.
- **R2.1** Reuse the `run_through_bson` pipeline SHAPE (source → JSON → graph →
  LLVM → lli), but with the deltas below — it is NOT a drop-in reuse.
- **R2.2** Behavior leg = **full MULTI-LINE stdout equality** (a TAP stream is
  many lines), not the chomped single-line repr `run_through_bson` compares.
- **R2.3** **NO epilogue type-tag.** A `.t` file's real output is raw TAP
  (`ok 1\n`), not `Int:1`. The epilogue is hard-baked into
  `Target::LLVM::lower_with_elaboration` (`LLVM.pm:1244-1345`) with no suppress
  seam (opts carries only `mop`), so this is NOT a pure harness instruction.
  **DECISION (R2.3b — runner-side strip, no backend change):** the Mode-1 runner
  strips a single trailing `^(Int|Num|Bool|Str|Undef|Slot):.*$` epilogue line
  from lli stdout before comparison. Chosen over a backend `suppress_epilogue`
  flag to avoid a Target::LLVM change for a test-only need. (Rides on R1: until a
  wrapped body can emit its own `print` stdout, the epilogue is the only output —
  nothing to strip.) (Contrast: R1's hand-corpus cases KEEP the epilogue, since
  they test a returned value alongside the print.)
- **R2.4** Invariant leg = TypedInvariant over the loaded graph(s).
- **R2.5** A file that fails to lower produces a LOUD, COUNTED skip naming the
  first unsupported construct — never a silent pass or silent drop
  (GAP-not-silent-skip invariant). The skip histogram is a first-class output.
- **Acceptance:** the runner passes on ≥1 fully-in-subset t/base file end-to-end
  whose assertions are TOP-LEVEL prints (candidate: `num.t`, `translate.t`, or
  `while.t` — NOT `cond.t`/`if.t`, whose prints are `&&`-arm/if-block, blocked on
  R2.0.2) and loud-skips a miniperl-exceeding one (`lex.t`) with a named reason.

### R3 — Mode 1 proving ground: t/base
Run Mode 1 over t/base (Perl's authoritative first ring). Measured 2026-07-17,
6/9 files in-subset (cond, if, num, pat, translate, while; lex/rs/term
loud-skip), further split by print SHAPE:
- **Top-level-print (R1 handles): `num.t` (60 top-level prints, 0 arm),
  `translate.t` (8/0), `while.t` (3/0), `pat.t` (1/0).** These are the real first
  candidates.
- **Arm/if-block-print (needs R2.0.2): `cond.t` (8 `&&`/`||`-arm), `if.t` (2 in
  if-blocks).** Blocked on R2.0.2; loud-skip until it lands.
- **Acceptance:** each top-level-print file PASSes (stdout==perl) or produces a
  counted skip naming the missing feature; the arm-print files loud-skip citing
  R2.0.2. No silent drops. A monotonic floor locks the passing count.

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

R1 (print + `Print` effect-op threading) is the FIRST BRICK — it gates R2.0
(faithful multi-statement lowering DEPENDS on R1's effect-threading; the wrap
alone miscompiles) and R2, and is a real RF core feature. Order:
**R1 → R2.0 → R2 → R3 → R4 → R5 → R6**, with R7 spanning. Two side-chains,
sequenced when they become the gating skip:
- **R2.0.2** (void print in `&&`/`||` arm) — gates cond.t/if.t; parallel to R3.
- **R1b-a → R1b-b → R1b** (add Coerce node → backend Int→Str arm → coerced
  print) — gates the `print "ok $n\n"` counter idiom.
R5/R6 (Mode 2) can proceed in parallel with R4 once R1/R2 land (they share only
the tri-fold adapter).

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

## Re-assess round 2 findings applied (2026-07-17, 4 feasibility probes + critique)

Re-ran assess against the corrected PRD (perigrin: "until a clean bill of
health"). The critique returned **clean=FALSE** with 8 findings; all applied:

1. **[CRITICAL] R2.0 wrap-alone is a MISCOMPILE.** Wrapping a void-statement
   sequence in a sub keeps only the last statement (measured: 3 prints → 1
   Call). R2.0 rewritten to require FAITHFUL lowering via R1's `Print`
   effect-threading; added R2.0.1 (anti-statement-drop acceptance).
2. **[SERIOUS] "Producer untouched" self-contradiction.** Faithful lowering
   needs R1's producer change, so "untouched" was false. Replaced with "no NEW
   producer node types beyond R1's Print."
3. **[SERIOUS] print-in-`&&`-arm dropped (measured).** cond.t's 8 arm-prints →
   3-node graph. Added R2.0.2 (GAP) and moved R3's pass candidate off cond.t/if.t
   onto the top-level-print files (num/translate/while).
4. **[MODERATE] R1b stale "residual multiconcat" attribution.** perl5-son has NO
   Coerce node at all. R1b split into R1b-a (add node + wire decoder) and R1b-b
   (backend arm + runtime length), sized honestly.
5. **[MODERATE] R1 singular-arg model.** Changed to LIST (walk pushmark..print);
   added R1.5 (filehandle-form GAP) and R1.6 (`$,`/`$\` GAP).
6. **[MINOR] R2.3 suppress mechanism unstated.** Decided R2.3b: runner-side strip
   of the epilogue line (no backend change).

Probe verdicts: R1 FEASIBLE (with LIST/filehandle caveats now in R1); R2.0
FEASIBLE_WITH_CAVEAT (the statement-drop, now R2.0.1); R1b FEASIBLE_WITH_CAVEAT
(no Coerce node, now R1b-a/b); R2.3 = runner-strip.
