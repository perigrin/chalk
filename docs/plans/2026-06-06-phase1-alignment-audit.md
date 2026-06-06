# Phase 1 Codegen-Harness Alignment Audit

**Date**: 2026-06-06
**Auditor role**: read-only plan-vs-code alignment auditor (no fixes; punch list only)
**Branch**: phase1-lateral-bindings
**Question**: Does the BUILT codegen-harness match what the converged plan + architecture
docs SPECIFIED, measured against the staged ACCEPTANCE CRITERIA — not "tests pass"?
**Claim under audit**: "Phase 1 done / tier-1 green."

## Oracle discipline (named up front)

- **Plan oracle**: `2026-06-05-codegen-harness-and-idiom-corpus.md` "Acceptance criteria
  (staged)" §93-104; architecture C1-C8 §60-87; the 7 invariants are sourced from the
  architecture "Review corrections" §110-125 and the plan's CRITICAL guard §15
  (the named `2026-06-06-codegen-harness-chain-review-regenerated.md` from the brief
  **does not exist** in `docs/plans/` — see Drift D-0).
- **External oracle**: real perl 5.42.0 via the harness's own `RunUnderPerl` path
  (used for behavioral spot-checks below).
- **Internal-invariant oracle**: behavioral equivalence of `next`-present vs
  `next`-absent loop bodies (used to confirm the M17/M18 false-green).

Tests in `t/bootstrap/codegen-harness/*.t` are treated as regression guards, NOT
correctness oracles (they were written alongside the harness).

---

## Per-question verdict table

| Q | Topic | Verdict | Key evidence |
|---|-------|---------|--------------|
| 1 | Stage-1: widened-record harness, all C2 axes with written policies, coverage-organized gap map | **PARTIAL** | All 10 axes have fields + written policies in `BehaviorRecord.pm:8-157`; but 3 axes (`object_state`, `aliasing_topology`, `dualvar` divergence path) are **never populated by the oracle** — `RunUnderPerl.pm:185,189` hardcodes `object_state => {}` and `aliasing_topology => {}`. Policy-without-exercise = latent, not active. |
| 2 | Stage-2(tier-1): tier-1 actually green; definition sound; DEFERRED/REJECT not a loophole; D5 guard | **VERIFIED** | Live `tier1_green()` returns TRUE: 76 PASS + 1 DEFERRED (M20) + 1 REJECT (M21), denom 78. Definition (`GapMap.pm:180-196`) excludes only registry-listed REJECT/DEFERRED; ordinary NOT-YET-COVERED still returns false (`:192`). |
| 3a | perl is SOLE oracle | **VERIFIED** | `Harness.pm:117-129` S=RunUnderPerl, P=PerlDriver; Comparator never reads stored/golden output. `ag golden\|prior\|expected` over harness = none. |
| 3b | gap-vs-MISCOMPILE classifier present + load-bearing | **VERIFIED** | `Comparator.pm:38-122` checks emission_meta FIRST (GAP), then degenerate-collusion guard (`:56`), then per-axis divergence → MISCOMPILE. |
| 3c | C corner correctly NOT built in Phase 1 | **VERIFIED** | No C driver in harness dir; `Target::C->generate` remains the documented stub; plan gates C behind Stage 3 §85, §102. |
| 3d | zero out-of-scope work | **VERIFIED** | No SemanticAction/B::SoN/parser-bridge/subset-enforcement touched on-branch; emitter changes are all corpus-greening (see Q4). |
| 3e | hand-author graphs directly, never `from_json` | **VERIFIED** | `ag from_json HandGraphs.pm` = ZERO; builders use `NodeFactory`/`make`/`make_cfg` directly. |
| 3f | widened record with written policies | **PARTIAL** | Same as Q1: policies written, but 3 axes inert. |
| 3g | determinism (C8) gate present | **PARTIAL** | `wire-determinism.t` exists and passes, but covers only A1/A4/A5 (3 of 76 PASS) + a self-referential perturbation test; C8 is NOT wired into the per-entry verdict path (`run_entry`/`PerlDriver`/`GapMap`). |
| 4 | scope drift in emitter changes | **VERIFIED (in-scope)** | E1 fix, ADJUST emission, foreach `$_`, ListAssign are all "complete CodeGen idiom-by-idiom with perl as spec" (plan §78-79). No change observed beyond making corpus idioms green. |
| 5 | acceptance-vs-commit honesty (any glossed criterion) | **DRIFT** | Two glosses: (D-1) M17/M18 PASS is a laundered miscompile — `next`/`last` is dropped from emitted code and the corpus body can't observe it; (D-2) determinism "preserved" is asserted but only 3/76 idioms are checked. |
| 6 | deferred items tracked with location | **VERIFIED** | M20 → `%DEFERRED_REASONS` + scope-decision doc + issue 019e9b4a; M21 → REJECT registry + policy cite; I1 done; C corner → Stage 3. K2/M19 resolved. |

---

## Stage-1 acceptance checklist (plan §93-95)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Repeatable harness `program → perl(S)` vs `program → Perl-codegen → run(P)` | **MET** | `Harness.pm:106-136` `run_entry`; `GapMap::generate` iterates all 78 live. |
| Diffs on the widened behavior record (all 10 C2 axes) | **PARTIAL** | Comparator compares 6 axes actively (`Comparator.pm:69-104`: wantarray, stdout, stderr, exception, return_values, object_state). `object_state` is compared but always `{}` on both sides (oracle never fills it). `aliasing_topology` has accessor + policy but is **not compared at all** in `verdict()`. `dualvar`/`fp` policies exist but the oracle always emits `dualvar_policy => 'numeric-first'` while `_return_values_equal` only branches on `'numeric'`/`'string'` (`Comparator.pm:180-193`) — `'numeric-first'` falls to the default exact-eq path, so the documented dualvar policy is **never executed**. |
| perl (S) is the sole oracle | **MET** | See Q3a. |
| Gap map organized by category/coverage over full A-M/78 denominator | **MET** | `gap-map.json` summary `by_group` A-M, `denominator: 78`; coverage-organized, not frequency. |

**Stage-1 net**: instrument exists and is repeatable (MET), but the "widened record"
is widened in *schema* more than in *behavior*. 6 of 10 axes are live; `object_state`
is structurally inert (always empty), `aliasing_topology` is uncompared, `dualvar`'s
own default token is unhandled, `fp_tolerance` only fires under `'numeric'` which the
oracle never sets. For the current tier-1 corpus (scalar/int returns, stdout, stderr,
exceptions) the live axes are sufficient — but the architecture made the widened record
"load-bearing … else false greens" (§105, §114, §124), and four axes are latent escapes.

## Stage-2(tier-1) acceptance checklist (plan §97-100)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Tier-1 all-green (S=P) by COMPLETING CodeGen, perl as spec | **MET (with D-1 caveat)** | `tier1_green()` = TRUE live; 76 PASS verified against perl. Caveat: M17/M18 PASS is behaviorally vacuous (D-1). |
| Determinism preserved (byte-identical Perl codegen) | **PARTIAL** | `wire-determinism.t` passes for A1/A4/A5 only; not asserted across the 76 PASS set; not wired per-entry. |
| Subset-rejection NOT owned here (PAAD F-N1) | **MET** | M21 REJECT is a *classification* label, not enforcement; matches §100. |

---

## DRIFT and glossed criteria (the most important output)

### D-0 — Named chain-review document does not exist
The brief names `docs/plans/2026-06-06-codegen-harness-chain-review-regenerated.md`
as the source of "the 7 invariants the build must preserve." That file is **absent**
from `docs/plans/`. The 7 invariants were reconstructed from the architecture doc's
"Review corrections" (§110-125) and the plan's CRITICAL guard (§15), which cover the
same content. **Impact**: low for this audit (invariants verifiable from the extant
docs), but an unlabeled-missing-artifact: either the chain review was never written,
was deleted, or lives under a different name. Recommend confirming before Phase 2
cites it.

### D-1 — M17/M18 PASS is a laundered miscompile (HIGH)
**Trigger / minimal failing case**: corpus M17 = `foreach my $n (1,2,3) { next if $n == 2; } return 1;`
**Site**: `HandGraphs.pm:3328-3358` (`_build_M17`, mirror `_build_M18`); emitter scheduler
path in `Target/Perl.pm`.
**Layer responsible**: emitter (scheduler path) — the `is_loop_jump` field on
`Chalk::Scheduler::EagerPinning::If` is never read by `_emit_schedule_item`.
**Evidence** (probe, perl 5.42 oracle):
- Generated P for M17 is:
  ```
  for my $n (1, 2, 3) {
      if ($n == 2) {
      }
  }
  return 1;
  ```
  The `next` statement is **dropped entirely** — emitted body is an empty `{}`.
- Behavioral equivalence probe: `corpus_next()` (with `next if`) returns 1;
  `corpus_empty()` (with `if(){}`) returns 1. Identical, because the corpus loop body
  has no side effect that `next` would alter (only `return 1` AFTER the loop).
- Contrast probe: with a body side effect (`$c++`), `next`-present returns 2,
  `next`-absent returns 3 — i.e. the drop IS observable in general, just not in THIS
  corpus.
This is exactly the gap-vs-miscompile launder the architecture's round-2 HIGH risk
(§122) and the pushback review (`2026-06-06-phase1-audit-pushback-review.md:109-117`)
warned about. The hand graph asserts `is_loop_jump => 'next'`, the emitter silently
ignores it, the behavior record cannot observe the difference, and the verdict is PASS.
The green status hides that **codegen does not emit `next`/`last` at all** on the
scheduler path.
**Suggested remediation shape** (NOT done here): either (a) widen the M17/M18 corpus +
hand graph so the loop body has an observable side effect that `next`/`last` changes
(forces the emitter gap to surface as a real divergence), or (b) make
`_emit_schedule_item` read `is_loop_jump` and emit the jump statement, then re-verify.
Until one of these lands, M17/M18 should arguably carry a NOT-YET-COVERED or a tracked
known-limitation rather than PASS.
**Side effects of a fix**: option (a) changes the corpus denominator semantics for two
idioms; option (b) touches the live scheduler emit path used by every control idiom —
must re-run the full 76 to confirm no regression.

### D-2 — "Determinism preserved" is asserted on 3 of 76 idioms (MEDIUM)
**Site**: `wire-determinism.t:13-70` (A1/A4/A5 only); `:72-91` T4 is a self-referential
test that appends a space to a string the test itself constructs — it verifies `isnt`
works, not the emitter.
**Layer**: harness (C8 gate).
**Evidence**: C8 is specified as a per-entry double-emit byte-compat check
(architecture §85-86, data-flow §91 step 3). The built C8 is a standalone 3-idiom test,
not wired into `run_entry`/`PerlDriver`/`GapMap` (`ag` for double-emit in those files =
none). The Stage-2 criterion "Determinism preserved (byte-identical Perl codegen)" is
therefore met for 3 idioms and unverified for the other 73 PASS idioms.
**Suggested remediation shape**: loop the double-emit assertion over all PASS tags in
the gap-map path, or add a determinism axis to the per-entry verdict.
**Side effects**: none behavioral; pure test-coverage widening.

### D-3 — Four behavior-record axes are latent (declared, not exercised) (MEDIUM)
**Sites**: `RunUnderPerl.pm:185` (`object_state => {}` hardcoded — the driver never
introspects post-call field values), `:189` (`aliasing_topology => {}` hardcoded);
`Comparator.pm` `verdict()` never compares `aliasing_topology`; `:180-193`
`_return_values_equal` handles `'numeric'`/`'string'` but the oracle always sets
`dualvar_policy => 'numeric-first'` (`RunUnderPerl.pm:188`), which hits the default
exact-eq branch — the dualvar numeric-face policy never runs; `fp_tolerance` only
applies under `'numeric'`, also never set.
**Layer**: oracle (RunUnderPerl) + comparator.
**Evidence**: code reads above; no tier-1 corpus idiom returns a float, a dualvar, a
shared-aliased ref topology, or asserts post-call object state, so the gap is currently
masked — but the plan made these axes load-bearing precisely to catch the idioms a
*later* corpus tier will introduce. Filed as a gap, not a Phase-1 blocker (tier-1 doesn't
exercise them), but it must not be summarized as "the widened record is built and
working."
**Suggested remediation shape**: populate `object_state` via invocant introspection in
the driver; add an `aliasing_topology` comparison branch; make `'numeric-first'` an
executed policy in `_return_values_equal`. Best done when Stage-2 tier-2/tier-3 adds
idioms that actually return floats/objects.

---

## Surveys

### C1-C8 component build status

| Comp | Spec | Built? | Location / note |
|------|------|--------|-----------------|
| C1 | Corpus entry + exercise spec + classification + graph-source tag | **YES** | `Harness.pm:18-95` %CORPUS; `GapMap::_spec_for`; classification via REJECT/DEFERRED registries. |
| C2 | Widened behavior record (10 axes) | **PARTIAL** | `BehaviorRecord.pm` — all fields + policies present; 4 axes latent (D-3). |
| C3 | Run-under-perl oracle | **YES** | `RunUnderPerl.pm` capture/capture_sub; zero Chalk dep on S path. |
| C4 | Pluggable graph-source (hand/chalk-parser/bson) | **PARTIAL (by design)** | Only `hand` built (`HandGraphs.pm`); chalk-parser/bson are named slots, correctly deferred per plan. |
| C5 | Codegen drivers (Perl + C) | **PARTIAL (by design)** | Perl driver built (`PerlDriver.pm`); C driver correctly deferred (Q3c). |
| C6 | Graph-loader adapter (JSON→MOP) | **NOT BUILT (correct)** | Plan §113 says hand root builds MOP directly; loader only needed for deferred bson. Absence is alignment-correct. |
| C7 | Triangle comparator + gap/miscompile classifier | **YES (S-vs-P only)** | `Comparator.pm`; triangle reduced to S-vs-P per Perl-first phasing. |
| C8 | Determinism gate | **PARTIAL** | `wire-determinism.t`, 3 idioms, not per-entry wired (D-2). |

### 7 invariants (architecture "Review corrections" + plan CRITICAL guard)

| # | Invariant | Status |
|---|-----------|--------|
| 1 | perl is sole oracle | VERIFIED |
| 2 | gap-vs-miscompile classifier load-bearing | VERIFIED (but D-1 shows a miscompile slipped through via an *unobserved axis*, the residual-risk the classifier explicitly cannot catch — §122 "wrong on an unobserved axis") |
| 3 | C corner gated behind P-green | VERIFIED |
| 4 | zero out-of-scope work | VERIFIED |
| 5 | hand graphs direct, not from_json | VERIFIED |
| 6 | widened record with written policies | PARTIAL (D-3) |
| 7 | F7 same-IR-two-lowerings | N/A — moot until C corner (§116), correctly deferred |

### Deferred-items ledger

| Item | Verdict | Tracked where |
|------|---------|---------------|
| M20 `do {}` | DEFERRED | `%DEFERRED_REASONS` `GapMap.pm:47-57` + `2026-06-06-phase1-m20-m21-scope-decision.md` + follow-up issue 019e9b4a |
| M21 `eval {}` | REJECT | `%REJECT_IDIOMS` `GapMap.pm:33-40` + CLAUDE.md try/catch policy |
| I1 ADJUST | DONE | commit 5243356e; verified return=6 live |
| M19 tuple-assign | DONE | `2026-06-06-m19-multi-assign.md`; new `ListAssign` node; verified return=3 live |
| K2 post-inc | DONE (corpus) | emits `$i+=1`, behaviorally identical for corpus; general PreInc/PostInc node still deferred (Actions.pm comment) |
| C corner | DEFERRED | plan Stage 3 §85, §102 |
| chalk-parser / bson graph-source | DEFERRED | architecture C4 slots |
| M17/M18 `next`/`last` real emission | **UNTRACKED** | see D-1 — this deferral is currently unlabeled (the green status implies it is done) |

---

## Bottom line

**"Phase 1 done, tier-1 green" is SUBSTANTIALLY HONEST but carries one drift that must
be labeled before Phase 2, plus two coverage gaps.**

What is genuinely true: `tier1_green()` returns TRUE live (not just from a stored
artifact), 76 of 78 idioms PASS as real perl-S-vs-P behavioral agreement, the
sole-oracle / direct-hand-graph / gap-vs-miscompile / no-out-of-scope invariants all
hold, M20/M21 deferrals are properly registered and documented, and the new IR work
(ListAssign, ADJUST) is behaviorally correct against perl. The emitter changes are all
in-scope corpus-greening, not scope creep.

The drift to fix (D-1): **M17/M18 are a green-laundered miscompile** — the emitter drops
`next`/`last` entirely (`if (COND) {}`), and the corpus bodies are too inert to observe
it. This is the exact false-green class the architecture's round-2 HIGH risk and the
pushback review predicted, and it is the one PASS that does not represent real codegen
capability. It is currently an UNTRACKED deferral (the green status implies `next`/`last`
emission works; it does not).

The coverage gaps to acknowledge (not Phase-1 blockers, but not "done" either): (D-2)
determinism is verified on 3 of 76 idioms and the C8 gate is not wired per-entry; (D-3)
four behavior-record axes (`object_state`, `aliasing_topology`, dualvar numeric-face,
fp tolerance) are declared with written policies but never exercised by the oracle —
the widened record is widened in schema more than in behavior. Tier-1 doesn't need them,
but the plan made them load-bearing for the later tiers, so Phase 2 must light them up
before mining lib/ and pedagogical corpora (which WILL return floats and objects).

Recommendation before Phase 2: (1) relabel M17/M18 (NOT-YET-COVERED or tracked
known-limitation) OR fix the `is_loop_jump` emission and re-verify with an
observable-body corpus; (2) confirm the missing chain-review doc (D-0); (3) schedule
the four latent axes (D-3) and per-entry determinism (D-2) as named Stage-2 work.

## Acceptance criteria verification (brief's deliverable)

- Per-question verdict table — provided.
- Stage-1 and Stage-2(tier-1) checklists with met/not-met/partial — provided.
- DRIFT / glossed criteria called out — D-0 through D-3, with D-1 as the load-bearing
  finding.
- Deferred-items ledger — provided (one untracked deferral surfaced: M17/M18).
- Bottom line — provided.

## Cross-references

- `2026-06-06-phase1-audit-pushback-review.md:109-117` — predicted the M17/M18
  `is_loop_jump`-is-dead-code finding (D-1 confirms it landed as a false-green).
- `2026-06-05-codegen-harness-architecture.md:122` (round-2 HIGH) — the
  unobserved-axis miscompile risk that D-1 instantiates.
- `2026-06-06-phase1-m20-m21-scope-decision.md` — the tier-1-green definition this audit
  verified as sound (Q2).
- Brief-named `2026-06-06-codegen-harness-chain-review-regenerated.md` — MISSING (D-0).
