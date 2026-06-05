# PAAD Architecture Review: CodeGen Behavioral Harness

**Date:** 2026-06-05
**Subject:** `docs/plans/2026-06-05-codegen-harness-architecture.md` (components C1–C8)
**Companions read:** `docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (plan/rationale), `docs/plans/2026-06-05-context-to-son-postpass-vision-validation.md` (background)
**Mode:** Design-document review of a not-yet-built verification harness. Diagnosis only, no fixes (PAAD rule).
**Reviewer stance:** Adversarial. This is a *verification* harness; an unsound oracle is the worst possible outcome, so the oracle logic gets the harshest scrutiny.

---

## Summary verdict

The **core oracle is sound**: perl-as-S is a genuinely external ground truth, and the bottom-up "verify CodeGen first against an external oracle, never against Chalk's own output" framing correctly breaks the circular-oracle trap. The S corner is the strongest part of the design and is correct as stated.

**But the architecture document materially misdescribes the two backend interfaces it is built on, and those misdescriptions are load-bearing.** Specifically:

1. The **C backend `generate($mop)` cited at `Target/C.pm:1722` is a STUB** that emits only method-name comments and an empty XS `MODULE` line — it lowers no method bodies. The real C codegen is `_generate_c_files($ir, $sa, $ctx)` at `Target/C.pm:1764`, which requires a `Chalk::IR::Program` **plus the chalk-parser's SemanticAction (`$sa`) and Context (`$ctx`)** — and asserts `$ctx->mop()` must be set (`C.pm:1853`). It does NOT take a free-standing MOP.
2. Consequently the **C corner of the triangle is structurally coupled to the untrusted chalk-parser artifacts** that the whole strategy is meant to route around. A `hand` or `bson` graph source cannot drive the *real* C backend at all through any interface the doc names; it can only drive the stub, which produces behaviorally-empty C.
3. The **graph-loader gap (C6) is worse than the doc states**: `from_json` returns a hash of `Chalk::IR::Graph` objects (`JSON.pm:299–306`), NOT a MOP and NOT a `Program`. Neither backend accepts that type. And `_deserialize_graph` *silently drops* fields Chalk nodes don't support (`JSON.pm:210–214`), so JSON round-trip is lossy — a lossy translation sitting in the trust root.

The design is salvageable and its central instinct (external oracle + dual-backend differential) is right. But as written it cannot be implemented against the cited interfaces without substantially more new plumbing than C6 alone, and the P-vs-C triangle is not a clean fault-localizer in early phases because C cannot be exercised from the trusted (hand) graph source. **Recommendation embedded in the verdicts below: gate C behind P-green (Q3 = yes), make the hand graph source produce MOP/Program directly without JSON (Q4 = yes), and treat C2's behavior record as necessary-but-insufficient (Q2).**

---

## Interface verification (Phase 1 recon — read the code, not the doc)

| Doc claim | Reality (verified at HEAD) | Verdict |
|---|---|---|
| `Target::Perl->generate($input)` takes MOP or `IR::Program` (`Perl.pm:77`) | TRUE. `Perl.pm:77–85`. MOP → `_generate_from_schedule` (returns **hashref** `{'main.pm'=>$code}`), Program → `_emit_program` (returns **string**). | Accurate, but the **return-type polymorphism** (hashref vs string) is unstated and matters for C2/C5. |
| `Target::C->generate($mop)` takes a MOP, returns C source (`C.pm:1722`) | MISLEADING. `C.pm:1722` is a **stub**: emits `/* method: name */` comments + empty `MODULE = X PACKAGE = X`. No method bodies. Real path is `_generate_c_files($ir,$sa,$ctx)` at `C.pm:1764`. | **Misdescribed.** The cited entry does not do codegen. |
| `IR::Serialize::JSON::{to_json,from_json}` (`JSON.pm:194,299`) | TRUE locations. `from_json` returns `\%graphs` of **`Chalk::IR::Graph`** (`JSON.pm:299–306`); lossy (`_deserialize_graph` drops unsupported fields, `JSON.pm:210–214`). | Locations accurate; **output type and lossiness understated** — neither backend consumes `Graph`. |
| byte-compat rig at `t/bootstrap/mop/codegen-byte-compat*.t` | TRUE. Two files exist. Schedule rig handles the hashref return specially (`codegen-byte-compat-schedule.t:76–88`), regenerates via **chalk-parser (untrusted)**, compares to **stored goldens** — never runs anything. | Accurate; doc correctly notes it compares to goldens not behavior. |
| Seed corpus `t/fixtures/ir-audit-corpus.pl` (~40 idioms) | TRUE. 156 lines, `=== TAG: desc` headers + class-fragment snippets. **No drivers, no expected values, no classification tags in-file.** Entries take params (`method m($n)`). | Accurate count; doc's "exercise spec" need is real and larger than implied (see Q5). |
| "KNOWN GAP": no `from_json` → generate-acceptable path; `chalk-emit-son-json` only goes the other way | CONFIRMED. `chalk-emit-son-json` is parse → IR → `to_json` only, and does so via the untrusted SemanticAction path. No reverse path exists. | **Accurate** — this is the doc's most honest and correct claim. |

---

## Strengths

- **S1 — The oracle is genuinely external.** C3 (run-under-perl) has zero Chalk dependency. This is the one corner that cannot be contaminated by Chalk's own bugs, and it is correctly identified as canonical. This is the design's foundation and it is sound.
- **S2 — Bottom-up verification order is correct.** "Two unverified things cannot validate each other; CodeGen-first because the corpus is small enough to blame the layer by inspection" is a valid escape from the circular-oracle trap. The reasoning in the companion plan (lines 15–21) is rigorous.
- **S3 — Perl-as-oracle removes hand-specified expected output** for mined tiers. This is the scaling property that makes tier-2/tier-3 expansion tractable and resistant to the "expected output drifts from intent" failure mode.
- **S4 — Determinism gate (C8) reuses an existing, proven invariant.** Byte-compat already exists; folding it in as an orthogonal check is low-risk and correct.
- **S5 — Explicit graph-source tagging per entry (C4)** is the right instinct: the comparator must know which producer to blame. Making the trust seam *named and per-entry* rather than implicit is good architecture.
- **S6 — Scope discipline is honest.** The "NOT in this architecture" section (no SA rewrite, no B::SoN, no parser-to-IR bridge) is disciplined and matches the deferred-work framing. The doc does not overclaim completeness.

---

## Flaws / Risks

### F1 — C-backend interface is misdescribed; the real C path is coupled to untrusted parser artifacts
**Category:** Integration / Contracts · **Impact:** High · **Confidence:** 95%
The doc points the C driver at `Target::C->generate($mop)` (`C.pm:1722`). That method is a stub (verified: emits only `/* method: name */` and an empty `MODULE` line, `C.pm:1726–1755`). The functional C codegen is `_generate_c_files($ir, $sa, $ctx)` (`C.pm:1764`), which (a) takes a `Program`, not a MOP, and (b) requires `$sa` (SemanticAction) and `$ctx` (Context) with `$ctx->mop()` set, dying otherwise (`C.pm:1853`). The C corner therefore depends on exactly the chalk-parser objects the strategy declares untrusted/deferred. **The triangle's C corner cannot be fed from a `hand` or `bson` graph source through any interface the document names.** C6 as scoped (JSON/IR→MOP) does not close this — the real C path wants `$sa`+`$ctx`, not a MOP.

### F2 — JSON interchange returns `Graph`, not MOP/Program, and is lossy
**Category:** Integration / Contracts · **Impact:** High · **Confidence:** 95%
`from_json` returns `\%graphs` of `Chalk::IR::Graph` (`JSON.pm:299–306`). Neither backend accepts a bare `Graph` — Perl wants MOP or Program, C wants Program+sa+ctx. So C6 is not "JSON→MOP," it is "JSON→Graph→(reconstruct MOP class/method/sub structure + scheduler-ready bodies)" — a much larger build. Worse, `_deserialize_graph` *silently drops* fields the Chalk node classes don't model (`JSON.pm:210–214`, e.g. RegexMatch pattern, VarDecl scope). A lossy translator placed in the trust root means a `hand` graph authored, serialized, and reloaded may not be the graph that reaches codegen — the trust root cannot be trusted to be identity-preserving. This directly motivates Q4's "skip JSON for hand."

### F3 — The triangle is not a clean fault-localizer while C is both unverified and un-drivable-from-trusted-source
**Category:** Testability / Soundness · **Impact:** High · **Confidence:** 85%
The localization matrix (`P≠C`→codegen bug; `P=C≠S`→IR bug) assumes both backends are independent lowerings of the *same trusted* graph. Early on: (a) the only graph source that can drive the *real* C path is the chalk-parser (untrusted, per F1); (b) C itself has known bugs (CV cache, segfaults — per the companion's own caveat and project memory). So an early `P≠C` carries at least three indistinguishable causes — C-codegen bug, chalk-parser-fed-different-graph-to-C-than-to-Perl, or genuine signal — collapsing the localization the matrix promises. The doc's own honest caveat (companion line 36) acknowledges the C-buggy case but not the "C can't be fed from the trusted source" case, which is the structural one.

### F4 — Behavior record (C2) under-observes Perl semantics
**Category:** Testability / Soundness-of-oracle · **Impact:** Medium · **Confidence:** 80%
"return + stdout + exception + object-state" misses divergence classes that are common in real Perl and in the subset the corpus already uses: **wantarray/context** (a method returning `scalar @list` vs the list itself — corpus A2/D3 return scalars, but list-context returns are not captured), **numeric-vs-string equality and stringification** (`0`, `0.0`, `0E0`, `"0 but true"`), **floating-point** (no tolerance model), **hash key ordering** (corpus M23 `keys %h`; ordering is randomized per-run in perl — comparing raw key order would produce false divergence), **warnings to STDERR** (captured nowhere; the record names stdout only), **aliasing / in-place mutation** (`foreach` aliasing `$_`), and **tie/overload magic**. For a *verification* oracle, an under-observing record produces **false greens** (S=P=C agree on the observed projection while diverging on an unobserved axis) — the most dangerous failure for a harness, because it certifies broken codegen as correct. This is a soundness issue, not just coverage.

### F5 — Exercise spec (C1) is a manual semantic input that partially re-introduces hand-specification
**Category:** Structure / Boundaries · **Impact:** Medium · **Confidence:** 80%
The corpus snippets are class fragments (`class C { method m($n) {...} }`) with **parameters** but no argument values (verified: D1 `m($n)`, M8 `m($r)`, M24 `m($r)` need a hashref-of-array). To produce S at all, the harness must supply *representative arguments* and a *driver*. Choosing arguments that exercise the intended branch (e.g. `$n>0` vs `$n<=0` for D1) is a manual, semantic act. The plan claims "expected behavior is never hand-specified — only classification is manual" (companion line 49), but **argument selection is a third manual axis** the architecture does not name. It does not undermine the oracle (perl still defines the *result* of whatever inputs are chosen), but it does undermine the "only classification is manual" claim and is a hidden per-entry cost, especially for tier-2 lib/ classes (Q5).

### F6 — Backend return-type asymmetry is unmodeled in the comparison contract
**Category:** Integration / Contracts · **Impact:** Low · **Confidence:** 90%
`Target::Perl->generate` returns a **string** for a Program but a **hashref** `{'main.pm'=>...}` for a MOP (`Perl.pm:84,115`); the C path returns `{files=>{...}, exported_functions=>[...], ...}` (`C.pm:1760`). The corpus entries are class fragments needing a driver wrapper before any of this is runnable. C5 ("thin wrappers ... run/compile-and-run") elides the non-trivial step of assembling these heterogeneous emission outputs into a *runnable program with a driver*. The existing byte-compat rig already had to special-case the hashref (`codegen-byte-compat-schedule.t:76`), evidence this seam is real.

### F7 — "Same IR lowered two ways" is not actually guaranteed by the architecture
**Category:** Coupling / Dependencies · **Impact:** Medium · **Confidence:** 75%
The localization argument's foundation is that P and C lower the *identical* graph. But Perl-backend takes MOP/Program while the real C path takes Program+`$sa`+`$ctx`. If the two backends are fed via different construction routes (one a reconstructed MOP, the other the live parser Context), there is no structural guarantee they received the same graph — and the JSON lossiness (F2) makes divergence plausible even from one source. The architecture asserts the equality but provides no mechanism (e.g. a single canonical in-memory graph object handed to both) to enforce it. Without that enforcement the triangle's central premise is an assumption, not an invariant.

### F8 — `do`/`eval` and subset-membership are unclassified in the seed corpus
**Category:** Error handling / Observability · **Impact:** Low · **Confidence:** 70%
The seed corpus includes M20 (`do` block) and M21 (`eval` block). Project memory states the subset's exception mechanism is try/catch and "eval is excluded in all forms." Both run under perl (verified: M20→3, M21→empty/false). The corpus thus contains entries whose subset-membership is contested, with no in-file classification tag (C1 says entries "carry a classification tag" but the fixture has none today). This is a corpus-hygiene gap that will surface as ambiguous verdicts ("did C refuse because IR is underspecified, or because the construct is out-of-subset by design?").

---

## Direct verdicts on the 5 open questions

### Q1 — Does the pluggable graph-source (C4) hide a circular-oracle risk?
**Verdict: NO circular-oracle risk in principle; the bootstrap is sound — but it is currently un-realizable for the C corner.**
The logic is valid: a `hand`-authored graph is trusted by inspection, grounds codegen mechanics, and an untrusted source (`chalk-parser`/`bson`) is explicitly tagged so a divergence is attributed to the producer, not laundered into the codegen verdict. That is genuinely non-circular. The hidden assumption the doc worries about ("an untrusted graph-source contaminates the codegen verdict") is *avoided* by the per-entry source tag — good. **However** (F1/F2), there is today no way to feed a `hand` graph to the *real* C backend (it demands parser `$sa`/`$ctx`), and the JSON path that would carry a hand graph is lossy. So the bootstrap is sound *as a design* but blocked *as an implementation* on the C side until C gets a parser-independent entry point. For the Perl backend alone, the bootstrap is realizable today.

### Q2 — Is the behavior record (C2) a sufficient observable for Perl behavioral equivalence?
**Verdict: NO — necessary but insufficient. It risks false greens.**
It misses (F4): wantarray/list-context return shape, numeric-vs-string equality and stringification edge cases, floating-point tolerance, hash-ordering nondeterminism (must be canonicalized or it produces false *reds*), STDERR/warnings (named nowhere; only stdout), aliasing/in-place mutation, and tie/overload magic. For a verification oracle the asymmetry matters: an under-observed axis yields S=P=C "agreement" on broken codegen — certifying a bug as correct. At minimum the record needs: context-sensitivity (capture both scalar and list invocation), STDERR capture, a hash/set canonicalization policy, and an FP-comparison policy. This is the second-most-important finding after the C-interface misdescription.

### Q3 — Is the dual-backend triangle a sound fault-localizer given C is itself unverified?
**Verdict: NO, not early — and "gate C behind P-green first" is the wiser sequencing.**
Per F1/F3: early on, C is both buggy *and* only drivable from the untrusted parser, so `P≠C` has at least three indistinguishable causes and `P=C` cannot be reached for hand graphs at all (C produces empty stub output or needs parser ctx). An unverified, un-trusted-source-drivable C corner produces more noise than localization signal in tiers 0–1. The companion's own caveat (line 36) concedes the buggy-C case. The cleaner sequence: (1) verify Perl backend against S on hand graphs (S=P), establishing a trusted P; (2) *then* introduce C and verify it against the now-trusted P and S. Until C has a parser-independent entry point (F1), it cannot even participate honestly. So: **gate C behind P-green.** The triangle becomes a sound localizer only after both corners are independently grounded against S.

### Q4 — Does the graph-loader adapter (C6) confound the triangle? Should `hand` produce MOP directly?
**Verdict: YES, C6-via-JSON confounds the trust root; the `hand` source should produce MOP/Program (in-memory) DIRECTLY, skipping JSON.**
Three reasons (F2): (a) `from_json` returns `Graph`, not MOP/Program — C6 is bigger than "JSON→MOP" and must reconstruct class/method structure, which is itself non-trivial new logic that can have bugs; (b) `_deserialize_graph` is *lossy* (silently drops unsupported fields) — placing a lossy transform in the trust root means the hand graph that's authored is not provably the graph that reaches codegen; (c) every line of adapter in the trust root is un-grounded new code that can itself diverge. Authoring `hand` MOP/Program objects directly in Perl keeps the trust root adapter-free and lossless. JSON interchange is valuable later (for `bson` interop), but it must not sit between the *trusted* source and codegen. Keep JSON out of the bootstrap rung.

### Q5 — Are exercise specs (C1) for tier-2 lib/ units auto-derivable, or do they need per-unit manual specs?
**Verdict: NOT generally auto-derivable; tier-2 needs per-unit manual specs — and this does partially undermine "no manual expected output," though less than it first appears.**
Auto-deriving "instantiate class X with what constructor args, call which method with which representative inputs, observe what" is the general program-synthesis-of-a-test problem; it is not tractable in general. Even the *seed* corpus already needs hand-chosen arguments for parameterized methods (F5: D1/D7 need branch-selecting `$n`; M8/M24 need shaped refs). For real lib/ classes (`:param` fields, collaborator objects, builder dependencies) the instantiate-and-exercise harness is a manual, per-unit authoring task. **Nuance that rescues the core claim:** what stays auto-derived is the *expected result* — perl still computes it from whatever inputs are supplied. So "no manual *expected output*" survives; "no manual *anything but classification*" does not. The architecture should rename this honestly: classification AND exercise-spec (driver + representative inputs) are manual; only the expected behavior is oracle-derived. For lib/ at scale this manual cost is the dominant tier-2 effort and should be planned for, not assumed away.

---

## Hotspots (where the design will break first)

1. **`Target/C.pm:1722` vs `:1764`** — the stub-vs-real-path confusion. Any implementation pointed at the doc's cited entry will silently produce empty C and "pass" trivially. **Highest-risk landmine.**
2. **`JSON.pm:210–214` + `:299`** — lossy `Graph`-returning deserialization in what the doc designates the trust root.
3. **C2 behavior record** — context/STDERR/hash-ordering/FP omissions → false greens. The oracle's blind spots.
4. **`$ctx->mop()` requirement at `C.pm:1853`** — the hard coupling of real C codegen to parser-produced Context; the structural blocker for any non-parser graph source feeding C.
5. **Seed corpus drivers** — 156 lines of class fragments with parameters and zero drivers/expected values; the gap between "fixture" and "runnable behavioral case" is unbudgeted.

---

## Next questions (for the author, before implementation)

1. Given `_generate_c_files` needs `$sa`+`$ctx` with `$ctx->mop()` set, what is the plan to give the C backend a **parser-independent entry point** (Program/MOP only)? Without it, C cannot join the triangle from hand/bson sources at all. Is building that entry in scope, or is C deferred to after P-green?
2. Will P and C be handed the **same in-memory graph object** (enforced), or reconstructed independently per backend? If the latter, how is "same IR, two lowerings" guaranteed against the JSON lossiness in F2?
3. What is the **canonicalization policy** for hash/set ordering and FP comparison in C2, and will the record capture **list-context** invocation and **STDERR**? (These determine whether the oracle can produce false greens.)
4. Should the architecture explicitly **rename the manual surface** to "classification + exercise-spec," and budget tier-2 exercise-harness authoring as the dominant lib/ cost?
5. Should the seed corpus fixture gain **in-file classification + driver + representative-input** annotations (it has none today), or will those live in a parallel spec file? Where does the M20/M21 (`do`/`eval`) subset-membership decision get recorded?

---

## Evidence appendix (commands run, all read-only; `git diff --stat lib/ t/` empty before and after)

- `Perl.pm:77–116` — `generate` polymorphism; MOP→hashref, Program→string.
- `C.pm:1717–1756` — `generate($mop)` STUB (comments + empty MODULE only).
- `C.pm:1758–1786, 1853` — `_generate_c_files($ir,$sa,$ctx)`, requires `$ctx->mop()`.
- `JSON.pm:194–207` — `to_json(\%named_graphs)`.
- `JSON.pm:210–214, 215–294, 299–306` — `_deserialize_graph` lossy; `from_json` returns `\%graphs` of `Chalk::IR::Graph`.
- `script/chalk-emit-son-json` — parse→IR→`to_json` only (one-way), via SemanticAction path.
- `t/bootstrap/mop/codegen-byte-compat-schedule.t:36–88` — regenerates via chalk-parser, compares to stored goldens, handles hashref return.
- `t/fixtures/ir-audit-corpus.pl` (156 lines) — `=== TAG: desc` + class fragments; no drivers/expected/classification; parameterized methods present.
- Ran under perl 5.42: M20 `do`→`3`; M21 `eval`→empty/false. Both execute natively.
