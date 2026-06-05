# PAAD Architecture Re-Review: CodeGen Behavioral Harness (Round 2)

**Date:** 2026-06-05
**Subjects (read fully, reconciled to tell one story):**
- `docs/plans/2026-06-05-codegen-harness-architecture.md` (architecture: C1–C8, S/P/C triangle, "Review corrections")
- `docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (plan: directional-CodeGen framing, gap-map-first, 4 phases, tiered corpus)
**Prior review:** `paad/architecture-reviews/2026-06-05-codegen-harness-architecture-review.md`
**Mode:** Re-review of a not-yet-built verification harness, AFTER round-1 corrections were folded into the docs. Diagnosis only, no fixes (PAAD rule).
**Reviewer stance:** Adversarial. An unsound verification oracle is the worst outcome; the oracle logic and the trust root get the harshest scrutiny.
**Verification:** All code claims re-verified against HEAD. `git diff --stat lib/ t/` empty before and after (only this report added).

---

## Summary verdict

**The round-1 corrections landed cleanly and faithfully.** Every load-bearing interface fact the docs now assert is TRUE against code at HEAD: the C `generate($mop)` stub, the real `_generate_c_files($ir,$sa,$ctx)` path with its `$ctx->mop()` death, the lossy `Graph`-returning `from_json`, and the Perl `generate` polymorphism are all described correctly. The reframe to "CodeGen is DIRECTIONAL — gap-map first, complete idiom-by-idiom with perl as spec, C corner gated behind P-green" is internally coherent and resolves the round-1 structural blockers honestly. The two docs tell one consistent story.

**But the reframe introduces ONE genuinely new soundness risk that the first review did not cover, and re-verification surfaced TWO doc-vs-code inaccuracies and ONE underweighted trust-root cost:**

1. **NEW — gap-vs-miscompile conflation (the reframe's own hazard).** Under "directional CodeGen, red is expected," the harness's framing actively biases the operator to read failures as *gaps* (CodeGen-not-yet) rather than *miscompiles* (CodeGen-wrong-but-plausible). A gap usually fails loudly (emit dies / won't compile / blatantly wrong output). A miscompile passes-but-wrong on the OBSERVED projection. The combination of (a) an under-observing behavior record (still partially true, see below) and (b) a "default reading is: not implemented yet" posture is a recipe for **dismissing a false green as an unimplemented idiom**. This is new because round-1 reviewed a "verify a finished CodeGen" design; the "complete a directional CodeGen" design changes the operator's default interpretation of a passing/failing result.

2. **DOC-VS-CODE — "verified to run natively under perl 5.42" is imprecise (plan line 15).** `t/fixtures/ir-audit-corpus.pl` does NOT run or even compile under perl 5.42 (`perl -c` → `syntax error ... near "=="`). It is a fixture-format file (`=== TAG: desc` headers + class fragments), not a runnable program. The *fragments* run only after wrapping (`use v5.42; use experimental 'class';` + a driver + `say`). The claim is defensible for the fragments but as written ("the root-of-trust corpus ... verified to run natively under perl 5.42") it overstates the artifact's readiness and hides the driver-wrapping cost the prior review flagged as F5/Q5.

3. **TRUST-ROOT COST — hand-authoring tier-1 MOP/Program is adapter-free but NOT deep-knowledge-free.** This is the round-1 Q4 recommendation ("hand source produces MOP/Program directly, no JSON") taken at face value. Re-verification shows the production Perl path is `_generate_from_schedule → _emit_mop_method → _emit_scheduled_body`, which runs the **EagerPinning scheduler over the method's Sea-of-Nodes `$graph`** (`Perl.pm:204,234–236`; `EagerPinning.pm:26`). So "hand-author the MOP directly" means hand-wiring a SoN graph — Start/Constant/VarDecl/Return nodes with correct control edges (`set_control_in`), per-method hash-cons scope, AND the structured-control fields the scheduler reads (`body_stmts`, `then_stmts`, `else_stmts`, `iterator`, `is_for_style`; `EagerPinning.pm:235`). The smallest possible method (`return "hello"`) already costs ~6 node-construction calls plus factory/graph plumbing (verified in `t/bootstrap/c-schedule-walker.t:18–40`). Tier-1 idioms like D1 (if/else) or D2 (while) require correctly-wired Region/Phi/loop CFG. The trust root is real and adapter-free, but it requires the SAME deep IR/MOP knowledge the strategy is trying to route around — and one of those fields (`body_stmts` seeding) is itself flagged prototype in project memory (commit c7361f3c). The plan's framing ("hand-author MOP/Program directly," lines 47/72) reads as low-cost; it is not.

The design is sound enough to build the Perl-first half. The above are not blockers; they are sharp edges that, unaddressed, defeat the harness's purpose (catching miscompiles) or sandbag tier-1 throughput.

---

## Re-verification of load-bearing interface claims (Phase 1 recon — read code, not docs)

| Doc claim (revised) | Reality at HEAD | Verdict |
|---|---|---|
| Perl `generate($input)` takes MOP (→`_generate_from_schedule`, returns hashref `{'main.pm'=>...}`) or `IR::Program` (→`_emit_program`, returns string). `Perl.pm:77–85`. | TRUE. `Perl.pm:77–85`; MOP branch returns `{ 'main.pm' => $code }` (`Perl.pm:115`). Polymorphic return type still real. | **Accurate.** |
| C `generate($mop)` (`C.pm:1722`) is a STUB — only `/* method: name */` comments + empty `MODULE = X PACKAGE = X`, no bodies (`C.pm:1733–1746`). | TRUE. `C.pm:1722–1756` verbatim: method-name comments + boilerplate includes + bare `MODULE` line. No body emission. | **Accurate — correction landed.** |
| Real C codegen is `_generate_c_files($ir,$sa,$ctx)` (`C.pm:1764`), takes Program + chalk-parser SA + Context, asserts `$ctx->mop()` (`C.pm:1853`), dies otherwise. | TRUE. `C.pm:1764` signature `($ir,$sa,$ctx)`; `$ctx->mop // die "_generate_c_files requires \$ctx->mop()..."` at `C.pm:1852–1854`. Welded to parser Context. | **Accurate — correction landed.** |
| `from_json` returns hash of name→`Chalk::IR::Graph`, NOT MOP/Program (`JSON.pm:299–306`); `_deserialize_graph` silently drops unsupported fields (`JSON.pm:210–214`), i.e. lossy. | TRUE. `from_json` returns `\%graphs` of `Chalk::IR::Graph` (`JSON.pm:301–305`). `_deserialize_graph` header explicitly says unsupported fields "are silently dropped" (`JSON.pm:211–213`); RegexMatch/VarDecl branches supply defaults rather than preserving source fields (`JSON.pm:266–277`). | **Accurate — correction landed.** |
| Seed corpus `t/fixtures/ir-audit-corpus.pl` runs under perl 5.42 (plan line 15). | **PARTIALLY FALSE.** File does NOT compile (`perl -c` → syntax error near `==`); 156 lines of `=== TAG` headers + class fragments. Individual fragments run only when wrapped with pragma + driver + output. | **Inaccurate as stated** (see flaw R2). |

---

## Strengths (what the reframe got right)

- **S1 — Corrections are faithful, not cosmetic.** The docs did not merely append a caveat; they restructured around the findings (Perl-first staging, C6 split, C2 widening, manual-surface honesty). The "Review corrections" section and the staged phases/acceptance criteria are mutually consistent — Phase 0–4 map 1:1 to Stage 1–4, and both gate C identically ("Perl green AND free-standing-graph→C path exists; `generate($mop)` is a stub"). No leftover day-one-dual-backend language survives in either doc.
- **S2 — The oracle remains genuinely external and uncontaminated.** perl-as-S (C3) still has zero Chalk dependency. The reframe does not weaken this; it strengthens the "never compare to Chalk's own prior output" discipline (plan lines 13, 27).
- **S3 — Directional framing is intellectually honest about CodeGen state.** Calling current CodeGen "a sketch of the right shape" and the deliverable "a gap map, red is the work-list" is a more accurate self-description than "verify a finished CodeGen," and it correctly de-risks early reds from being read as subtle regressions.
- **S4 — C deferral is now structural, not vibes.** The gate is tied to a concrete code fact (`generate($mop)` stub + `_generate_c_files` needing `$sa`+`$ctx`+`$ctx->mop()`), not a soft "C is buggy." This is the cleanest part of the reconciliation.
- **S5 — Manual-surface honesty improved.** Both docs now name driver+representative-args as a manual axis (architecture C1/§corrections; plan Phase 2, "only the expected *output* is oracle-derived"). The round-1 Q5 nuance survived into the docs intact.
- **S6 — JSON correctly evicted from the trust root.** The docs now say the `hand` source builds MOP/Program directly and reserve JSON/`from_json` for the deferred `bson` path, explicitly labeled "untrusted plumbing." This is the right call given the verified lossiness.

---

## Flaws / Risks

### R1 — Directional framing cannot distinguish a GAP from a silent MISCOMPILE (the reframe's new hazard)
**Category:** Error handling / Soundness-of-oracle · **Impact:** High · **Confidence:** 85%
The reframe instructs the operator: "Early red results are not subtle bugs — the default reading is: CodeGen does not implement this idiom yet" (plan line 13). That is correct for the *common* case but dangerous as a *default*, because the two failure modes have opposite signatures:
- **Gap** (idiom unimplemented): emit dies, won't compile, or output is blatantly absent/wrong → fails LOUD. Safe to read as "not done."
- **Miscompile** (idiom emitted but semantically wrong): produces plausible-but-wrong behavior → fails QUIET on the observed projection, or *passes* if the wrong axis isn't observed (a false green).

Nothing in the architecture distinguishes these. The comparator (C7) classifies `S≠P` as "IR/codegen divergence" but has no rule separating "P could not be produced" (gap) from "P was produced and is subtly wrong" (miscompile). Worse, the *posture* ("default reading: not implemented yet") trains the operator to triage a quiet `S≠P` as a backlog item rather than a correctness alarm — and to dismiss a green as "implemented" without auditing whether the green is on the full behavior projection. The harness needs an explicit gap-vs-miscompile discriminator (e.g. emit-success is itself a recorded outcome distinct from behavior-match; a green must assert "P was emitted AND ran AND matched on the FULL widened record"). As written, a directional CodeGen that emits confidently-wrong code for an idiom the operator believes is "still a gap" is the exact false-green a verifier exists to prevent. The first review (Q2/F4) flagged false greens from an under-observing record; this is a *distinct, compounding* source of false green introduced by the directional posture itself.

### R2 — "Corpus verified to run natively under perl 5.42" overstates the seed artifact
**Category:** Integration / Contracts · **Impact:** Medium · **Confidence:** 95%
Plan line 15: "the root-of-trust corpus already exists in seed form ... verified to run natively under perl 5.42." Verified FALSE for the file as an artifact: `perl -c t/fixtures/ir-audit-corpus.pl` → `syntax error ... near "=="`. The `===` header lines are not Perl. The class fragments run only after (a) prepending `use v5.42; use experimental 'class';`, (b) supplying a driver (`C->new->m(...)`), and (c) supplying representative arguments for parameterized methods (D1 `m($n)`, M8 `m($r)`). The "ground truth already exists" framing therefore hides the same per-entry harness cost the prior review flagged (F5/Q5) — and which the architecture doc DID absorb (C1, §corrections) but the plan's "Why this, why now" did not update to match. This is a residual doc-vs-doc seam: the plan still implies the seed is run-ready; the architecture concedes it is not. Minor inconsistency, but it is in the load-bearing "root of trust already exists" claim.

### R3 — Hand-authored trust root requires deep SoN/scheduler knowledge, not just "author a MOP"
**Category:** Testability / Bootstrap · **Impact:** Medium · **Confidence:** 90%
Both docs present the trust root as "hand-author MOP/Program directly" (plan 47/72; architecture C4/§corrections). Re-verification of the production path shows what that actually entails: the Perl backend's MOP path runs the **EagerPinning scheduler over the method's `$graph`** (`Perl.pm:234–236` → `EagerPinning.pm:26 my $graph = $method->graph`). So a hand MOP must carry a correctly-wired Sea-of-Nodes graph:
- `Chalk::MOP::Method` requires a `$graph` (`Chalk::IR::Graph`) and the body nodes (`MOP/Method.pm:16,18`).
- The smallest method (`return "hello"`) = Start node + Constant node + `make_cfg('Return')` + `set_control_in($start)` + 3× `$graph->merge` — 6 construction calls (`t/bootstrap/c-schedule-walker.t:26–40`).
- Control idioms (D1 if/else, D2/D3 loops) require Region/Phi/structured-control nodes with `then_stmts`/`else_stmts`/`body_stmts`/`iterator`/`is_for_style` populated, because the scheduler reads those fields (`EagerPinning.pm:235`). One of them (`body_stmts` seeding) is flagged a PROTOTYPE in project memory (commit c7361f3c) — so the hand-author must also track which scheduler inputs are themselves provisional.

This does NOT reintroduce coupling to the chalk-*parser* (the answer to Q3 is "yes, adapter-free of the parser"). But it DOES require deep MOP+SoN+scheduler internals knowledge. The trust root is harder to construct than "author a MOP" implies, and the per-idiom authoring cost scales with control-flow complexity. The plan should budget this (it currently does not name SoN-graph-authoring as the tier-1 cost) and should note the bootstrap risk: a hand graph authored *wrong* (mis-wired control edge) is itself an un-grounded artifact — the trust root is only as trustworthy as the human's SoN fluency, and there is no independent check that a hand graph equals the idiom's intent except... running it through the very CodeGen under test. (perl-as-S checks the *result*, which catches a mis-wired hand graph as an `S≠P` — so the oracle does backstop this — but then the operator faces R1: is that `S≠P` a CodeGen gap, a CodeGen miscompile, or a mis-authored hand graph? Three causes again, now on the Perl corner, not just the deferred C corner.)

### R4 — Widened behavior record (C2) is better but still has named gaps; equivalence classes remain missing
**Category:** Testability / Soundness-of-oracle · **Impact:** Medium · **Confidence:** 75%
The C2 record was widened per round-1 to: return + wantarray/context + stdout + STDERR/warnings + exception + object-state + hash-order + FP-tolerance + dualvar + aliasing/tie/overload. That closes the round-1 F4 list. But for a *verification* oracle, "we listed these axes" is not "these axes are capturable and specified," and several listed axes are hand-wavy or under-specified, plus new classes are still missing:
- **Specification debt on listed axes:** "hash-order normalized," "FP-tolerant," "dualvar (num vs str)" are named as *intentions*, not policies. What tolerance? Normalize by sorting keys (loses insertion-order semantics that some idioms depend on)? Dualvar comparison needs a defined num-AND-str equality, not "capture dualvar." Without a written comparison policy per axis, the record is a checklist, not a contract — and an under-specified comparison silently picks one projection, reintroducing false greens (R1's compounding partner).
- **Still-missing equivalence classes:** **blessed-ref identity / class name** (two objects of different classes can compare equal on field-values-only — object-state capture must include the blessed package, not just fields); **code-ref / closure equality and captured-lexical state** (closures are in the subset via `method`/anon subs); **weakrefs** (`Scalar::Util::weaken` — observable via liveness); **reference topology / shared-vs-copied aliasing across data structures** (two fields pointing at the SAME aref vs equal-but-distinct arefs — a real miscompile class for SoN lowering, distinct from the `$_`-aliasing already listed); **`wantarray`-void context** (the record lists scalar+list context but void is a third); **exception object identity vs string** (a thrown blessed exception vs a die-string — the record says "type + message," which flattens a blessed exception to its stringification); **return of a reference whose referent mutates after return** (return-aliasing). For the corpus that exists today (fields holding arefs/hrefs — M8/M24 take shaped refs), the reference-topology and blessed-identity classes are immediately reachable, not exotic.

The widened record is necessary progress and probably sufficient for the *tier-1 scalar/control* idioms; it is NOT yet sufficient for the reference-heavy and OO-identity idioms the corpus already contains, and the named axes lack comparison policies. So: better than round-1, still not a closed soundness story.

### R5 — Comparator (C7) classification matrix is not updated for the Perl-first stage
**Category:** Structure / Boundaries · **Impact:** Low · **Confidence:** 70%
C7's matrix is stated entirely in S/P/C terms (`P≠C`→codegen bug; `P=C≠S`→IR bug; `C refused`→underspecified IR; all-equal→pass). But the whole reframe says the day-one build is **S-vs-P only** (no C corner until Stage 3). In the Perl-first stage there is no `P≠C` row, no `C refused` row, and `P=C≠S` collapses to just `S≠P`. The architecture doc never restates what C7 actually computes in Stage 1 — i.e. the only available signal is `S vs P`, which (per R1/R3) has at least three causes (CodeGen gap, CodeGen miscompile, mis-authored hand graph) that the single-corner comparator cannot disambiguate. The doc asserts "the harness localizes the fault automatically" (the triangle property) but that property is explicitly a Stage-3 destination, yet C7 is described as if it operates from day one. This is a muddled responsibility: C7 is simultaneously "Stage-1 single-corner gap-map producer" and "Stage-3 triangle fault-localizer," and the doc only specifies the latter. The dual role the prompt asked about (gap-map vs gate) is real and under-specified at the comparator level.

---

## Direct verdicts on the 5 highest-value questions

### Q1 — Did the corrections land WITHOUT introducing new internal contradictions between the two docs?
**Verdict: Substantially YES. One residual doc-vs-doc seam.**
The Perl-first staging, C-gate, C6 split, C2 widening, and manual-surface honesty are consistent across both docs, and the phases (0–4) map cleanly to the staged acceptance criteria (Stage 1–4) with identical C-gate wording. The ONE remaining inconsistency: the plan's "Why this, why now" (line 15) still calls the seed corpus "verified to run natively under perl 5.42" and "the root-of-trust corpus already exists," while the architecture doc (C1, §corrections) concedes drivers + representative args + classification are manual per-entry work. Verified: the file does not compile as-is (R2). The plan's framing implies a run-ready root of trust; the architecture's implies a fixture needing per-entry harnessing. Reconcile the plan's "already exists / verified to run" to match the architecture's honest "needs drivers."

### Q2 — Under "directional CodeGen," can the harness distinguish a GAP (expected red) from a silent MISCOMPILE (false green)?
**Verdict: NO — and this is the new risk the reframe introduces (round-1 did not cover it).**
See R1. A gap fails loud (emit dies / won't run / blatantly wrong); a miscompile fails quiet or passes on the unobserved axis. The architecture has no discriminator: C7 does not separate "P could not be produced" from "P produced but subtly wrong," and the directional *posture* ("default reading: not implemented yet") biases triage toward dismissing quiet divergences and unaudited greens as backlog. Combined with R4's under-specified comparison policies, the directional reframe makes false greens MORE likely to be rationalized away, not less. The harness must record emit-success as an outcome distinct from behavior-match, and a "green" must mean "emitted AND ran AND matched on the full widened record" — otherwise the gap-map framing licenses certifying miscompiles as unimplemented idioms.

### Q3 — Is hand-authoring tier-1 MOP/Program (the trust root) actually adapter-free and tractable?
**Verdict: Adapter-free of the chalk-PARSER: YES. Tractable / shallow: NO.**
See R3. The production Perl path schedules the method's SoN `$graph` (`Perl.pm:234`; `EagerPinning.pm:26`), so "hand-author the MOP" means hand-wiring a Sea-of-Nodes graph with control edges (`set_control_in`), per-method hash-cons scope, and structured-control fields (`body_stmts`/`then_stmts`/`else_stmts`/`iterator`/`is_for_style`). The minimal method costs ~6 node calls (`c-schedule-walker.t`); control idioms need Region/Phi. This does not reintroduce parser coupling, but it demands deep SoN/scheduler knowledge — exactly the internals the strategy hoped to route around — and a mis-wired hand graph is an un-grounded artifact whose only backstop is perl-as-S, which then runs into the Q2 three-cause ambiguity (gap vs miscompile vs bad-hand-graph) on the PERL corner. Budget SoN-graph-authoring as the dominant tier-1 cost; the docs currently present it as low-effort.

### Q4 — Is the widened behavior record (C2) now SUFFICIENT?
**Verdict: NO — better, but still missing equivalence classes AND lacking comparison policies.**
See R4. The round-1 list (context/STDERR/hash-order/FP/dualvar/aliasing/tie/overload) was absorbed. Still missing: blessed-ref identity/class-name in object-state, code-ref/closure equality + captured state, weakrefs, reference-topology/shared-aliasing across structures (distinct from `$_` aliasing), void context, exception-object identity-vs-string. And the named axes (hash-order, FP, dualvar) are intentions without written comparison policies — an under-specified comparison silently picks a projection and produces false greens. Sufficient for tier-1 scalar/control; insufficient for the reference-heavy/OO-identity idioms the corpus already contains (M8/M24 shaped refs, every field-bearing class).

### Q5 — Any NEW architectural flaw the first pass missed, now that the design is consistent?
**Verdict: YES — three.**
(1) **R1/Q2 — gap-vs-miscompile non-discrimination**, the reframe's signature risk, entirely new. (2) **R5 — C7 comparator is specified only for the Stage-3 triangle**, but operates in Stage 1 as a single-corner (`S vs P`) instrument with three indistinguishable failure causes; its Stage-1 responsibility is unspecified, creating the gap-map-vs-gate muddle. (3) **R3's bootstrap-circularity sub-finding** — a hand-authored graph is only as trustworthy as the author's SoN fluency, with no independent equality check against intent except running it through the CodeGen under test; perl-as-S backstops the *result* but cannot tell a bad-hand-graph from a CodeGen fault. None of these are fatal; all are sharp edges the consistent design newly exposes.

---

## Hotspots (where the design will break first)

1. **Gap-vs-miscompile triage (R1)** — the first quiet `S≠P` that the operator files as "idiom not implemented yet" when it is actually a miscompile. The harness's reason-for-existing fails here silently. **Highest-risk landmine of the reframe.**
2. **Hand-authored SoN tier-1 graphs (R3)** — first control-flow idiom (D1/D2). Mis-wired control edge or unpopulated `then_stmts` → `S≠P` with three candidate causes. The trust root's authoring cost and fragility are unbudgeted.
3. **Comparison-policy gaps in C2 (R4)** — first reference-returning or two-objects-equal-on-fields idiom. An unspecified hash-order/FP/identity policy picks a projection and greens a divergence.
4. **C7 in Stage 1 (R5)** — the comparator is documented only for the triangle; its single-corner Stage-1 behavior (the actual day-one deliverable) is unspecified.
5. **Plan's "root of trust already exists / verified to run" (R2)** — `perl -c` on the fixture fails today; the per-entry driver cost is hidden in the plan even though the architecture doc concedes it.

---

## Next questions (for the author, before implementation)

1. How does the harness DISCRIMINATE a gap (emit-could-not-produce) from a miscompile (emit-produced-wrong)? Will emit-success be a first-class recorded outcome, and will a "green" require match on the FULL widened record (not just the easy projection)? (R1/Q2)
2. What are the WRITTEN comparison policies for each widened axis — hash-order normalization, FP tolerance, dualvar num-AND-str equality, blessed-ref identity, reference-topology/shared-aliasing? "Capture X" is not "compare X." (R4)
3. What is the budgeted per-idiom cost of hand-authoring a SoN `$graph` for tier-1, and how is a mis-authored hand graph distinguished from a CodeGen fault when `S≠P` (given perl backstops only the result)? (R3)
4. In Stage 1 (S-vs-P only), what EXACTLY does C7 compute and what does it output, given the triangle matrix has no `P≠C`/`C refused` rows yet? Is the Stage-1 deliverable a gap-map (list) or a gate (pass/fail), and how does one comparator serve both? (R5)
5. Will the plan's "Why this, why now" be reconciled to the architecture's honest "fixture needs drivers + representative args + classification," so "root of trust already exists / verified to run" no longer overstates the seed artifact? (R2)

---

## Evidence appendix (commands run, all read-only; `git diff --stat lib/ t/` empty before and after)

- `Perl.pm:72–116` — `generate($input)` polymorphism; MOP→`_generate_from_schedule`→hashref `{'main.pm'=>...}`; Program→`_emit_program`. **Doc-accurate.**
- `Perl.pm:195–244` — `_emit_mop_method`→`_emit_scheduled_body`→`Scheduler::EagerPinning->schedule($method)`. Production Perl path schedules the SoN graph. (R3)
- `C.pm:1717–1756` — `generate($mop)` STUB: `/* method: name */` + includes + bare `MODULE = X PACKAGE = X`. No bodies. **Doc-accurate.**
- `C.pm:1758–1786, 1852–1856` — `_generate_c_files($ir,$sa,$ctx)`; `$ctx->mop // die "_generate_c_files requires \$ctx->mop()..."`. Welded to parser Context. **Doc-accurate.**
- `JSON.pm:194–207` — `to_json(\%named_graphs)`.
- `JSON.pm:209–214` — `_deserialize_graph` header: unsupported fields "are silently dropped" (lossy). **Doc-accurate.**
- `JSON.pm:266–277` — RegexMatch/VarDecl supply defaults rather than preserving source fields (concrete lossiness).
- `JSON.pm:299–306` — `from_json` returns `\%graphs` of `Chalk::IR::Graph`, NOT MOP/Program. **Doc-accurate.**
- `EagerPinning.pm:25–27, 235` — `schedule($method)` reads `$method->graph`, `$graph->returns`; loop expansion reads `$sd->body_stmts`. Confirms hand graph must populate SoN + structured-control fields. (R3)
- `MOP/Method.pm:11–18` — `Chalk::MOP::Method` fields: `$graph` (IR::Graph), `$body`, `$factory`, `$params`. (R3)
- `t/bootstrap/c-schedule-walker.t:18–40` — minimal hand-built method graph: Start + Constant + `make_cfg('Return')` + `set_control_in` + 3× `merge` = ~6 calls for `return "hello"`. (R3)
- `perl -c t/fixtures/ir-audit-corpus.pl` → `syntax error ... near "=="` — file does NOT compile; it is a `=== TAG` fixture, not a runnable program. (R2)
- `perl -e 'use v5.42; use experimental "class"; class C { method m() { my $x=1; return $x; } } say C->new->m;'` → `1` — fragments run only when wrapped with pragma + driver + output. (R2)
- `git diff --stat lib/ t/` → empty (CLEAN-lib-t) before and after.
