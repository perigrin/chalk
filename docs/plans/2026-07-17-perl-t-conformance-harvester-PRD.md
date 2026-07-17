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
**R1 is a CORRECTNESS FIX, not just a feature (perigrin, verified 2026-07-17).**
`print` today is a live SILENT MISCOMPILE: `print "SIDE\n"; 42` lowers to a graph
with NO print node (producer ops: Start/Constant/Return only) — perl prints
`SIDE\nInt:42`, Chalk lli emits just `Int:42`. The print's side effect is
silently dropped.

**Root cause — a WRONG CLASSIFICATION DEFAULT (perigrin, verified 2026-07-17).**
The producer has a void-statement-effect path — a void-context node gets
`is_stmt_effect => true` and is pinned to the control chain
(`FromOptree.pm:993-1010`, gated on `OPf_WANT_VOID`). But that pinning is applied
per-site: **`entersub` (user-sub) calls reach it, but builtin listop/unop nodes
(`print`, `chomp`, `printf`, `warn`, …) do NOT** — they are built as floating
value nodes, so when their value is unused they are dropped and their effect is
LOST. This is Chalk's Sea-of-Nodes effect classification having the WRONG
DEFAULT: it defaults a `Call` to PURE (floatable, DCE-if-unused) and pins only
the ones a per-site check happens to reach. The safe polarity is the inverse
(see "Effect-by-default" below).

**The bug is a BROAD CLASS (measured), not IO-specific:**
- `print "SIDE\n"; 42` → `Start/Constant/Return` — print effect lost.
- `warn "W\n"; 1`, `printf "%d\n",5; 1` → effect lost.
- **`chomp $s; length $s` → `Start/Constant/Length/Return`** — the `chomp`
  MUTATION is lost; Chalk computes `length` of the un-chomped string (perl: 2;
  Chalk: wrong). A mutating builtin, not IO — proving the class is wide.
- `sideeffect(); 42` → `Call` PRESENT (survives) — confirming `entersub` IS
  correctly pinned; only the builtin-listop/unop sites are not.

### R1's fix: EFFECT-BY-DEFAULT, PURITY-BY-PROOF (perigrin)
The principled fix is not "route print (and then chomp, and then warn, …) one at
a time." It is to **invert the default**: build every `Call`-producing node as
effect-bearing (pinned, `is_stmt_effect`), and DEMOTE to a pure floatable data
node ONLY when purity is PROVEN. This matches LLVM (`readnone` is opt-in; a call
is effectful by default), GHC (`IO` is the default world, purity is earned), and
the Sea-of-Nodes construction discipline Chalk already follows. The asymmetry is
the whole point: a wrong "pure" default is a SILENT MISCOMPILE (what we have); a
wrong "effect" default is only a MISSED OPTIMIZATION (a pure call needlessly
pinned) — never wrong output. Correctness > performance, expressed as the IR's
classification policy.
- **Purity proof mechanism (initial):** an ALLOW-LIST of known-pure builtins
  (`uc lc ucfirst lcfirst fc quotemeta index rindex substr(rvalue) join sprintf
  pack unpack reverse length abs int sqrt …`) that MAY be demoted to floatable
  data nodes (so they keep hash-consing/CSE). Everything else — `print printf
  warn say chomp chop push pop shift unshift splice ++ -- entersub` and any
  unrecognized builtin/user call — stays effect-pinned by default. (A real
  purity analysis over user subs is a later refinement.)
- **Why this over the narrow fix:** it fixes `print` AND `chomp`/`warn`/`printf`
  AND every future builtin at once, and turns the question from "did we remember
  to pin this one?" (miscompile if forgotten) into "did we prove this one pure?"
  (slow if forgotten). It disarms the whole landmine field.

R1 delivers `print` end-to-end (the harvester's need) ON TOP OF this inverted
default, so the default flip is the load-bearing correctness change and print is
its first exercised instance.

NOTE: a `print`-lowering stub issue `019f6e1c` already exists (created before
this PRD); reconcile it during refinement — reframe it under this
effect-by-default correctness fix, or fold it into R1, rather than leaving a
duplicate.

`print LIST` must lower to real stdout. Today the backend only printf's the
single return value in the epilogue; there is no `Print` node in the producer
and no `_lower_print` in the backend. (Verified: `print` maps to a generic
`Call` in perl5-son `OpMap.pm:258`; not in `%STATEMENT_EFFECT_OPS`
`NodeFactory.pm:155`; no `Print` dispatch branch in `Context.pm:395-470`.)
- **R1.0 (EFFECT-BY-DEFAULT — the load-bearing correctness change)** Producer
  (perl5-son `SoN::FromOptree`): every `Call`-producing builtin/listop/unop node
  is constructed effect-pinned (`is_stmt_effect => true`) BY DEFAULT, not just at
  the `entersub` site. A node is DEMOTED to a floatable pure data node only if it
  is on the purity ALLOW-LIST. This fixes the whole class (print/chomp/warn/…) at
  the construction policy, not per-op.
  - **Acceptance:** `chomp $s; length $s` → the chomp effect survives (length 2,
    not 3); `sideeffect(); 42` still survives; a PURE call in value context
    (`my $x = uc($s)`) is still a floatable data node (no CSE regression — the
    allow-list demotes it). Bilateral: an effectful-and-unused call is KEPT; a
    pure-and-unused call is DROPPED (correct DCE).
- **R1.1** Producer: add a `print` listop handler emitting a `Print` node.
  Under R1.0 it is effect-pinned by default (print is NOT on the purity
  allow-list). Subject = the LIST of print args: **walk the whole
  `pushmark..print` span and emit each element**, not a single input.
  (`print "ok ", 1, "\n"` is `pushmark→const→const→const→print`.)
- **R1.1a** Consumer (Chalk): if the loader/scheduler keys statement-effects off
  `%STATEMENT_EFFECT_OPS` (`NodeFactory.pm:155`, currently Assign/CompoundAssign/
  RegexSubst/TryCatch/Call/RegexMatch/Match/NotMatch/BacktickExpr — no Print),
  add `Print` there so the consumer treats it as an effect. Verify whether it is
  needed (the node carries `is_stmt_effect` already).
- **R1.2** Backend (`lib/Chalk/Target/LLVM.pm`): `_lower_print` emits a libc
  write of the arg bytes to fd 1 (`write`/`fputs`/`printf` — the C-call declare
  path is proven; verify the exact line). Add an `elsif ($op eq 'Print')` branch
  in the op-dispatch chain (`LLVM.pm:~1555-1582`) alongside the RegexSubst arm
  (`LLVM.pm:~1679`). (NOTE: all LLVM lowering dispatch lives in
  `lib/Chalk/Target/LLVM.pm`, NOT a `Context.pm` — earlier `Context.pm:NNN`
  citations were wrong.)
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
    (`lib/Chalk/Target/LLVM.pm:~2055`; verified ~10 arms today, none Int→Str —
    falls through to `die`). It must
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
lowering is delivered by **R1.0's effect-by-default** — every `Call`/builtin node
is effect-pinned unless proven pure, so a sequence of top-level void prints (and
`chomp`s, and any effectful statement) all survive on the control chain. So R2.0
depends on R1 (specifically R1.0); the earlier blanket "producer untouched" is
WRONG and is replaced by: **R1.0 flips the construction default + R1.1 adds the
`Print` node.** (The `is_stmt_effect` mechanism already exists; R1.0 makes it the
default instead of a per-site opt-in.)
- **R2.0.1 (anti-statement-drop):** a wrapped body of N independent top-level
  void statements must produce a graph where ALL N are control-threaded (none
  dropped as a discarded value). **Testable at TWO layers:** (producer/graph)
  N top-level void statements → N `is_stmt_effect` nodes on the control chain
  (assertable before the backend exists); (behavioral) lli stdout equality.
- **Acceptance:** graph-level: `sub __main__ { print "a\n"; print "b\n";
  print "c\n"; }` yields 3 control-threaded Print nodes. Behavioral (once R1.2
  lands): lli stdout is `a\nb\nc\n` (NOT just `c\n`). An unwrapped bare program
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
  strips exactly the FINAL line, and only when it matches the compiler epilogue
  `^(Int|Num|Bool|Str|Undef):.*$` (NOT `Slot` — that is an internal repr never
  emitted as a top-level tag). Chosen over a backend `suppress_epilogue` flag to
  avoid a Target::LLVM change for a test-only need. **Scoped to Mode-1 t/base,
  where it is VERIFIED SAFE** (measured: no cond/if/num/pat/translate/while TAP
  line matches the pattern). **LOUD GAP for R4/R5 widening:** t/op Test::More
  descriptions can legitimately be `ok 5 - Str:foo roundtrip`, and the epilogue
  is currently exactly one line — a future multi-value return emitting >1 tag
  would break the single-line strip. Before R4/R5, replace pattern-matching with
  a robust scheme (sentinel-guarded epilogue channel, or compare against the
  known epilogue for the case's return value). (Rides on R1: until a wrapped body
  emits its own `print` stdout, the epilogue is the only output.) (Contrast: R1's
  hand-corpus cases KEEP the epilogue, since they test a returned value.)
- **R2.4** Invariant leg = TypedInvariant over the loaded graph(s).
- **R2.5** A file that fails to lower produces a LOUD, COUNTED skip naming the
  first unsupported construct — never a silent pass or silent drop
  (GAP-not-silent-skip invariant). The skip histogram is a first-class output.
- **Acceptance:** the runner passes end-to-end on a **synthetic literal-only
  top-level-print `.t`** (`print "1..3\n"; print "ok 1\n"; print "ok 2\n";
  print "ok 3\n";` — the ONLY shape R1 alone handles; this is what R2.0.1 tests)
  and loud-skips a miniperl-exceeding file (`lex.t`) with a named reason.
  **NO stock t/base file passes under R1 alone** (see R3) — the synthetic file
  is the first real acceptance.

### R3 — Mode 1 proving ground: t/base
Run Mode 1 over t/base (Perl's authoritative first ring). **CRITICAL correction
(reassess round 3): NO stock t/base file is purely top-level literal prints.**
My round-2 "top-level vs `&&`-arm" split was on the wrong axis — I counted `^print`
lines, but every file's ASSERTION prints need more than R1. Per-file construct
debt (measured @94e5086608), each mapped to its blocking requirement:

| file | assertion-print shape | blocked on |
|------|----------------------|-----------|
| num.t | `print $cond ? "ok N\n" : "not ok N # $a\n"` (ternary arg + string-eq + package `$a` + coercion) | R1(ternary-arg) + R1b + string-eq + package-scalar |
| translate.t | `print $i+1 . " - ... $i"` inside a `for` loop | R1b (Concat+Int→Str) + loop-body + R1(list) |
| while.t | `ok N` inside `if(){}else{}` blocks | if-block void-print threading (R2.0.3) |
| pat.t | prints inside if/else; uses `//` regex | R2.0.3 + regex (PARKED) |
| cond.t | 8 prints in `&&`/`||` arms | R2.0.2 |
| if.t | 2 prints in if-blocks | R2.0.3 |

So t/base is NOT reachable under R1 alone. The honest sequence: R1 lands
(synthetic file passes) → then the blockers above land one at a time, each
UN-skipping its files. Each blocker is a NEW named requirement, NOT assumed:
**R2.0.3** (void print statement inside an if/else/loop BLOCK body — distinct
from R2.0.2's logical-op arm; if/else already builds Region/Phi per RC5, so this
is void-effect threading inside an existing Block), plus **string-eq**,
**package-scalar reads**, and **ternary-valued print args** as their own GAPs.
- **Acceptance:** each t/base file either PASSes (once ALL its listed blockers
  land) or produces a counted skip naming its FIRST unmet blocker from the table.
  No file is claimed to pass before its blockers land. No silent drops. A
  monotonic floor locks the passing count (starting at 0 stock files, +synthetic).

### R2.0.3 — void statement inside an if/else/loop BLOCK body (GAP, filed)
Distinct from R2.0.2 (logical-op arm). A `print` that is a statement inside an
`if(){}else{}` or loop block body. Chalk already builds if/else with Region/Phi
(RC5); this is threading a void effect inside that Block. Empirically confirm
whether it already threads under R1 before assigning it as a blocker — it may be
partially free.
- **Acceptance:** `if ($c) { print "a\n" } else { print "b\n" }` fires the
  correct branch's print; bilateral (both arms).

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

R1 is the FIRST BRICK, and **R1.0 (effect-by-default) is its load-bearing
correctness change** — it gates R2.0 (faithful multi-statement lowering depends
on effect-pinning; without it the wrap miscompiles) and fixes a broad silent-
miscompile class (print/chomp/warn/… all drop today). Order:
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

## Re-assess round 3 findings applied (2026-07-17, dual independent critics)

Both critics returned clean=FALSE and CONVERGED on the same critical + serious
finding. All applied:

1. **[CRITICAL] R2/R3 had no reachable real-file pass candidate.** My round-2
   "top-level-print" reclassification was on the WRONG axis — I counted `^print`
   lines, but every stock t/base file's ASSERTION prints are ternary-arg
   (num.t), loop-body+coerced (translate.t), or if-block (while.t/pat.t/if.t) —
   all blocked. NO stock t/base file passes under R1 alone. Fix: R2's first
   acceptance is a SYNTHETIC literal-only file; R3 got a per-file construct-debt
   table mapping each file to its blockers; added R2.0.3 (if/else/loop block-body
   void print) + named GAPs (string-eq, package-scalar, ternary-arg).
2. **[SERIOUS] `%STATEMENT_EFFECT_OPS` mechanism was wrong.** That hash is a
   Chalk CONSUMER table (`NodeFactory.pm:155`); the perl5-son PRODUCER uses a
   per-site `is_stmt_effect` flag gated on `OPf_WANT_VOID`. Verified the real
   defect: `print` is an `OP_LIST` listop that never reaches the void-Call
   construction branch, so its effect node is never built (not "DCE'd from a
   hash"). R1.1 rewritten to the real mechanism; added R1.1a (consumer table).
3. **[MODERATE] Stale `Context.pm:NNN` citations** — all LLVM dispatch is in
   `lib/Chalk/Target/LLVM.pm` (RegexSubst ~1679, dispatch ~1555, `_lower_coerce`
   ~2055). Fixed R1.2, R1b-b.
4. **[MODERATE] R2.0.2 conflated logical-arm with if-block.** Split: R2.0.2 =
   `&&`/`||` arm; new R2.0.3 = if/else/loop block body.
5. **[MODERATE] R2.3b strip unbounded for R4/R5.** Scoped to t/base (verified
   safe), dropped `Slot`, flagged as a LOUD GAP requiring a robust scheme before
   R4/R5 widening.
6. **[MINOR] R2.0.1 not producer-testable** — added a graph-level assertion
   (N void statements → N control-threaded nodes) alongside the stdout check.

## Effect-by-default reframe (2026-07-17, perigrin)

Prompted by "do other languages do purity analysis like escape analysis but for
side effects?" — yes: effect systems (Koka/GHC `IO`), purity attributes (LLVM
`readnone`, GCC `__attribute__((pure/const))`), and Sea-of-Nodes effect-chain
pinning. All make the OPTIMIZATION opt-in and EFFECT the default. Chalk had it
backwards (default pure, pin a per-site list), which is why print/chomp/warn
silently dropped. perigrin's fix: **default all `Call` nodes to effect-bearing;
prove purity (allow-list, later real analysis) to demote.** This became R1.0 —
the load-bearing correctness change — and it dissolves the whole
silent-effect-drop class (MEASURED: `chomp $s; length $s` drops the mutation
today) rather than patching print alone. Asymmetry rationale: wrong-pure =
silent miscompile; wrong-effect = missed optimization. Correctness > performance.
