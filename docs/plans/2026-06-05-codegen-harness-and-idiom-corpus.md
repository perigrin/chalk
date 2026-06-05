# Plan: CodeGen Behavioral Harness + Idiom Corpus

**Date:** 2026-06-05
**Scope:** Build a behavioral verification harness for Chalk's CodeGen, grounded in a corpus of real Perl idioms with **perl itself as the oracle**. This is a verification-asset plan, NOT an architecture rewrite. It supersedes the abandoned v3 "construction-layer reset" framing.

## Why this, why now

The session that produced this established (with evidence) a dependency-ordered trust problem:
- The **Parser** (Grammar + Aycock DFA + Leo + 4 filter semirings) is VERIFIED correct (produces a single unambiguous survivor; confirmed by instrumentation).
- **IR-generation** (SemanticAction) is KNOWN broken.
- The **IR** and **CodeGen** are UNVERIFIED — they sit downstream of the broken IR-gen, so "it produces output" is not "it produces correct output." (perigrin: "standing on sand.")

**Framing (assume CodeGen is DIRECTIONAL, not complete):** the current CodeGen (both Perl and C backends) is a *sketch of the right shape*, not a finished implementation — the C backend's `generate` is literally a stub (PAAD finding F1). Therefore the harness is a **completeness instrument FIRST, a regression gate SECOND.** The harness's first deliverable is a **gap map** (which idioms CodeGen can't yet handle, organized by corpus category/coverage — NOT by frequency: the corpus is one-snippet-per-idiom with no count weighting, so "ranked by frequency" would require adding frequency data the corpus does not have; treat the gap map as coverage-organized work-list); only once CodeGen is substantially complete does "all corpus green" become a meaningful regression gate. The effort is therefore not "verify an existing CodeGen" but "**use the harness + corpus as specification-by-example to COMPLETE CodeGen idiom-by-idiom, with perl as the spec.**" Never treat current CodeGen output as a reference — it is an incomplete sketch; perl is the only thing we compare to.

**CRITICAL guard (PAAD re-review): a red is NOT automatically "just a gap."** The directional framing introduces a false-green risk — two different causes both look like `S≠P`: a **GAP** (CodeGen couldn't emit / emitted obviously-incomplete code — fails loud, IS backlog) vs a **MISCOMPILE** (CodeGen emitted plausible-but-WRONG code that ran and diverged, or is wrong on an axis the behavior record doesn't observe = a FALSE GREEN). A miscompile is a **correctness alarm, never backlog.** The harness comparator MUST classify gap-vs-miscompile explicitly (did it emit code at all / for every construct / mark-unsupported, vs. emitted complete-looking code that diverged) — see architecture doc C7. Do not let "red is expected" launder a miscompile.

The fix is to verify bottom-up against an EXTERNAL oracle, not against Chalk's own (suspect) output. The external oracle is **perl**: "does the code Chalk generates behave the same as the source program run under perl?" The root-of-trust corpus exists in SEED form: `t/fixtures/ir-audit-corpus.pl` (~40 categorized `feature class` idioms with human-obvious intended results). **Precise status (PAAD re-review correction):** the FILE is a `=== TAG`-delimited catalog of snippets, NOT a runnable program (`perl -c` fails on the `===` lines). The individual idioms DO run correctly under perl 5.42 when extracted and wrapped with a pragma + driver (spot-verified: D3→6, C2→3, A5→7). So Phase 0 must include an EXTRACTION+WRAP step (snippet → runnable program with a driver); "the corpus is the oracle" means "each extracted+wrapped idiom, run under perl, is the oracle" — not "run the file."

**Verification order (each layer grounded on something already trusted):**
1. CodeGen — verified against the idiom corpus + perl behavior. (THIS PLAN.)
2. (later) B::SoN / optree front-end — verified using the now-trusted CodeGen as the instrument.
3. (later) IR-generation bridge — verified against the now-trusted IR target.

CodeGen-first is deliberate: two unverified things cannot validate each other. The corpus is small and behaviorally-known enough that when generated output diverges from perl, a human can read the one-line idiom and tell WHICH layer broke — that is what breaks the circular-oracle trap.

## What this plan builds (and explicitly does NOT)

BUILDS (in stages — the harness GROWS, it is not built all at once; CodeGen is directional, so we build the instrument and use it to COMPLETE CodeGen):
- **First: a Perl-first behavioral-equivalence harness** — source program → run under perl (capture behavior S) vs. Chalk Perl-codegen output → run → diff (behavior P). perl (S) is the oracle; never "match Chalk's prior output" (which is an incomplete sketch anyway). This alone produces the **gap map** that drives CodeGen completion.
- **An expanded idiom corpus** (tier 1 hand idioms → mined from lib/ → pedagogical/canonical sources), each entry carrying a perl-derived expected behavior.
- **Later (gated): the C corner**, turning the S-vs-P comparison into the full S/P/C triangle below — added only once Perl-codegen is substantially green AND a free-standing-graph → C path exists (PAAD finding F1: today `Target::C->generate($mop)` is a STUB; the real C codegen is welded to the chalk-parser SA+Context, so a hand/bson graph cannot drive it yet).

### The S/P/C triangle — the DESTINATION (Stage 3), not the day-one build

Once both backends can lower the SAME IR, let P = Perl-codegen behavior, C = C/XS-codegen behavior, S = source-under-perl (ground truth). The three must agree; disagreements localize the fault automatically:
- **P ≠ C** → bug in ONE codegen; IR exonerated.
- **P = C ≠ S** → both lowered a WRONG graph; bug is UPSTREAM in the IR; codegens exonerated.
- **C/XS chokes where Perl passes** → C commits to types/memory/struct-layout (StructPromotion), acting as a stricter type/shape checker; a graph it rejects but Perl accepts signals an UNDERSPECIFIED IR.

This mechanizes the "blame the layer" property the corpus gives by inspection. **Until the C corner exists, layer-blame relies on the corpus's tier-1 smallness (human reads the one-line idiom), not on backend agreement.** Caveat for when C is added: the C backend is itself directional/unverified, so early `C ≠ P` may just be "C-codegen incomplete here" rather than an IR signal — the triangle verifies all three corners; trust no single corner at the outset.

DOES NOT (out of scope here):
- No rewrite of SemanticAction / IR-generation (paused).
- No B::SoN integration (a later phase, once CodeGen is the trusted instrument).
- No parser-to-IR bridge decision (deferred; it becomes well-posed once the IR target is verified).

## Open seam (named honestly): where does the graph come from to drive CodeGen?

To run CodeGen we need an IR/MOP graph per corpus program. Today the only producers are (a) Chalk's parser+SemanticAction (the broken/unverified path) and (b) B::SoN (itself unverified). The corpus does NOT eliminate this — it makes it **auditable**: for the smallest tier-1 idioms the correct graph is hand-authored DIRECTLY as MOP/Program (PAAD: not via lossy JSON), so CodeGen can be COMPLETED and certified on hand-trusted graphs first; as CodeGen becomes trusted, it becomes the probe that finds a graph-producer's bugs (a corpus idiom diverging from perl, isolatable to the producer because CodeGen is trusted). Tier-1 smallness is what keeps each bootstrap rung small enough to trust. This seam is the reason CodeGen is completed-and-verified FIRST — and the reason early reds are read as CodeGen gaps (directional, not done), not graph-producer bugs, while we are still on hand-authored graphs.

## The corpus — three tiers, escalating coverage, each with a perl-grounded oracle

The discipline that keeps the corpus trustworthy as it grows: **expected behavior for mined programs is never hand-specified — it is whatever perl does when the program runs.** Only classification is manual.

- **Tier 1 — hand-written idioms (`ir-audit-corpus.pl`, ~40):** tiny, categorized (decls, side-effects, assignments, control flow, returns, fields, methods), human-obvious result. Trusted by INSPECTION. This is the root that grounds CodeGen first. Also the primary source for the `feature class` MOP corpus.
- **Tier 2 — mined from `lib/`:** real, complex 5.42 `feature class` — and the eventual self-hosting workload (capstone: regenerate the Earley parser). Trusted by PERL behavior (libraries need exercise harnesses — instantiate, call methods, observe; not "run and print"). Second source for MOP-shaped programs.
- **Tier 3 — pedagogical & canonical-idiom sources (in-subset, high-yield):** small, complete, idiomatic, behaviorally-clear examples of how Perl is *meant* to be written — covering body-level idioms (refs, closures, data structures, regex, string/list ops, control flow) we wouldn't think to hand-write (fixes tier-2's blind spot: lib/ only exercises idioms Chalk's own authors used). Sources:
  - chromatic's *Modern Perl* (onyxneon.com free CC edition) — canonical modern-Perl idioms.
  - "Learning Perl"-style teaching examples.
  - perlfaq / perldoc "how do I do X" snippets — very idiomatic, small, in-subset-heavy.
  - perl's own distribution test suite (`t/` in the perl source) — the most authoritative "this is what Perl must do" corpus; behaviorally precise (much is out-of-subset / tests the interpreter, so classify hard, but the in-subset slice is gold).
  - rosettacode Perl entries — same task across many idioms (diversity).
  - Perl Weekly Challenge solutions — small self-contained programs with known expected output (excellent behavioral-oracle fit).
  Caveats (apply to all tier-3 sources): (a) CLASSIFY per example (in-subset / reject / scope-decision) — these cover the whole language; (b) extraction is semi-manual — pull COMPLETE, runnable, intended-to-work snippets (skip fragments and "don't do this" anti-examples); (c) provenance — confirm each source's license permits including derived examples; (d) WEAK on `feature class` MOP (predate it / teach Moo/Moose/bless-OO) — complement but do not solve the MOP-corpus need (that stays tiers 1+2). Trusted by PERL behavior once extracted.

  **CPAN is DROPPED for now** — highest classification effort, lowest in-subset yield; revisit later for breadth + negative testing once tiers 1-3 are solid.

## Phases (map to the staged acceptance criteria above)

The throughline: CodeGen is **directional**. Each phase first MAPS gaps (run corpus → perl-oracle diff → gap list), then COMPLETES CodeGen against those gaps (perl as spec), re-verifying to green. We are building CodeGen *with* the harness, not auditing a finished CodeGen.

### Phase 0 — Perl-first harness skeleton + tier-1 gap map (Stage 1)
- Behavior-capture half: for each tier-1 idiom, run under perl 5.42, capture the **widened behavior record** (return + context/wantarray + stdout + STDERR/warnings + exception + object-state + hash-order-normalized + FP-tolerant + dualvar + aliasing/tie/overload — per architecture C2). Ground truth; no Chalk dependency.
- Graph half: hand-author MOP/Program **directly** (NOT via JSON — PAAD finding: `from_json` is lossy and returns loose Graphs, not MOP/Program) for the tier-1 idioms. This is the bootstrap root of trust.
- Wire: hand graph → Perl-codegen → run → diff vs perl. Determinism (byte-identical Perl codegen) checked in the rig.
- **Deliverable = the GAP MAP:** which tier-1 idioms CodeGen handles vs. doesn't-yet. Red is EXPECTED and is the work-list — not a failure.

### Phase 1 — Complete CodeGen to tier-1 green (Stage 2 begins)
- Work the gap map: complete/fix Perl-codegen idiom-by-idiom until tier-1 is all S=P green. perl is the spec; never the current sketch output.

### Phase 2 — Corpus expansion → drive further completion (Stage 2 continues)
- **Mine lib/** (tier 2): extract compilable units; capture perl behavior via per-unit exercise specs (driver + representative args are partly MANUAL — PAAD finding Q5; only the expected *output* is oracle-derived). Run through the harness; the new reds extend the gap map; complete CodeGen against them. This is the self-hosting workload building toward the capstone.
- **Pedagogical/canonical sources** (tier 3): harvest complete runnable snippets (Modern Perl, Learning-Perl-style, perlfaq/perldoc, perl's own `t/`, rosettacode, Perl Weekly Challenge); classify (in-subset/reject/scope-decision); confirm license/provenance; capture perl behavior; broaden coverage beyond what lib/ exercises. (CPAN deferred.)

### Phase 3 — Add the C corner (Stage 3, GATED)
- Prerequisite: Perl-codegen substantially green AND a free-standing-graph → C path exists (today the real C backend needs Program+SA+Context; `generate($mop)` is a stub). Build that path, then add C as the third triangle corner for automatic IR-vs-codegen localization. Enforce same-IR-two-lowerings (architecture F7).

### Phase 4 — Capstone: self-host the Earley parser (Stage 4)
- The hardest tier-2 target: the Earley parser + semirings. CodeGen output must produce a parser that parses like the original. The definitive CodeGen certification (and, later, the gate for the whole optree→IR→codegen path once a front-end is trusted).

## Acceptance criteria (staged — CodeGen is directional, so these are MILESTONES, not day-one expectations)

**Stage 1 — harness + gap map (the instrument exists):**
- A repeatable harness: `program → perl behavior (S)` vs `program → Perl-codegen → run (P)`, diffing on the widened behavior record (see architecture doc C2: return + context/wantarray + stdout + STDERR/warnings + exception + object-state + hash-order-normalized + FP-tolerant + dualvar + aliasing/tie/overload). perl (S) is the sole oracle. (C corner deferred per PAAD: Perl-first.)
- A **gap map**: for the tier-1 corpus, which idioms CodeGen handles vs. doesn't-yet, ranked. This is the FIRST deliverable — red is expected and is the work-list, not a failure.

**Stage 2 — complete CodeGen to green, idiom by idiom:**
- Drive tier-1 to all-green (S = P) by COMPLETING CodeGen against the gap map, perl as spec. Then tier-2 (lib/) + tier-3 (pedagogical), growing the green set.
- Determinism preserved (byte-identical Perl codegen).
- (NOTE — out of scope for THIS harness, PAAD F-N1: "out-of-subset programs cleanly rejected" is a PARSER/front-end concern, not a CodeGen-harness one — S=perl has no subset notion and P=codegen-over-hand-graphs never authors a graph for out-of-subset input, so nothing here owns subset-rejection. The actor is the parser+SemanticAction, which this plan defers. Corpus-entry CLASSIFICATION (in-subset / reject / scope-decision) stays here as a labeling step; ENFORCING rejection belongs to a future parser-scope plan.)

**Stage 3 — add the C corner (gated):** once Perl-codegen is substantially green AND a free-standing-graph → C path exists (today the real C backend needs Program+SA+Context; the named `generate($mop)` is a stub), add C as the third corner for automatic IR-vs-codegen localization. Enforce same-IR-two-lowerings (F7).

**Stage 4 — capstone:** self-host the Earley parser via the harness (CodeGen output produces a parser that parses like the original). The eventual definitive certification, not a near-term requirement.

## Relationship to the kept evidence docs
- `2026-06-05-context-to-son-postpass-vision-validation.md` — established the 3-pieces decomposition + that disambiguation is IR-independent (why CodeGen/IR can be developed against an external oracle). Still valid context.
- `2026-06-05-clean-control-construction-design.md` / `-control-construction-alignment-audit.md` / `-rebuild-deletion-readiness-audit-pass3/4.md` — findings about the (now-paused) IR-generation layer. Kept as record; not active work.
