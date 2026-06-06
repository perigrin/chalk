# Chain Review: `codegen-harness` milestone

**Date:** 2026-06-06
**Reviewer role:** crochet:chain-review (alignment coverage lens + pushback plan-quality lens), pre-execution gate.
**Chain:** milestone `codegen-harness`, 12 issues (11 code + 1 doc), produced by crochet:refinement.
**Spec ("PRD"):**
- `docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (plan: 4 staged phases + staged acceptance criteria)
- `docs/plans/2026-06-05-codegen-harness-architecture.md` (architecture: C1–C8, gap-vs-miscompile classifier, Perl-first/C-gated, behavior-record widening, F7)
**Mode:** Diagnosis only. No edits to `lib/`, `t/`, or `refs/zhi/`. Working tree confirmed clean at finish.

---

## 1. Top-line verdict

**READY TO EXECUTE** — with 3 low-severity advisories the executor should fold in, none blocking.

The chain is well-aligned to the spec and quality-sound. Every staged acceptance criterion maps to ≥1 issue; every issue traces to a stated plan requirement; the dependency DAG reflects real technical constraints; the C corner is genuinely gated on Phase-1-green plus a free-standing-graph→C path; there are ZERO out-of-scope issues (no SemanticAction/IR-gen rewrite, no B::SoN, no parser-bridge, no subset-rejection enforcement); positive AND negative scenarios with backtick verification commands are present on every issue. The four named invariants all PASS.

The two "epic suspects" (Phase 1 complete-CodeGen, Phase 4 self-host-Earley) are honestly framed as directional/capstone milestones rather than disguised as 2-hour tasks — but their unbounded nature is real and is the basis of advisory P-1 below.

---

## 2. Alignment findings (coverage lens)

### 2.1 Requirements coverage — COMPLETE

Every staged acceptance criterion and phase deliverable is covered:

| Spec requirement | Issue(s) covering it |
|---|---|
| Stage-1 harness (S vs P, widened record) | `f091` (oracle/C3+C2), `f0aa` (comparator/C2+C7), `f0c3` (hand graphs/C4), `f0db` (wire C5+C8) |
| Stage-1 gap map | `f0f4` (produce tier-1 gap map) |
| Stage-2 complete-to-green | `f10c` (Phase 1 tier-1 green) |
| Stage-2 determinism (byte-identical) | `f0db` (C8 gate), re-checked in `f10c` negative AC |
| Stage-2 tier-2 (lib/) + tier-3 (pedagogical) | `f124` (tier-2 mine), `f13d` (tier-3 harvest) |
| Stage-3 C corner (gated) | `f156` (free-standing graph→C), `f171` (triangle + F7) |
| Stage-3 same-IR-two-lowerings (F7) | `f171` positive + negative AC (refaddr identity) |
| Stage-4 capstone (self-host Earley) | `f188` |
| Widened behavior record (C2) axes | `f091` enumerates all axes + negative AC requiring a written policy per axis |
| Gap-vs-miscompile classifier (C7) | `f0aa` (core), reinforced in `f0f4`, `f10c`, `f124`, `f13d`, `f188` |
| Extract+wrap step for `=== TAG` corpus | `f091` ("EXTRACT one tier-1 idiom and WRAP it") + negative AC on malformed extraction |
| Hand-author MOP directly, not JSON | `f0c3` (positive: "no JSON"; negative: regression guard that build does NOT route through `from_json`) |
| Corpus tiers hand/lib/pedagogical | `f0c3`/`f10c` (tier-1), `f124` (tier-2), `f13d` (tier-3) |
| Operational guide (run/add/read) | `019e9a2e` doc issue |

No UNCOVERED items.

### 2.2 Scope compliance — CLEAN, zero phantom features

Every issue traces to a stated plan requirement. I specifically searched for the four OUT-OF-SCOPE temptations and found ZERO issues for any of them:
- **No SemanticAction/IR-gen rewrite issue.** `f0c3` hand-authors graphs directly; nothing rewrites SA.
- **No B::SoN integration issue.** Correctly absent; `bson` remains a deferred slot.
- **No parser-to-IR bridge issue.** Absent.
- **No subset-rejection enforcement issue.** `f124`/`f13d` explicitly treat classification (in-subset/reject/scope-decision) as a *labeling step only* and call out in-issue that "this harness does NOT enforce subset-rejection (parser-scope concern, deferred)." This matches plan line 100 (PAAD F-N1) exactly.

### 2.3 Dependency direction — CORRECT

Verified edges from `--format json`:
- **Three Phase-0 heads genuinely independent:** `f091` (oracle) and `f0c3` (hand graphs) both declare no `blocked_by` (parallel heads). `f0aa` (comparator) is `blocked_by f091` only because it consumes the `BehaviorRecord` type — a real type dependency, correct. The plan calls oracle/comparator/hand-graphs the three independent heads; the refinement correctly serialized comparator-after-oracle on the genuine type dependency rather than forcing false parallelism. Acceptable and more honest than three bare parallel heads.
- **Wire (`f0db`) blocked_by all three** (`f091`, `f0aa`, `f0c3`) — correct; it joins oracle+comparator+hand-graph.
- **Gap map (`f0f4`) blocked_by wire** — correct; can't map gaps until the S-vs-P loop closes.
- **Phase 1 (`f10c`) blocked_by gap map** — correct; the gap map is the work-list.
- **C corner GATED:** `f156` (free-standing C path) `blocked_by f10c` (Phase-1 green) — the gate is honored at the DAG level. `f171` (triangle) `blocked_by f156`. So the C corner cannot start until Perl-green AND the free-standing path exists. **PASS on invariant (c).**
- **Capstone (`f188`) blocked_by f124** (tier-2) — correct; Earley is the hardest tier-2 target.
- **Doc issue (`019e9a2e`) blocked_by f0f4** (gap map) — correct; the guide documents the rig + gap-map artifact, both of which must exist first.

No implausible or reversed edges.

### 2.4 AC completeness — COMPLETE (SQE negatives persisted)

Every one of the 11 code issues has BOTH a `### Positive Scenarios` and a `### Negative Scenarios` block, each scenario carrying a backtick verification command. The SQE-added negatives are present and substantial — e.g. `f0aa` carries six negatives centered on the false-green/laundering failure modes; `f091` carries five (malformed extraction, non-determinism, under-specified spec, unobserved-axis, exception path); `f171` carries the F7 refaddr-identity negative. The doc issue (`019e9a2e`) has positive + negative scenarios; two of its negatives use prose assertions ("assert each test path named in the guide exists on disk") rather than a literal backtick command — acceptable for a doc issue, noted as advisory A-3.

---

## 3. Pushback findings (plan-quality lens), ranked

### P-1 (LOW–MED) — Two issues are honestly-framed epics, not 2-hour tasks; sizing variance is extreme but acknowledged

`f10c` ("complete CodeGen to tier-1 green") and `f188` ("self-host the Earley parser") are open-ended completion efforts whose true size is bounded only by how broken CodeGen turns out to be — which the gap map (`f0f4`) does not yet exist to reveal. Next to them sit genuine ~2-hour tasks (`f091`, `f0aa`). This is real size variance.

**However, this is not a defect to block on:** the plan itself frames CodeGen as DIRECTIONAL and these phases as MILESTONES, not day-one expectations (plan lines 78, 88, 91). `f10c`'s steps are explicitly iterative ("Repeat RED-GREEN-COMMIT for each remaining GAP idiom in gap-map order"), so the issue is structured as a loop over a work-list, not a monolith. `f188` is labeled CAPSTONE and gated behind tier-2 infrastructure.

**Advisory:** the executor should expect `f10c` and `f188` to each spawn many commits (and possibly child issues as the gap map reveals scope), and should NOT treat their single-issue framing as a promise of single-sitting completion. Consider, at execution time, splitting `f10c` along the gap-map category axis (decls/side-effects/assignments/control/returns/fields/methods) once the gap map is in hand — but this cannot be done before `f0f4` runs, so it correctly stays deferred. Recording the expectation here satisfies plan-discipline ("write down where it is deferred to").

### P-2 (LOW) — `f10c` quietly absorbs deferred Phase-0 work (control-shape hand graphs)

`f0c3` (Phase 0 hand graphs) deliberately scopes to "SMALLEST data-only idioms," deferring Region/Phi control-shape graphs. `f10c` then carries, inside a Phase-1 issue, the work of authoring those control-shape hand graphs (step 5: "add hand graphs + tier-1 entries for control-shape idioms (D1 if/else, D2 while) with real Region/Phi wiring"). This is consistent with the architecture doc's "add control-shape graphs incrementally" guidance (round-2 correction), so it is not a contradiction — but it means `f10c` is doing both *graph authoring* and *emitter completion*, compounding the sizing concern in P-1. The architecture's round-2 note that "control idioms need Region/Phi wiring" and that one input (`body_stmts` seeding) is itself prototype means this hand-graph work is non-trivial IR-internals work, not a thin add. Flagging so the executor budgets for it; not a blocker.

### P-3 (LOW) — Gap-map category enum is narrower than the actual corpus taxonomy

The gap-map issues (`f0f4`, and the verification greps in `f10c`/doc) organize by `decls / side-effects / assignments / control / returns / fields / methods` — which maps to corpus groups A/B/C/D/E/F/I. But the seed corpus (`t/fixtures/ir-audit-corpus.pl`, verified) also contains groups G (postfix deref/subscript), H (map/grep/sort/anon-sub block-builtins), J (regex), K, L, and a large M group (25 entries). Under the chain's current category enum these idioms would land without a named section, or be folded into an existing bucket. This is an *ambiguity*, not a coverage gap (the gap map is explicitly "coverage-organized, not exhaustive-from-day-one," and tier-1 starts with the smallest idioms). **Advisory:** the gap-map artifact should either widen its category list to cover G/H/J/K/L/M or state explicitly that those groups are out-of-tier-1-scope-for-now, so coverage isn't silently overstated by a too-small denominator (which `f0f4`'s own "empty corpus / shrunk denominator" negative AC is trying to guard against).

### P-4 (LOW) — "substantially green" gate threshold is undefined

The C-corner gate (`f156`, `f171`) and the plan both use "Perl-codegen substantially green" as the trigger. Neither the plan nor the chain defines *substantially* (a percentage? all data-only idioms? all of tier-1?). `f156`'s negative AC ("C path built against a tier-1 idiom that already passes S=P, not one still in GAP") gives an operational floor — C work must target an already-green idiom — which is a reasonable de-facto definition and partially mitigates the vagueness. **Advisory:** pin "substantially green" to a concrete bar (suggest: "all tier-1 data-only idioms PASS, zero MISCOMPILE in tier-1") when `f10c` completes, so the Phase-3 gate is a fact not a judgment call.

### Feasibility — PASS (no infeasible issues)

I verified the load-bearing code-reality claims the chain depends on, against HEAD:
- **C `generate($mop)` is a comment-only stub** — confirmed (`Target/C.pm`, emits `/* method: name */` + empty `MODULE` line, no bodies). `f156` correctly opens against this stub and its negative AC asserts a real method body must be present.
- **Real C path welded to SA+Context** — confirmed: `_generate_c_files($ir, $sa, $ctx)` exists and `$ctx->mop() // die "..."` is enforced (`C.pm:1852-1853`). `f156` correctly frames the free-standing path as the prerequisite plumbing and its negative AC asserts NO Context argument is required.
- **Perl `generate` polymorphic over MOP/Program** — confirmed (`Target/Perl.pm:77`, MOP→`_generate_from_schedule`, else Program→`_emit_program`). `f0db` uses this.
- **`EagerPinning` runs per body** — confirmed (`_generate_from_schedule` runs each body through it). `f0c3`/`f10c` correctly require hand MOPs to carry a real SoN graph with control edges, and `f0c3`'s negative AC asserts an under-wired statement-list graph FAILS EagerPinning loudly. This matches the architecture round-2 correction that the trust root is "adapter-free but NOT shallow."
- **`from_json` lossy** — `to_json`/`from_json` exist in `JSON.pm`; `f0c3`'s "no JSON" regression guard is well-founded.
- **Corpus seed exists** — `t/fixtures/ir-audit-corpus.pl` present, `===`-delimited (78 delimiter lines, ~39 idioms across groups A–M), not runnable as a single program — matching the plan's extract+wrap premise.
- **Reference rigs exist** — `codegen-hand-constructed-mop.t`, `codegen-byte-compat.t`, `codegen-byte-compat-schedule.t` all present.

Every feasibility-critical assumption holds. The hardest issue (`f156`, free-standing C path) correctly acknowledges the stub-and-weld reality rather than assuming a clean interface.

### Omissions — none material

Implied work is named: extract+wrap tooling (`f091`), per-axis normalization POLICIES not just intentions (`f091` positive AC requires a *written* policy per axis; negative AC rejects a named-but-unimplemented axis), tier-2 manual-driver/arg axis (`f124`, explicitly per PAAD Q5), tier-3 provenance/license (`f13d` creates `PROVENANCE.md` + ingestion-fails-without-license negative AC), error handling (compile-failure-as-GAP and "verdict-even-on-crash" negatives across `f0db`/`f156`/`f188`). The behavior-record normalization policies are required as artifacts, not just intentions — directly addressing the architecture round-2 "intentions without written comparison policies" risk.

### Contradictions — none

No issue contradicts a plan invariant. Spot checks:
- perl-as-sole-oracle: every oracle/verdict AC compares against perl-run S; `f10c`'s negative AC explicitly forbids matching "the PRIOR Chalk sketch output." No self-comparison anywhere.
- directional gap-map-first: `f0f4` produces the map before `f10c` consumes it; correct order.
- gap-vs-miscompile = alarm not backlog: enforced in `f0aa` and re-asserted as "MISCOMPILE fails loud / never laundered as backlog" in `f0f4`, `f10c`, `f124`, `f13d`, `f188`, and the doc issue.

---

## 4. Per-invariant pass/fail

| Invariant | Verdict | Evidence |
|---|---|---|
| **(a) perl is the SOLE oracle** — no issue compares against Chalk's own prior output | **PASS** | All S captured via `RunUnderPerl`; `f10c` negative AC explicitly forbids anchoring to prior sketch output; no issue references a stored-Chalk-output oracle. (Existing byte-compat goldens are reused only for the *determinism* gate C8, not as a behavioral oracle — correct.) |
| **(b) CodeGen is DIRECTIONAL** — gap-map first; comparator classifies GAP vs MISCOMPILE | **PASS** | `f0f4` (gap map) precedes `f10c` (completion); `f0aa` implements the GAP/MISCOMPILE classifier as load-bearing, with the laundering failure modes as negatives. |
| **(c) C corner GATED on Phase-1-green + free-standing-graph→C path** | **PASS** | `f156 blocked_by f10c`; `f171 blocked_by f156`. `f156` negative AC requires building against an already-S=P-green idiom. DAG enforces the gate structurally. |
| **(d) ZERO issues for SemanticAction / B::SoN / parser-bridge / subset-rejection** | **PASS** | None present. `f124`/`f13d` treat classification as labeling only and state in-issue that rejection-enforcement is deferred parser-scope work. |

---

## 5. Bottom line

The chain faithfully renders the converged plan and its PAAD-hardened corrections (Perl-first, C-gated, gap-vs-miscompile classifier, hand-author-directly-not-JSON, behavior-record widening with written policies, F7 same-IR-two-lowerings, classification-as-labeling-only). It is execution-ready. The advisories (P-1 epic-sizing expectation, P-2 control-shape graph load inside `f10c`, P-3 gap-map category breadth vs the full corpus taxonomy, P-4 "substantially green" threshold) are refinements to apply during execution, not gates to clear before starting. Recommend proceeding to crochet:execute, beginning with the two independent Phase-0 heads (`f091` oracle, `f0c3` hand graphs) in parallel.
