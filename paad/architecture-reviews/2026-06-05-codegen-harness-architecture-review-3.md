# PAAD Architecture Review — Round 3 (Convergence Check): CodeGen Behavioral Harness

**Date:** 2026-06-05
**Subjects (read fully):**
- `docs/plans/2026-06-05-codegen-harness-architecture.md` (architecture: C1–C8, S/P/C triangle Perl-first, two "Review corrections" rounds)
- `docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (plan: directional-CodeGen, gap-map-first w/ gap-vs-miscompile guard, 4 staged phases, tiered corpus)
**Prior reviews:** `...-architecture-review.md` (round 1), `...-architecture-review-2.md` (round 2)
**Mode:** Convergence check after rounds 1+2 folded in. Diagnosis only, no fixes (PAAD rule).
**Reviewer stance:** Adversarial but honest in both directions — a manufactured finding has cost; so does a false all-clear.
**Verification:** Load-bearing code facts re-verified at HEAD. `git diff --stat lib/ t/` empty before and after (only this report added).

---

## TOP-LINE VERDICT

**NOT CONVERGED — 1 new material finding (plus 1 minor sub-finding noted, below the action bar).**

The design is *very close* to convergence. Rounds 1 and 2 landed faithfully; the two docs tell one consistent story; every load-bearing interface fact is accurate at HEAD; and the two hardest soundness risks (gap-vs-miscompile discrimination, C2 false-greens) are now explicitly named in both docs. I did NOT find a new soundness hole in the oracle, the trust root, or the comparator beyond what rounds 1–2 already surface.

But one stated **Stage-2 acceptance criterion has no owning component in the harness's architecture**: "Establish the negative set: out-of-subset programs cleanly rejected" names an outcome that nothing in scope produces. That is a genuine, new, material boundary/scope gap — not a re-statement of round-1 F8 (corpus-entry classification) nor of the Stage-3 "C rejects underspecified IR" path. It is material because it is a checkbox the plan commits to that the architecture cannot deliver as drawn, which will surface as an un-buildable milestone.

If the team wants to graduate to execution, this one criterion needs an owner (or removal/deferral) first. Everything else is execution-ready.

---

## What I checked to be confident the rest has converged

1. **Round-1/2 findings are reflected in the CURRENT doc text, not just appended.** Verified the Perl-first staging, C-gate (tied to the concrete `generate($mop)` stub + `_generate_c_files($ir,$sa,$ctx)` weld), C6 split (hand builds MOP/Program directly; JSON reserved for deferred `bson`), C2 widening, and manual-surface honesty (driver+args manual; only expected *output* oracle-derived) all appear in BOTH docs and are mutually consistent. The gap-vs-miscompile guard (round-2 R1) is now a first-class CRITICAL guard in the plan (line 15) and a HIGH correction in the architecture doc (line 122) — the single most important round-2 finding made it in load-bearing, not as a footnote.
2. **Load-bearing interface facts still hold at HEAD** (read code, not docs):
   - `Target/Perl.pm:77` — `generate($input)` polymorphic: MOP → `_generate_from_schedule`, else Program → `_emit_program`. **Confirmed.**
   - `Target/C.pm:1722` — `generate($mop)` is the STUB (header comment at 1720–1721 literally says "minimal stub output"). **Confirmed.**
   - `Target/C.pm:1764` — real path `_generate_c_files($ir, $sa, $ctx)`. **Confirmed.**
   - `Target/C.pm:1852` — `$ctx->mop // die "_generate_c_files requires \$ctx->mop()..."`. **Confirmed** (welded to parser Context).
   - `JSON.pm:299` — `from_json` returns `\%graphs` of `Chalk::IR::Graph`, NOT MOP/Program. **Confirmed.**
3. **No folded-in finding is contradicted elsewhere** (a contradiction would itself be a new finding). The plan's round-2 R2 seam ("seed corpus verified to run natively") was reconciled — the plan now says explicitly (line 17) the file is a `=== TAG` catalog that does NOT compile (`perl -c` fails on `===`) and needs an extraction+wrap step. So round-2 R2 is RESOLVED, not residual. Re-verified: 78 `===` tags in the fixture.

---

## Probe results (the candidate areas the convergence check flagged)

I deliberately probed four areas to test whether the convergence claim is real or whether a finding was being missed. Three came back clean (no finding); one is the material finding above plus a minor companion.

### (a) Two determinisms — byte-identical codegen vs hash-order/FP normalization. **NOT a finding.**
C8 (determinism gate) compares the emitted *source string* to itself across two runs (byte-identical). C2 (behavior record) compares *runtime behavior* of S vs P with hash-order/FP normalization. These operate on different objects (emitted text vs runtime values), and the architecture doc explicitly labels C8 "Orthogonal to behavior" (line 86). There is no conflict: codegen text determinism and runtime-value normalization are independent axes. No contradiction.

### (b) Negative set — "rejected BY WHAT?" **MATERIAL FINDING (F-N1 below).**
This is the genuine new gap. See finding.

### (c) Staging — does Phase 2 (mine lib/) over-sequence behind Phase 1 (tier-1 green)? **NOT a (material) finding.**
The phases are presented sequentially, but the directional gap-map-first principle already licenses early gap-MAPPING of lib/ independent of tier-1 completion; only the COMPLETION work benefits from ordering. The conservative sequencing (finish tier-1 green before chasing tier-2 completion) is defensible and keeps the work-front narrow — it is a reasonable plan choice, not a structural flaw. Not material.

### (d) Gap-map "ranked by corpus = by idiom frequency" — is frequency captured? **MINOR sub-finding (below action bar).**
Plan lines 13/96 assert the gap map is "ranked by the corpus = by real idiom frequency." Verified: the corpus fixture carries one snippet per idiom with ZERO frequency/count/weight annotation (`grep` for freq/count/weight/occur → NONE; 78 tags, no weighting). So "= by frequency" is an *equation asserted*, not a signal *captured* — corpus membership is presence, not frequency. This affects work-ORDER prioritization only; it cannot cause a false green or a soundness failure, and a mis-ordered gap map is self-correcting (you still work every gap). Rated Low/Confidence-90; recorded for honesty, but it does NOT block graduation on its own. (If the team wants the ranking claim to be true rather than aspirational, capturing occurrence counts when mining tier-2/3 is the cheap fix — but that is a wording/scope tightening, not an architectural defect.)

---

## NEW FLAW

### F-N1 — The "negative set" acceptance criterion has no owning component in the harness architecture
**Category:** Structure / Boundaries (orphaned acceptance criterion) · **Impact:** Medium · **Confidence:** 85%

The plan commits, in BOTH the phase list (line 80) and the Stage-2 acceptance criteria (line 100), to:
> "Establish the negative set: out-of-subset programs cleanly rejected."

But nothing in the harness's *scope* performs that rejection:

- **S (C3, run-under-perl)** cannot reject anything as "out-of-subset" — perl happily runs vast swaths of Perl that are outside Chalk's subset. The oracle has no notion of the subset.
- **P (C5 → Target::Perl)** lowers a *graph*; CodeGen does not enforce subset membership. And in the day-one **hand-authored-graph** path, an out-of-subset program simply never gets a graph authored for it — there is no point at which the harness is handed an out-of-subset *source* and asked to reject it.
- The component that *actually* performs subset rejection is the **parser + SemanticAction** (the 4 filter semirings producing zero for non-subset constructs, plus IR-gen). Per the plan's own scope boundaries, **SemanticAction/IR-gen is KNOWN BROKEN and explicitly OUT OF SCOPE** ("No SemanticAction/IR-gen rewrite (paused)"; architecture line 95). So the only actor capable of producing the criterion's outcome is the one the plan excludes.

Therefore the negative-set criterion describes an outcome **no in-scope component produces**, in a stage (Stage 2) where the only wired path is S-vs-P over hand-authored graphs. As written it is an un-buildable milestone: an executor reaching Phase 1 will find no harness seam to attach a "cleanly rejected" check to.

**Why this is NEW (not a re-statement):**
- It is NOT round-1 **F8** (do/eval subset-membership): F8 is about *classifying corpus ENTRIES' membership* (corpus hygiene / tagging an entry in-subset vs reject). F-N1 is about *which component performs the rejection ACT* and finding that none is in scope.
- It is NOT the **Stage-3 "C/XS chokes where Perl passes"** path (plan line 38): that is C-backend type/shape strictness rejecting an *underspecified IR graph*, gated behind Stage 3, and is about IR underspecification — not about rejecting *out-of-subset source*. The negative-set criterion is a Stage-2 deliverable, where the C corner does not yet exist.

**Why it is material (not nit-level):** it is one of only ~4 Stage-2 acceptance criteria and it appears twice (phase + acceptance list), so it reads as a committed deliverable. Graduating to a task chain will decompose acceptance criteria into tasks; this one decomposes into "wire a check onto a component that isn't here," which either silently gets dropped (drift — the exact 80-90% pattern the project's plan-discipline warns against) or forces an unplanned re-scope mid-execution (pull the parser's subset-rejection — i.e. the excluded SemanticAction layer — back into scope).

**What would close it (diagnosis only, per PAAD — not prescribing the fix):** the criterion needs either (i) an explicitly-named rejector and its trust status (e.g. "subset-rejection is the *parser's* job and is verified independently of this harness; the negative set lives in the parser's test suite, not this harness"), or (ii) deferral to the stage where a source→graph front-end exists, or (iii) removal. Any of those resolves the orphan; the doc currently does none.

---

## Strengths confirmed stable (no regression from rounds 1–2)

- **S (perl-as-oracle) remains genuinely external** — zero Chalk dependency; uncontaminated. Unchanged and correct.
- **Gap-vs-miscompile guard is now load-bearing in both docs** — the round-2 R1 risk (the reframe's signature hazard) is no longer latent; it is a CRITICAL guard the operator is instructed to honor ("a red is NOT automatically just a gap"; "a miscompile is a correctness alarm, never backlog"). This was round-2's most important catch and it converged.
- **C deferral is structural, tied to verified code facts**, not vibes. Both docs gate C identically on (P-green) AND (free-standing-graph→C path), and both cite the stub + weld.
- **Trust-root honesty** — the round-2 R3 "hand-author MOP = hand-wire a SoN graph through EagerPinning, not trivial" finding is reflected (architecture line 123: "a hand MOP must carry a real SoN GRAPH with control edges + schedule-meta, not a statement list... ~6 node calls minimum... body_stmts seeding is itself prototype").
- **C2 widening + the still-open equivalence-class debt** is recorded (architecture line 124), so the team is not walking into the reference-topology/blessed-identity false-greens blind.

---

## Convergence assessment summary

| Dimension | Status |
|---|---|
| Round-1 corrections reflected & uncontradicted | CONVERGED |
| Round-2 corrections reflected & uncontradicted | CONVERGED |
| Load-bearing code facts accurate at HEAD | CONVERGED (4/4 re-verified) |
| Oracle soundness (S external) | CONVERGED |
| Gap-vs-miscompile discrimination | CONVERGED (now explicit) |
| Behavior-record sufficiency | Open debt, but NAMED (not a new finding) |
| Trust-root cost honesty | CONVERGED |
| **Negative-set criterion ownership** | **NOT CONVERGED (F-N1)** |
| Gap-map frequency ranking | Minor wording gap (below action bar) |

**Decision input:** 1 new material finding (F-N1). The team is one clarification away from graduation: assign an owner (or defer/remove) the negative-set criterion. The rest of the design is stable and execution-ready.

---

## Next question (for the author, before graduation)

1. The Stage-2 criterion "out-of-subset programs cleanly rejected" — **which component rejects them, and is it in this harness's scope?** Given S=perl (no subset notion), P=CodeGen-over-hand-graphs (no subset enforcement, and out-of-subset programs never get a hand graph), and SemanticAction (the actual subset gate) is explicitly out of scope — is the negative set (a) the parser's responsibility tested elsewhere, (b) deferred to a source→graph front-end stage, or (c) to be dropped from Stage 2? (F-N1)

---

## Evidence appendix (commands run, all read-only; `git diff --stat lib/ t/` empty before and after)

- `Target/Perl.pm:77–85` — `generate($input)` polymorphic (MOP vs Program). **Doc-accurate.**
- `Target/C.pm:1720–1730` — `generate($mop)` STUB (header "minimal stub output"). **Doc-accurate.**
- `Target/C.pm:1764` — `_generate_c_files($ir,$sa,$ctx)`. **Doc-accurate.**
- `Target/C.pm:1852–1854` — `$ctx->mop // die "_generate_c_files requires \$ctx->mop()..."`. **Doc-accurate** (parser-Context weld).
- `JSON.pm:299–306` — `from_json` returns `\%graphs` of `Chalk::IR::Graph`, NOT MOP/Program. **Doc-accurate.**
- `grep ===` `t/fixtures/ir-audit-corpus.pl` → 78 tags; `grep -i freq|count|weight|occur` → NONE. (Probe d: frequency not captured.)
- `grep negative|reject|cleanly|parser` both docs — negative set named at plan lines 80, 100; no rejector component attributed; SemanticAction explicitly out of scope (architecture line 95). (F-N1.)
- `git diff --stat lib/ t/` → empty before and after.
