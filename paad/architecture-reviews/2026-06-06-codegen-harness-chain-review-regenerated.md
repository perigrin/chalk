# Chain Review: `codegen-harness` milestone (REGENERATED on git-zhi 0.3.8)

**Date:** 2026-06-06
**Reviewer role:** crochet:chain-review (alignment coverage lens + pushback plan-quality lens), pre-execution gate.
**Chain:** milestone `codegen-harness`, 12 issues (11 code + 1 doc), re-derived via crochet:refinement on git-zhi 0.3.8 from the committed source docs.
**Why a second review:** the prior 0.3.1-written chain became unreadable after the 0.3.8 upgrade (ref-namespace change, git-zhi #9), so the chain was REBUILT — every issue body was freshly authored. The DAG shape was eyeballed; the bodies had not been independently reviewed. This review gates the regenerated bodies.
**Spec ("PRD"):**
- `docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (plan: 4 staged phases + staged acceptance criteria)
- `docs/plans/2026-06-05-codegen-harness-architecture.md` (architecture: C1–C8, gap-vs-miscompile classifier, Perl-first/C-gated, behavior-record widening, F7)
- `paad/architecture-reviews/2026-06-06-codegen-harness-chain-review.md` (the ORIGINAL chain review; its P-3 and P-4 advisories were to be baked into this regeneration)
**Mode:** Diagnosis only. No edits to `lib/`, `t/`, or `refs/zhi/`. Working tree clean at finish.

---

## 1. Top-line verdict

**READY TO EXECUTE.** The regenerated bodies faithfully encode the converged plan and all PAAD-hardened corrections, and — unlike the chain reviewed on 0.3.1 — the two prior advisories (P-3 gap-map breadth, P-4 C-corner gate threshold) are now **baked into the issue bodies as load-bearing acceptance criteria**, not left as executor advisories. No new blocking findings. One verified-and-corrected discrepancy improves on the prior chain (see §3).

The DAG, dependencies, ready set, and out-of-scope cleanliness all match the reviewed 0.3.1 chain. The body rewrite preserved every invariant.

---

## 2. Per-invariant pass/fail (verified against the regenerated bodies)

| Invariant | Verdict | Evidence in the regenerated bodies |
|---|---|---|
| **(1) perl is the SOLE oracle** — no self-comparison | **PASS** | `019e9a91-1bbe` (oracle) captures S "zero Chalk dependency"; `019e9a94-0cc7` (Phase 1) negative AC `tier1-green-neg.t` "FAIL if an idiom's expected behavior is taken from prior Chalk output instead of perl S"; `019e9a95-f912` (capstone) "oracle is the ORIGINAL parser run under perl, not prior Chalk output." No stored-Chalk-output oracle anywhere. |
| **(2) CodeGen DIRECTIONAL; gap-map first; GAP vs MISCOMPILE classified** | **PASS** | `019e9a91-8951` (comparator) implements `{PASS\|GAP\|MISCOMPILE}` as the load-bearing path with six false-green negatives (miscompile-laundered-as-gap, gap-misclassified-as-pass, unobserved-axis, FP boundary, empty-record collusion). `019e9a93-92c3` (gap map) precedes `019e9a94-0cc7` (completion). "MISCOMPILE is a correctness alarm, never backlog" re-asserted in gap-map, Phase-1, tier-2, tier-3, capstone, and doc issues. |
| **(3) C corner GATED on Phase-1-green + free-standing-graph→C path** | **PASS** | `019e9a95-3682` (C path) `blocked_by 019e9a94-0cc7` (Phase 1); `019e9a95-9af7` (triangle) `blocked_by 019e9a95-3682`. Gate enforced structurally in the DAG **and** spelled out as a concrete prose gate in the C-path body (see P-4 below). |
| **(4) ZERO out-of-scope issues** (SA rewrite / B::SoN / parser-bridge / subset-rejection enforcement) | **PASS** | None present. `019e9a92-9aa2` hand-authors graphs directly (no SA rewrite). `bson` named only as a deferred slot. tier-2/tier-3 bodies state classification is "a LABELING step only — this harness does NOT enforce subset-rejection (parser-scope concern, deferred; plan line 100 / PAAD F-N1)"; tier-3 has a dedicated negative AC `tier3-neg.t` "No subset-enforcement creep." |

Additional invariants from the source docs, also confirmed in the bodies:
- **Trust root = hand-author MOP/Program DIRECTLY, not via lossy `from_json`** — `019e9a92-9aa2` positive AC "no JSON," negative AC "hand-graph build does NOT route through `Chalk::IR::Serialize::JSON::from_json`."
- **Hand graphs need real SoN + control edges (EagerPinning), start data-only** — `019e9a92-9aa2` scopes to "SMALLEST DATA-ONLY idioms (no control flow)"; negative AC "under-wired statement-list graph must FAIL EagerPinning loudly." Control-shape (Region/Phi) deferred to Phase 1.
- **Widened behavior record, written policy per axis** — `019e9a91-1bbe` enumerates all 11 axes, each requiring a WRITTEN normalization policy; negative AC rejects "an axis named but without a written policy."
- **Determinism (byte-identical Perl)** — `019e9a93-2153` (C8 gate) + re-checked in Phase-1 and capstone.
- **F7 same-IR-two-lowerings** — `019e9a95-9af7` enforces refaddr identity of the graph object across both backends; negative AC fails a rig feeding two separately-built graphs.

---

## 3. The one material change vs the 0.3.1 chain — a CORRECTION, verified

The prior review (0.3.1 chain) raised **P-3** as a LOW advisory: the gap-map category enum (`decls/side-effects/.../methods`) was narrower than the corpus taxonomy, and the prior review estimated the corpus at "**~39 idioms across groups A–M**."

The regenerated `019e9a93-92c3` does not merely "widen the enum" — it pins an **exact denominator of 78 idioms** with a per-group breakdown (A=5, B=8, C=5, D=8, E=4, F=3, G=4, H=4, I=3, J=3, K=2, L=4, M=25) as a load-bearing AC, with negative scenarios guarding shrunk-denominator and dropped-group false greens.

**I independently verified this against the corpus at HEAD** (`grep` on `t/fixtures/ir-audit-corpus.pl`):
- `=== TAG` delimiter lines: **78** (matches).
- Distinct `[A-M]<n>` idiom tags: **78** (matches).
- Per-group counts: **A=5, B=8, C=5, D=8, E=4, F=3, G=4, H=4, I=3, J=3, K=2, L=4, M=25** — every count matches the body verbatim. Highest M index = M25.

So the prior review's "~39" was an undercount, and the regenerated chain carries the **correct, verified** number baked into a test assertion (`gap-map.t`: denominator == 78, all 13 groups present). This is a strict improvement: P-3 went from an unbaked advisory with a wrong count to a baked, verified, test-enforced criterion.

**P-4** (the prior LOW advisory: "substantially green" was undefined) is likewise now baked: `019e9a95-3682` opens its Prerequisites with **"P-4 CORRECTION (chain-review, load-bearing): the gate is CONCRETE … Phase 1 tier-1 is 100% PASS / 0 MISCOMPILE / 0 GAP across groups A-M (`tier1-green.t` all-green). Tier-2 / tier-3 are NOT required."** The Phase-1 gate (`019e9a94-0cc7`) defines exactly that bar. No vagueness remains.

---

## 4. Pushback findings (plan-quality lens)

The two prior advisories that were *baked in* (P-3, P-4) are resolved. The two that are *inherently executor-time* (P-1, P-2) remain — correctly, because they cannot be pre-resolved:

- **P-1 (LOW–MED, carried) — `019e9a94-0cc7` and `019e9a95-f912` are honestly-framed epics.** Both are labeled `[EPIC]`/`[CAPSTONE]` in the title and body, structured as iterated RED-GREEN-COMMIT loops over a work-list, with explicit "expect many commits / possibly child issues; single-issue framing is NOT a promise of single-sitting completion." The body even pre-records the intended split axis (gap-map categories A–M) for `019e9a94-0cc7`, deferred until the gap map exists. This is the correct treatment; not a blocker.
- **P-2 (LOW, carried) — `019e9a94-0cc7` absorbs control-shape hand-graph authoring** (D-group Region/Phi graphs) that `019e9a92-9aa2` deferred. The body names this explicitly ("Control-shape work absorbed here (chain-review P-2)") and flags it as non-trivial IR-internals work. Consistent with the architecture's "add control-shape graphs incrementally" guidance. Budgeted, not hidden.

No new pushback findings. Issue sizing (outside the two acknowledged epics) is consistent ~2-hour-to-half-day scope. Dependencies are technically grounded (comparator-after-oracle on the genuine `BehaviorRecord` type dependency; wire joins all three heads; gap-map-after-wire; everything downstream of the gap map).

---

## 5. Feasibility — PASS (code-reality claims re-confirmed)

The load-bearing code-reality claims the chain depends on were verified against HEAD in the prior review and the bodies cite the same line numbers; the corpus claim was re-verified here (§3). No interface has changed between the two reviews (same branch `phase1-lateral-bindings`). Key claims the bodies stake themselves on:
- `Target::C->generate($mop)` is a comment-only stub (`C.pm:1722`); real C path `_generate_c_files($ir,$sa,$ctx)` welded to parser Context, dies without `$ctx->mop()` (`C.pm:1852`) — `019e9a95-3682` opens against exactly this and asserts a real method body with NO Context.
- `Target::Perl->generate` polymorphic over MOP/Program (`Perl.pm:77`), runs EagerPinning per body — `019e9a93-2153` / `019e9a92-9aa2` rely on this correctly.
- `from_json` lossy — `019e9a92-9aa2`'s no-JSON guard is well-founded.

---

## 6. Bottom line

The regenerated chain is a faithful re-derivation of the reviewed plan with the two prior advisories now baked in as test-enforced criteria — and the P-3 denominator was verified against the corpus and is *more correct* than the chain reviewed on 0.3.1. The DAG, dependencies, ready set, invariants, and out-of-scope cleanliness all hold. The body rewrite introduced no drift.

**Recommend proceeding to crochet:execute**, beginning with the three independent Phase-0 heads — `019e9a91-1bbe` (oracle), `019e9a91-8951` (comparator), `019e9a92-9aa2` (hand graphs) — in parallel. The oracle head is the cleanest first cycle (pure ground-truth capture, zero Chalk dependency).
