# Architecture: CodeGen Behavioral Harness

**Date:** 2026-06-05
**Companion to:** `docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (the plan: what/why). This doc is the HOW — components, interfaces, data flow, file locations. Intended for a PAAD agentic-architecture review before implementation.

## Goal (one sentence)

Build a repeatable harness that, for each corpus program, compares three behaviors — **S** (source run under perl), **P** (Chalk Perl-codegen output, run), **C** (Chalk C/XS-codegen output, run) — using perl (S) as the ground-truth oracle and the P-vs-C agreement as an automatic IR-vs-codegen fault localizer.

## Existing interfaces the harness builds on (verified at HEAD)

- **Perl backend:** `Chalk::Bootstrap::Perl::Target::Perl->generate($input)` — `$input` is either a `Chalk::MOP` (→ `_generate_from_schedule`, runs each body through `Chalk::IR::Scheduler::EagerPinning`) or a `Chalk::IR::Program` (→ `_emit_program`). Returns Perl source string. (`Target/Perl.pm:77-85`)
- **C/XS backend:** `Chalk::Bootstrap::Perl::Target::C->generate($mop)` — takes a MOP, returns C source (+ headers). (`Target/C.pm:1722`)
- **IR JSON interchange:** `Chalk::IR::Serialize::JSON::{to_json($named_graphs), from_json($json_string)}` (`JSON.pm:194,299`). `from_json` deserializes a SoN graph (Chalk's own, or B::SoN's compatible subset).
- **MOP:** `Chalk::MOP` is the graph-of-graphs root (per-class/method/sub IR graphs). It is the codegen input contract.
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

## Open questions for the PAAD review (where I most want challenge)
1. **Is the graph-source plug (C4) the right seam, or does pluggability hide the circular-oracle risk?** The whole strategy rests on `hand` graphs grounding codegen before `chalk-parser`/`bson` are trusted. Is that bootstrap sound, or is there a hidden assumption that an untrusted graph-source contaminates the codegen verdict?
2. **Is the behavior record (C2) a sufficient observable?** Does "return + stdout + exception + object-state" actually capture Perl behavioral equivalence, or are there divergence classes (tie magic, ordering, numeric stringification, aliasing) it misses?
3. **Loader adapter (C6) risk:** building JSON→MOP introduces a new translation that itself could have bugs and confound the triangle. Should the hand graph-source produce MOP *directly* (skip JSON) to keep the trust root adapter-free?
4. **C-backend-unverified caveat:** is treating C as a triangle corner sound when C is known-buggy, or does an unverified C corner produce more noise than localization signal early on? Should C be gated behind P-green first?
5. **Exercise specs (C1) for tier-2 lib/ units:** is auto-deriving "how to invoke a library class" tractable, or does it need per-unit manual specs (and does that undermine "no manual expected output")?
