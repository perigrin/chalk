# PAAD Architecture Review — Round 4 (Confirmation): CodeGen Behavioral Harness

**Date:** 2026-06-05
**Mode:** Tight confirmation pass after round-3 fixes (commit `93b9e00f`). Diagnosis only, no fixes.
**Subjects:**
- `docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (the plan)
- `docs/plans/2026-06-05-codegen-harness-architecture.md` (the architecture)
**Prior reviews:** `...-architecture-review{,-2,-3}.md`
**Verification:** `git diff --stat lib/ t/` empty before and after (this report only). HEAD at `93b9e00f`.

---

## TOP-LINE VERDICT

**CONVERGED (zero new material findings; round-3 fixes confirmed; ready to execute).**

Round-3's one material finding (F-N1) is fully resolved, the minor frequency item is substantially resolved (one cosmetic residue noted below, well below the action bar — same Low/non-material class round-3 already assigned it), no new inconsistency was introduced between the docs, and no new material flaw surfaced on a fresh standard-lens scan. The design has converged. The team may graduate to decomposing the plan into a task chain.

---

## Confirmation 1 — F-N1 (negative-set ownership): CONFIRMED FIXED

The round-3 finding was that "out-of-subset programs cleanly rejected" was committed as an OWNED milestone (plan phase line + Stage-2 acceptance line) with no in-scope component producing it.

Verified against the fix commit (`git show 93b9e00f`) and current text:

- **Phase 1** (was line 80): the bullet `- Establish the negative set: out-of-subset programs cleanly rejected.` is **DELETED**. Phase 1 now owns only "work the gap map to tier-1 green," which is genuinely in scope.
- **Stage-2 acceptance** (was line 100): the owned bullet `- Negative set: out-of-subset programs cleanly rejected.` is **REPLACED** by a parenthetical scope NOTE (current line 100) that explicitly states subset-rejection is a parser/front-end concern, names the actor (parser+SemanticAction), records that the plan defers it, and keeps corpus-entry CLASSIFICATION as a labeling step. This is exactly resolution path (i)+(iii) round-3 offered: named rejector + trust status, with the enforcement removed from this plan.
- **grep sweep** (`negative set|cleanly reject|out-of-subset|out of subset`): the only remaining hits in the plan are (a) line 61 — a tier-3 source caveat ("much is out-of-subset / classify hard"), which is corpus classification, not harness-performed rejection; and (b) line 100 — the scope note itself. Neither treats subset-rejection as work THIS harness performs. **No remaining owned occurrence.**
- **Architecture doc:** zero hits for negative set / reject-as-action. The only `reject` reference (C1, line 61) is the corpus-entry **classification tag** (`in-subset / reject / scope-decision`) — a labeling step, consistent with the plan's reframe. No dangling reference assuming the negative set is produced.

The removal did not orphan anything: every stage still maps to a phase, and no acceptance criterion now points at a missing phase.

## Confirmation 2 — frequency-ranked gap map: SUBSTANTIALLY FIXED (one cosmetic residue, below action bar)

Round-3's minor sub-finding: the gap map was described as "ranked by the corpus = by real idiom frequency," but the corpus has no frequency data.

- **Plan line 13** (the primary statement): **fully reworded** — now "organized by corpus category/coverage — NOT by frequency," with an explicit explanation that frequency data does not exist and the gap map is a coverage-organized work-list. Correct and complete.
- **Architecture doc:** zero `frequency|ranked` hits. Clean.
- **RESIDUE (cosmetic, below action bar):** plan **line 95** still reads "...which idioms CodeGen handles vs. doesn't-yet, **ranked**." The bare word "ranked" is the same gap-map deliverable; its only defining dimension (frequency) was removed everywhere else, so "ranked" now has no antecedent. This is a leftover from the same wording-residue the round-3 fix targeted — the line-13 statement was fixed comprehensively; this echo was missed.

  **Why this is NOT a (new) material finding:** it is the identical item round-3 already adjudicated as Low / Confidence-90 / **below the action bar** — it "affects work-ORDER prioritization only; it cannot cause a false green or a soundness failure, and a mis-ordered gap map is self-correcting." A bare "ranked" with no specified key is, if anything, *less* committal than the prior "ranked by frequency," so it carries strictly less risk than the item already deemed non-blocking. It does not re-open the finding's materiality. Recorded for honesty; it does not block graduation. (Cheap optional tidy: drop "ranked" or write "category-organized" to match line 13.)

## Confirmation 3 — no new cross-doc inconsistency: CONFIRMED

- The plan now says corpus-entry CLASSIFICATION (in-subset/reject/scope-decision) stays in scope as a labeling step; the architecture doc's C1 already carries exactly that classification tag. **Consistent** — the fix actually tightened alignment.
- The architecture doc never claimed harness-performed subset-rejection nor frequency ranking, so removing both from the plan created no divergence. The two docs still tell one story.
- The fix commit touched only the plan doc + the round-3 review file; no code, no architecture-doc edits — so the round-1/2 load-bearing interface facts (Target/Perl.pm:77; Target/C.pm:1722 stub / 1764 / 1852 weld; JSON.pm:299 lossy) are undisturbed by definition. Re-verified at HEAD by commit scope (`git diff --stat lib/ t/` empty); no spot-recheck warranted since nothing changed near them.

---

## Fresh standard-lens scan (new material findings?)

Probed specifically for (a) a dangling reference left by the F-N1 removal and (b) internal completeness (every phase deliverable owned; every acceptance criterion maps to a phase).

- **Dangling F-N1 reference:** none found beyond the (intentional) scope note. No stage, phase, or acceptance line still assumes a negative set is produced.
- **Phase ↔ acceptance mapping (now complete):**
  - Stage 1 (harness + gap map) ← Phase 0 — owned.
  - Stage 2 (complete CodeGen to green) ← Phase 1 (tier-1) + Phase 2 (tier-2/3) — owned; the only formerly-unowned criterion (negative set) was removed.
  - Stage 3 (C corner, gated) ← Phase 3 — owned, with the gate stated identically in both docs.
  - Stage 4 (capstone: self-host Earley) ← Phase 4 — owned.
  Every acceptance criterion now maps to a phase with an in-scope owner; every phase deliverable has an owner. Internally complete.
- **Oracle / trust-root / comparator soundness:** unchanged from round-3's CONVERGED assessment (S external, gap-vs-miscompile guard load-bearing, C deferral structural, trust-root cost honest, C2 widening + open equivalence-class debt named). The fix did not touch these. No regression.

No new material finding.

---

## Decision input

| Item | Status |
|---|---|
| F-N1 (negative-set ownership) | **CONFIRMED FIXED** |
| Frequency-ranked gap map | **FIXED** at the substantive site (line 13); one cosmetic residue (line 95 "ranked"), below action bar, non-material |
| New cross-doc inconsistency from fixes | **NONE** |
| Phase↔acceptance completeness | **COMPLETE** |
| New material findings (fresh scan) | **ZERO** |

**CONVERGED.** Ready to execute. The optional one-word tidy on line 95 is a wording cleanup the team may fold into execution; it is not a gate.

---

## Evidence appendix (all read-only; `git diff --stat lib/ t/` empty before and after)

- `git show 93b9e00f` — fix commit touches only the plan doc (3 changed lines) + adds review-3; no code.
- plan `negative set|cleanly reject|out-of-subset`: hits at lines 61 (tier-3 source caveat) and 100 (scope note) only; no owned occurrence. Architecture doc: none.
- plan `frequency|ranked`: line 13 (reworded "NOT by frequency / coverage-organized"), line 95 (residual bare "ranked"). Architecture doc: none.
- architecture `subset|reject|frequenc|ranked|gap map`: only C1 line 61 classification tag (`in-subset / reject / scope-decision`) — labeling, not rejection-as-action.
- `git diff --stat lib/ t/` → empty. HEAD `93b9e00f`.
