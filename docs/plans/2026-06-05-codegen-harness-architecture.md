# Architecture: CodeGen Behavioral Harness

**Date:** 2026-06-05
**Companion to:** `docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (the plan: what/why). This doc is the HOW — components, interfaces, data flow, file locations. Intended for a PAAD agentic-architecture review before implementation.

## Goal (one sentence)

Build a repeatable harness that, for each corpus program, compares three behaviors — **S** (source run under perl), **P** (Chalk Perl-codegen output, run), **C** (Chalk C/XS-codegen output, run) — using perl (S) as the ground-truth oracle and the P-vs-C agreement as an automatic IR-vs-codegen fault localizer.

## Existing interfaces the harness builds on (verified at HEAD)

> **CORRECTIONS from the PAAD architecture review (2026-06-05, `paad/architecture-reviews/2026-06-05-codegen-harness-architecture-review.md`) — verified against code. The original interface descriptions below were materially wrong; the corrected facts are load-bearing and change the harness design (see §"Review corrections" at the end).**

- **Perl backend:** `Chalk::Bootstrap::Perl::Target::Perl->generate($input)` — `$input` is a `Chalk::MOP` (→ `_generate_from_schedule`, runs each body through `Chalk::IR::Scheduler::EagerPinning`) or a `Chalk::IR::Program` (→ `_emit_program`). Returns Perl source string. (`Target/Perl.pm:77-85`) **[VERIFIED correct.]**
- **C/XS backend:** `Chalk::Bootstrap::Perl::Target::C->generate($mop)` (`Target/C.pm:1722`) is a **STUB** — it emits only `/* method: name */` comments and an empty XS `MODULE` line, NO method bodies (`C.pm:1733-1746`). The REAL C codegen is `_generate_c_files($ir, $sa, $ctx)` (`C.pm:1764`), which takes a `Program` **plus the chalk-parser's SemanticAction instance and Context** and asserts `$ctx->mop()` is set (`C.pm:1853`). **It is structurally welded to the untrusted chalk-parser path** — a `hand` or `bson` graph CANNOT drive the real C backend through any existing interface. This breaks the "C corner" of the triangle as originally drawn.
- **IR JSON interchange:** `Chalk::IR::Serialize::JSON::{to_json($named_graphs), from_json($json_string)}` (`JSON.pm:194,299`). **`from_json` returns a hash of name → `Chalk::IR::Graph` — NOT a MOP or Program** (`JSON.pm:299-306`), and `_deserialize_graph` **silently drops unsupported fields** (`JSON.pm:210-214`) — i.e. it is LOSSY. So the loader adapter (C6) must *assemble a MOP/Program from loose per-method graphs* (bigger than "JSON→MOP") and sits as lossy plumbing in the trust root.
- **MOP:** `Chalk::MOP` is the graph-of-graphs root (per-class/method/sub IR graphs). It is the Perl-backend codegen input contract (the C backend's real path wants Program+SA+Context, not a free MOP — see above).
- **Pattern to learn from:** `t/bootstrap/mop/codegen-byte-compat*.t` — existing golden/byte-compat rigs (determinism + emission), but they compare to STORED goldens, not to perl behavior. The harness differs: oracle is perl, not stored output.

## The KNOWN GAP this architecture must close

The codegen entry (`generate`) requires a **`Chalk::MOP` or `Chalk::IR::Program`** — an in-memory object graph. But the interchange format is **JSON** (`from_json`). There is today **no path** from `from_json`'s output to a `generate`-acceptable MOP/Program. `script/chalk-emit-son-json` only goes the other way (parse → IR → `to_json`). So a **graph-loader adapter** (JSON/IR → MOP/Program suitable for `generate`) is a required new component. This is the single biggest new piece of plumbing.

## Components

```
                              ┌──────────────────────────────────────────┐
                              │  CORPUS (one entry = one Perl program +   │
                              │  an exercise spec: how to invoke + observe)│
                              └───────────────┬──────────────────────────┘
                                              │
        ┌─────────────────────────────────────┼─────────────────────────────────────┐
        │                                      │                                      │
        ▼ (oracle path, no Chalk)              ▼ (graph path)                          │
  ┌───────────────┐                    ┌──────────────────┐                           │
  │ RUN-UNDER-PERL│                    │ GRAPH SOURCE      │  (pluggable; see below)   │
  │  → behavior S │                    │  → MOP / Program  │                           │
  └───────────────┘                    └────────┬─────────┘                           │
                                                 │                                     │
                                  ┌──────────────┴──────────────┐                      │
                                  ▼                             ▼                       │
                          ┌──────────────┐             ┌──────────────┐                │
                          │ Target::Perl │             │ Target::C    │                │
                          │ ->generate   │             │ ->generate   │                │
                          └──────┬───────┘             └──────┬───────┘                │
                                 ▼                            ▼                        │
                          ┌──────────────┐             ┌──────────────┐                │
                          │ RUN Perl out │             │ COMPILE+RUN  │                │
                          │  → behavior P│             │ C out → C    │                │
                          └──────┬───────┘             └──────┬───────┘                │
                                 └────────────┬───────────────┘                        │
                                              ▼                                         │
                                   ┌─────────────────────┐                             │
                                   │ TRIANGLE COMPARATOR  │◄────────────────────────────┘
                                   │ assert S==P==C;      │   (S from oracle path)
                                   │ classify divergence  │
                                   └─────────────────────┘
```

### C1 — Corpus entry model
Each entry is: (a) a Perl source program (a complete `feature class` unit or runnable snippet); (b) an **exercise spec** — how to drive it and observe behavior. For tier-1 idioms this is "call `C->new->m`, capture return"; for tier-2 lib/ units it's an instantiate-and-call harness; for tier-3 it's the snippet's own output. Entries carry a **classification** tag (in-subset / reject / scope-decision) and a **graph-source** tag (which producer supplies its MOP — see C4).

### C2 — Behavior capture (the observable contract)
A normalized "behavior" record so S/P/C are comparable: return value(s), stdout, exit/exception (type + message), and — for classes — post-call object state (field values via introspection). Comparison is structural on this record, not raw text. This is the same record shape regardless of which corner (S/P/C) produced it.

### C3 — Run-under-perl (oracle path)
Runs the corpus source under perl 5.42, applies the exercise spec, emits a behavior record S. Zero Chalk dependency — trivially correct ground truth. Output is the canonical expected behavior; never hand-specified.

### C4 — Graph source (PLUGGABLE — this is the bootstrap seam)
Produces a `Chalk::MOP` (or `Program`) for a corpus entry to feed `generate`. Pluggable backends, used in trust-order:
- **`hand`** — hand-authored MOP/graph for the smallest tier-1 idioms. The ROOT of trust; certifies codegen mechanics.
- **`chalk-parser`** — Chalk's own parser+SemanticAction (the paused/broken producer). Available but UNTRUSTED; its divergences are expected and are themselves a signal about IR-gen.
- **`bson`** — B::SoN/optree (deferred; wired later once codegen is trusted, then B::SoN is validated THROUGH this harness).
The graph-source is explicit per entry so the comparator knows which producer to blame.

### C5 — The two codegen drivers
Thin wrappers over `Target::Perl->generate` and `Target::C->generate`, plus run/compile-and-run, producing behavior records P and C. Reuses the existing backends unchanged. The C driver also captures "C backend refused / failed to compile" as a distinct outcome (the underspecified-IR signal).

### C6 — Graph-loader adapter (NEW PLUMBING — the gap from §"KNOWN GAP")
JSON-or-deserialized-IR → a `generate`-acceptable MOP/Program. Needed so non-`chalk-parser` graph sources (hand, bson) can drive codegen at all. Bridges `from_json` output to the MOP/Program contract.

### C7 — Triangle comparator + fault classifier
Compares S, P, C and classifies per the plan's matrix: `P≠C` → codegen bug; `P=C≠S` → IR bug; `C refused where P passed` → underspecified IR; all-equal → pass. Emits a per-entry verdict with the implicated layer and the graph-source.

### C8 — Determinism gate
Each backend's emission run twice; assert byte-identical (reuses the byte-compat pattern). Orthogonal to behavior; guards the existing determinism invariant.

## Data flow / sequencing per entry
1. Capture S (oracle path, C3).
2. Obtain MOP/Program from the entry's graph-source (C4), via the loader adapter if needed (C6).
3. Drive both backends (C5) → P, C (with byte-compat check C8).
4. Comparator (C7) → verdict {pass | layer-blamed-divergence}.

## What is NOT in this architecture (boundaries)
- No SemanticAction/IR-gen rewrite (paused). The `chalk-parser` graph source is *used as-is* and *not trusted*.
- No B::SoN integration yet (the `bson` graph source is a defined slot, not built here).
- No parser-to-IR bridge.
- The harness does not "fix" codegen; it MEASURES it. Fixes are downstream work the harness then re-verifies.

## Open questions — ANSWERED by the PAAD review (2026-06-05)

Full report: `paad/architecture-reviews/2026-06-05-codegen-harness-architecture-review.md`. Verdict: **the core oracle is sound (perl-as-S is genuine external ground truth; verify-CodeGen-first correctly breaks the circular trap), but the backend interfaces were misdescribed in load-bearing ways (see corrections above).** The five answers:

1. **Graph-source circular-oracle risk?** No risk in principle — per-entry source tagging avoids contamination — BUT currently un-realizable for the C corner (the real C backend needs the untrusted SA+Context, finding F1). The Perl corner is fine.
2. **Behavior record sufficient? — NO.** It misses wantarray/context, STDERR/warnings, hash-ordering, floating-point tolerance, numeric-vs-string equality, aliasing, tie/overload. Risk of **FALSE GREENS** — the worst outcome for a verifier. The behavior record (C2) must be widened to capture these, or each becomes a silent escape.
3. **Loader adapter / skip JSON for hand? — YES, the `hand` graph-source should produce MOP/Program DIRECTLY**, not via JSON. `from_json` is lossy (drops fields) and returns loose Graphs, not MOP/Program — JSON in the trust root is un-grounded. Reserve JSON for the (later) `bson` path.
4. **C as a triangle corner while unverified? — NO, not early. GATE C BEHIND P-GREEN.** Agreed with the doc's own hedge — and it's STRUCTURAL, not just "C is buggy": the C backend is a stub at the named interface and the real path is welded to the chalk-parser. Phase the harness as **Perl-only triangle first (S vs P)**; add the C corner only once a free-standing-graph C path exists and P is green.
5. **Auto-derive exercise specs for tier-2? — NO, tier-2 needs per-unit MANUAL specs** (driver + representative arguments). The "no manual expected output" claim SURVIVES (expected behavior stays perl-derived), but driver/arg selection is a third manual axis the plan must name — it is not "no manual work," it is "no manual *expected output*."

## Review corrections — what this changes about the architecture

- **The triangle is Perl-first, not dual-backend-from-day-one.** Start S vs P (oracle vs Perl-codegen). The C corner (and its IR-vs-codegen localization benefit) is a LATER addition gated on (a) P green and (b) a real free-standing-graph → C path existing (today the C backend's real entry needs Program+SA+Context). Until then, IR-vs-codegen localization relies on the corpus's tier-1 smallness (human blame), not the C corner.
- **C6 splits:** the `hand` trust root builds MOP/Program DIRECTLY (no JSON, no loader); a JSON/Graph→MOP assembler is needed only for the deferred `bson` path and is explicitly untrusted plumbing then.
- **C2 (behavior record) must widen** to context/wantarray, STDERR+warnings, hash-order normalization, FP tolerance, dualvar (num vs str), aliasing, tie/overload — else false greens.
- **C1 exercise specs are partly manual for tier-2** (driver + args); only expected *output* is oracle-derived. The plan's "no manual expected output" wording is correct but must not be mistaken for "no manual work."
- **F7 (Med):** "same IR, two lowerings" is asserted but not ENFORCED — the harness must guarantee both backends consume the identical graph object, or the triangle's localization logic is invalid. (Moot until the C corner is added, but record it.)

## Review corrections — round 2 (PAAD re-review 2026-06-05, `...-architecture-review-2.md`)

Round-1 corrections were verified to have landed faithfully (all four interface facts re-confirmed against code: C `generate` stub C.pm:1722; real C path welded C.pm:1764/1852; `from_json` returns loose Graphs lossy JSON.pm:299/210; Perl `generate` polymorphism). The two docs are mutually consistent. Re-review found one HIGH-impact NEW risk the reframe itself introduced, plus refinements:

- **HIGH — Gap-vs-miscompile non-discrimination (the reframe's new false-green risk).** Under "CodeGen is directional, red is expected backlog," the operator is biased to file every `S≠P` as "not implemented yet." But two very different causes both surface as `S≠P`: (a) a GAP — CodeGen couldn't emit / emitted obviously-incomplete code (fails loud); (b) a MISCOMPILE — CodeGen emitted plausible-but-WRONG code (passes the parts the behavior record checks, wrong on an unobserved axis = a FALSE GREEN; or diverges and gets mis-filed as backlog). **C7 (the comparator/classifier) MUST have an explicit rule separating GAP from MISCOMPILE** — e.g. did CodeGen emit code at all / did it emit code for every construct in the source / did it warn-or-mark-unsupported, vs. did it emit complete-looking code that ran and diverged. A miscompile is a CORRECTNESS ALARM, never backlog. This is the exact failure a verifier exists to prevent; the directional framing must not be allowed to launder it. Without this rule, the harness's whole purpose (catch miscompiles) is defeated.
- **Hand-authored trust root is adapter-free of the parser but NOT shallow.** Verified: the Perl emitter runs each body through `EagerPinning` (`Target/Perl.pm:88`), so a hand MOP must carry a real SoN GRAPH with control edges + schedule-meta, not a statement list. Minimal `return "x"` ≈ ~6 node calls; control idioms need Region/Phi wiring; one input (`body_stmts` seeding) is itself prototype. So building the trust root requires deep IR-internals knowledge — tractable but more work than "hand-author a graph" implied. Tier-1 should start with the SMALLEST data-only idioms and add control-shape graphs incrementally.
- **C2 still missing equivalence classes** beyond round-1's list: blessed-ref identity, code-ref/closure equality, weakrefs, reference-topology/shared-aliasing, void context, exception-object-vs-string. AND the named axes (hash-order/FP/dualvar) are *intentions without written comparison policies* — each needs a concrete normalization/tolerance rule, or it's a latent false-green.
- **C7 day-one single-corner ambiguity:** at Stage 1 (S vs P only) a divergence has THREE indistinguishable causes — gap, miscompile, or mis-authored hand graph. The gap-vs-miscompile rule above addresses two; the third (mis-authored hand graph) is why tier-1 graphs must be minimal + cross-checked (e.g. author the graph, emit, AND eyeball the emitted Perl matches the idiom's intent) before trusting a divergence as a CodeGen signal.
