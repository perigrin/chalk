# G5a SoN-JSON Comparison — Baseline Verification (2026-05-02)

**Purpose:** Verify the SoN-JSON comparison harness functions correctly
post-Tier-A (issue #691 retired) and document the actual current state
versus what the 2026-05-01 handoff doc describes.

**Branch:** `g5a-baseline-verification`. Read-only verification — no code
changes, just observation and memory-note correction.

## Result

**86/86 file-level subtests pass.** Wall time ~9 minutes (547 seconds CPU,
single-process). Run command:

```bash
cd /home/perigrin/dev/chalk
PERL5_SON_LIB=$HOME/dev/perl5-son/lib \
  perl -Ilib -It/bootstrap/lib \
  $(which prove) -v --norc t/bootstrap/son-compare.t
```

`Result: PASS`. Exit code 0.

## What the harness actually tests

Per `t/bootstrap/son-compare.t`, for each `.pm` file in `lib/Chalk/IR/`:

1. B::SoN exits 0 (perl(1)'s optree-derived SoN JSON)
2. Chalk exits 0 (Chalk's IR-derived SoN JSON via
   `script/chalk-emit-son-json`)
3. B::SoN output is valid JSON
4. Chalk output is valid JSON
5. (When applicable) per-method op-class comparison: count nodes,
   compare op multisets, mark divergence

**All divergences wrapped as TODO** (`# TODO IR divergences expected`)
so the harness asserts the divergence catalogue rather than failing
on it. This **IS** the divergence-triage annotation mechanism the
handoff doc described as remaining work.

## Corpus scope (much larger than handoff doc claims)

Handoff doc (`docs/plans/2026-05-01-session-handoff.md` G5a section)
says:

> 6-file pilot run (2026-04-11) producing the divergence catalogue

Reality on 2026-05-02: the corpus is **86 files** — every `.pm`
under `lib/Chalk/IR/`. The pilot expanded sometime between 2026-04-11
and now (commit not investigated; fingerprint observable in
`t/bootstrap/son-compare.t`).

## Divergence catalogue — current

185 "exact match" / similar; ~100 TODO-wrapped "diverged" or
"missing" entries. Categories visible (matches the 2026-04-13 catalog):

- **B::SoN extras** (Perl optimizer generates, Chalk doesn't):
  PadAccess, FieldAccess, Defined, Proj
- **Chalk extras** (Chalk preserves, Perl folds):
  Call, Constant, VarDecl, Interpolate, Return, TernaryExpr, Concat,
  StrEq, PostfixDeref, Region, If, Not, Unwind

No new divergence categories at the larger scale. The expansion
from 6 → 86 files just produces more *instances* of the same
catalog entries.

## Stale claims now retired

The 17-day-old `son_comparison_divergences.md` memory note
(2026-04-13 status) said:

> 4/6 files fail Chalk-parse on `map { ... } LIST` — that is
> issue #691 territory, pre-existing.

This is fully retired post-Tier-A (Bug 4 fix, commit `1ec8cae1`,
plus A3 walker hygiene `fc4524ef` / `45d8c131`). All 86 files in
the current corpus parse cleanly through both pipelines.

Memory note updated to reflect 2026-05-02 state.

## What G5a's "remaining work" actually is

The handoff doc lists:

- Divergence-triage annotation mechanism — **already done**
  (TODO-wrapping is the mechanism)
- Corpus expansion from 6-file pilot to full `lib/` — **partially
  done** (86 files in `lib/Chalk/IR/*.pm` already; the next layer
  is expanding into `lib/Chalk/Bootstrap/*.pm` and `lib/Chalk/MOP/*.pm`,
  which use richer constructs — methods with side effects, signatures,
  control flow — and may surface new divergence categories)
- Decide whether `--emit-son-json` joins the codegen Target hierarchy
  — **still deferred** (per handoff doc, not blocking; couples to
  G4-Phase-4 cleanup)

What's actually next for G5a:

1. **Extend corpus into `lib/Chalk/Bootstrap/`** — the parser, semirings,
   actions, etc. Richer constructs will exercise more nodes. Expect
   new divergence categories (or new issues to fix in either pipeline).
   Pilot scope: e.g., `lib/Chalk/Bootstrap/Semiring/Boolean.pm` and
   `lib/Chalk/Bootstrap/Context.pm` first — they're small, have
   parser-relevant constructs, and parse cleanly.
2. **Defer `lib/Chalk/Bootstrap/Perl/Actions.pm` and similar** until
   G4-Phase-4 lands — large files where current parse cost is the
   binding constraint (C2 chart-memory-pressure perf-gate item).
3. **G5a-as-contract-proof** wants G4-Phase-6 (single-representation
   IR) before declaring the harness proves the IR contract.
   `compat_class` artifacts and the dual-write IR/MOP path are noise
   under that lens, but not blocking for the functional harness.

## Cross-references

- Memory note: `~/.claude/projects/-home-perigrin-dev-chalk/memory/son_comparison_divergences.md`
- Test: `t/bootstrap/son-compare.t`
- CLI: `script/chalk-emit-son-json`
- Handoff: `docs/plans/2026-05-01-session-handoff.md` (G5a section
  has stale "6-file pilot" framing that should be updated)
- Audit 3: `docs/plans/2026-04-25-audit-3-mop-ir-findings.md`
  (Phase 6 deletion scope informs the contract-proof story)
