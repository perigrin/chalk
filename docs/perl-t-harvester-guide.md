# ABOUTME: Operational guide for the Perl t/ conformance harvester — how to run
# ABOUTME: Mode-1/Mode-2, read the skip histogram, and find the next feature to build.

# Perl t/ conformance harvester — operational guide

The harvester is an on-ramp DRIVER for the Phase-5 self-hosting capstone: it
harvests assertions from Perl's own `t/` suite into a tri-fold-gated corpus that
drives the loop, building core runtime-free (RF) semantics faster than the
hand-authored mdtest corpus. **Self-hosting `lib/` remains the definition of
done; this corpus is a driver, not the gate.**

Design + measurements: `docs/plans/2026-07-17-perl-t-conformance-harvester-PRD.md`.
Companion: `docs/codegen-harness-guide.md` covers the hand-authored mdtest gate;
`docs/architecture/runtime-free-boundary.md` covers the effect-by-default `Call`
classification and the RF `print`/`Stringify` host-effect notes (see the
cross-link below). This guide covers the harvester driver — the two harvest modes
and the skip-histogram worklist.

All harness modules live under `t/lib/Chalk/CodeGen/Harness/`. Run everything
with the pinned Perl: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl`.

## The GAP-not-silent-skip invariant

Every file/assertion the harvester cannot lower is a LOUD, COUNTED skip with a
named reason — never a silent pass or silent drop. The skip histogram (reason →
count) is a first-class output and IS the next-feature worklist: it tells you
which real Perl features unlock the most `t/` files.

Harvested conformance is tallied SEPARATELY from the hand-corpus gate-green
number (honest-number discipline): gate-green stays full-tri-fold only.

## Mode 1 — whole-file TAP oracle

A framework-free `.t` file already prints TAP, which is a machine-checkable
oracle. Mode-1 wraps the file body in `sub __main__` (`MainWrap.pm`), compiles it
B::SoN → from_json → LLVM → lli, strips the compiler epilogue tag
(`EpilogueStrip.pm`, robust known-epilogue compare — NOT a pattern strip), and
asserts lli stdout == perl stdout (full multi-line TAP).

Driver: `Mode1Runner.pm` — `run_file($t_path)` → `{verdict => PASS|SKIP|FAIL,
skip_reason?}`. `PASS` = stdout matches; `SKIP` = did not lower (named reason);
`FAIL` = lowered but MISMATCHED (a real miscompile — distinct from SKIP).

Run it: `... -Ilib -It/lib t/bootstrap/corpus/mode1-runner.t`.

### Reading the t/base construct-debt worklist

`TbaseWorklist.pm` drives Mode-1 over `~/dev/perl5/t/base/*.t` and produces a
per-file blocker table; the monotonic passing floor lives in
`t/bootstrap/corpus/tbase-worklist.t`. Run:
`... -Ilib -It/lib t/bootstrap/corpus/tbase-worklist.t` (emits the table as diag).

No stock t/base file lowers whole under the current RF slice — each is a counted
skip naming its FIRST unmet blocker (the real producer skip reason, not a guess).
The construct-debt signal as of the pinned SHA:

| file | first blocker |
|------|---------------|
| num.t, lex.t | list-context ternary |
| translate.t | cond_expr inside a loop body |
| while.t | loop control (`last`) inside a loop body |
| pat.t | PadAccess with no representation (TypeInference) |
| cond.t | `\|\|` LHS Bool needs Coerce→Bool |
| if.t | `StrNe` not lowered |
| rs.t, term.t | `die` inside a branch arm |

### Widening to more rings

`RingWorklist.pm` generalizes the worklist to Perl's ring order (base → cmd →
opbasic → cherry-picked comp; re/run/uni skipped). Each ring gets its own
monotonic floor. `t/comp` framework files (`use Test::More` / `require ./test.pl`)
are EXCLUDED (not silently failed) — `excluded(ring) + ringed == on-disk count`.
Run: `... -Ilib -It/lib t/bootstrap/corpus/ring-worklist.t`.

The combined cross-ring histogram is the ranked next-feature worklist. Top
signals as of the pinned SHA: top-level `__main__` GAPs and loop-condition
lowering unlock the most files, then `die`-in-arm, foreach-over-list,
list-context ternary, `undef(EXPR)`.

## Mode 2 — assertion extraction (Test::More files)

For `Test::More` files (whose framework Chalk cannot compile as a whole file),
`Mode2Extractor.pm` — `extract_file($path)` → `{cases, skips, histogram, total}`
— extracts each `is(EXPR, EXPECTED)` / `cmp_ok` / `ok` into a case record. Rules:
EXPECTED must be a compile-time literal (else counted-skip); SUBJECT must be
self-contained (its block-local `my` preamble is gathered, scope- and
mutation-aware so a mutated-after-binding lexical is a conservative skip, never a
wrong oracle); out-of-subset subjects (eval/open/fork/tie/format/typeglob/pack/
sprintf/syscall/XS/regex) are LOUD COUNTED skips. `harvested + skipped == total`
is asserted — no silent drops.

The `Mode2Adapter.pm` wraps extracted cases into the tri-fold runner: behavior
(lli == the harvested EXPECTED — the harvested value IS the oracle, no re-run of
perl) + invariant (TypedInvariant). Shape leg per contract C: harvested cases run
behavior+invariant only (no hand ir block); a gap-revealing case is PROMOTED into
the hand corpus with an `ir` block stamped `L: GAP` (uncertified until a human
authors the shape). The harvested-conformance tally is reported SEPARATELY and
never conflated with hand gate-green.

Run: `... -Ilib -It/lib t/bootstrap/corpus/mode2-extractor.t` and
`... t/bootstrap/corpus/mode2-adapter.t`. The dominant Mode-2 skip today is
`unresolved-lexical` (list-assign preambles) — closing that raises Mode-2 yield.

## Reproducibility

The corpus is harvested against Perl blead pinned at **`94e5086608`**, recorded
as the single source of truth in `HarvestPin.pm`. Vendor-vs-regenerate decision:
**regenerate-gated-on-SHA** — the corpus is not vendored; a harvest run must call
`HarvestPin::verify_checkout($perl5_path)` first, which LOUDLY fails if
`~/dev/perl5` HEAD ≠ the pin, is absent, or is dirty. Re-harvest is a deliberate,
reviewed step — never an implicit drift on a normal test run. See
`t/bootstrap/corpus/harvest-pin.t`.

## Cross-reference

The **effect-by-default classification** (every `Call` node is effect-pinned by
default, demoted to a pure floatable node only via the OpMap purity allow-list;
the correctness asymmetry is wrong-pure = silent miscompile, wrong-effect =
missed optimization) is documented in `docs/architecture/runtime-free-boundary.md`
alongside the `print`/`Stringify` RF-host-I/O notes. This guide points there
rather than duplicating it — that classification is the mechanism that makes
multi-statement program bodies (and thus Mode-1 whole-file lowering) faithful.
`docs/codegen-harness-guide.md` covers the hand-authored mdtest gate + the
harvester's pinned-SHA reproducibility.
