# Plan: CodeGen Behavioral Harness + Idiom Corpus

**Date:** 2026-06-05
**Scope:** Build a behavioral verification harness for Chalk's CodeGen, grounded in a corpus of real Perl idioms with **perl itself as the oracle**. This is a verification-asset plan, NOT an architecture rewrite. It supersedes the abandoned v3 "construction-layer reset" framing.

## Why this, why now

The session that produced this established (with evidence) a dependency-ordered trust problem:
- The **Parser** (Grammar + Aycock DFA + Leo + 4 filter semirings) is VERIFIED correct (produces a single unambiguous survivor; confirmed by instrumentation).
- **IR-generation** (SemanticAction) is KNOWN broken.
- The **IR** and **CodeGen** are UNVERIFIED — they sit downstream of the broken IR-gen, so "it produces output" is not "it produces correct output." (perigrin: "standing on sand.")

**Framing (assume CodeGen is DIRECTIONAL, not complete):** the current CodeGen (both Perl and C backends) is a *sketch of the right shape*, not a finished implementation — the C backend's `generate` is literally a stub (PAAD finding F1). Therefore the harness is a **completeness instrument FIRST, a regression gate SECOND.** Early red results are not "subtle bugs" — the default reading is "CodeGen does not implement this idiom yet, or implements it provisionally." The harness's first deliverable is a **gap map** (which idioms CodeGen can't yet handle, ranked by the corpus = by real idiom frequency); only once CodeGen is substantially complete does "all corpus green" become a meaningful regression gate. The effort is therefore not "verify an existing CodeGen" but "**use the harness + corpus as specification-by-example to COMPLETE CodeGen idiom-by-idiom, with perl as the spec.**" Never treat current CodeGen output as a reference — it is an incomplete sketch; perl is the only thing we compare to.

The fix is to verify bottom-up against an EXTERNAL oracle, not against Chalk's own (suspect) output. The external oracle is **perl**: "does the code Chalk generates behave the same as the source program run under perl?" The root-of-trust corpus already exists in seed form: `t/fixtures/ir-audit-corpus.pl` (~40 categorized `feature class` idioms with human-obvious intended results, verified to run natively under perl 5.42).

**Verification order (each layer grounded on something already trusted):**
1. CodeGen — verified against the idiom corpus + perl behavior. (THIS PLAN.)
2. (later) B::SoN / optree front-end — verified using the now-trusted CodeGen as the instrument.
3. (later) IR-generation bridge — verified against the now-trusted IR target.

CodeGen-first is deliberate: two unverified things cannot validate each other. The corpus is small and behaviorally-known enough that when generated output diverges from perl, a human can read the one-line idiom and tell WHICH layer broke — that is what breaks the circular-oracle trap.

## What this plan builds (and explicitly does NOT)

BUILDS:
- A **behavioral-equivalence harness**: source program → run under perl (capture behavior) vs. Chalk CodeGen output → run → diff. perl is the oracle; never "match Chalk's prior output."
- A **dual-backend differential cross-check** (see below): lower the SAME IR through BOTH the Perl backend and the C/XS backend, run both, and compare all three of {source-under-perl, Perl-codegen-output, C/XS-codegen-output}.
- An **expanded idiom corpus** (tier 1 hand idioms → mined from lib/ → pedagogical/canonical sources), each entry carrying a perl-derived expected behavior.

### Dual-backend differential cross-check — localizes IR-vs-CodeGen failures automatically

The same IR (MOP + SoN graph) is lowered two independent ways. Let P = behavior of the Perl-codegen output, C = behavior of the C/XS-codegen output, S = behavior of the source under perl (the ground truth). The three must agree (S = P = C); the *disagreements* are the diagnostic:
- **P ≠ C** (backends disagree with each other, same IR input) → bug is in ONE of the codegens; the IR is exonerated. Failure localized to a backend without human inspection.
- **P = C ≠ S** (backends agree with each other but not with perl) → both faithfully lowered a WRONG graph → bug is UPSTREAM in the IR; codegens exonerated.
- **C/XS chokes where Perl-codegen passes** → the C backend must commit to types/memory/struct-layout (the StructPromotion path), so it acts as a stricter type/shape checker than perl ever would; a graph it rejects but Perl-codegen accepts signals an UNDERSPECIFIED IR the Perl backend was papering over.

This mechanizes the "blame the layer" property the corpus gives by inspection: agreement-between-backends isolates IR-vs-codegen automatically. Honest caveat: the C/XS backend is itself unverified at the start (known XS-codegen bugs: CV cache, edge-case segfaults), so early `C ≠ P` will sometimes just be "C-codegen is broken here" rather than an IR signal — that's fine, the triangle ALSO verifies the C backend (against P + perl); we simply trust no single corner at the outset and lean on tier-1 smallness to keep it debuggable.

DOES NOT (out of scope here):
- No rewrite of SemanticAction / IR-generation (paused).
- No B::SoN integration (a later phase, once CodeGen is the trusted instrument).
- No parser-to-IR bridge decision (deferred; it becomes well-posed once the IR target is verified).

## Open seam (named honestly): where does the graph come from to drive CodeGen?

To run CodeGen we need an IR/MOP graph per corpus program. Today the only producers are (a) Chalk's parser+SemanticAction (the broken/unverified path) and (b) B::SoN (itself unverified). The corpus does NOT eliminate this — it makes it **auditable**: for the smallest tier-1 idioms the correct graph is hand-confirmable, so CodeGen's mechanics can be certified on hand-trusted graphs first; as CodeGen earns trust, it becomes the probe that finds a graph-producer's bugs (a corpus idiom diverging from perl, isolatable to the producer because CodeGen is trusted). Tier-1 smallness is what keeps each bootstrap rung small enough to trust. This seam is the reason CodeGen is verified FIRST.

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

## Phases

### Phase 0 — Behavioral harness skeleton (tier 1)
- A test rig: for each tier-1 idiom, run under perl 5.42, capture behavior (return value / stdout / exception). This is the ground-truth half — needs no Chalk at all and is trivially correct.
- Hand-confirm IR/MOP graphs for the smallest idioms (the bootstrap root of trust for CodeGen mechanics).
- Wire: trusted graph → CodeGen → emit Perl → run → diff vs perl behavior.
- Gate: CodeGen mechanics certified on hand-trusted graphs across the tier-1 categories. Determinism (byte-identical codegen) checked as part of the rig.

### Phase 1 — Corpus expansion: mine lib/
- Programmatically extract compilable units from `lib/Chalk/**` (per-class / per-method) as tier-2 corpus entries.
- For each: capture perl behavior via an exercise harness (instantiate, call with representative inputs). Where a unit can't be exercised meaningfully in isolation, note it.
- Run each through the (now mechanically-trusted) CodeGen path; classify divergences (CodeGen bug vs. graph-producer bug vs. unsupported construct).
- This is where the perl-as-oracle discipline pays off: no human specifies expected output for 22k lines; perl does.

### Phase 2 — Corpus expansion: pedagogical & canonical sources (tier 3)
- Harvest complete, runnable, intended-to-work snippets from the tier-3 sources (Modern Perl, Learning-Perl-style, perlfaq/perldoc, perl's own `t/`, rosettacode, Perl Weekly Challenge). Classify each (in-subset / reject / scope-decision); confirm per-source license/provenance.
- Capture perl behavior for each; run through CodeGen + dual-backend cross-check. These broaden body-idiom coverage beyond what lib/ exercises.
- (CPAN deferred — see corpus tiers note.)

### Phase 3 — Capstone: self-hosting via the harness
- The hardest tier-2 target: the Earley parser + semirings. CodeGen output must produce a parser that parses like the original. This is the definitive CodeGen certification (and, later, the gate for the whole optree→IR→codegen path once a front-end is trusted).

## Acceptance criteria (staged — CodeGen is directional, so these are MILESTONES, not day-one expectations)

**Stage 1 — harness + gap map (the instrument exists):**
- A repeatable harness: `program → perl behavior (S)` vs `program → Perl-codegen → run (P)`, diffing on the widened behavior record (see architecture doc C2: return + context/wantarray + stdout + STDERR/warnings + exception + object-state + hash-order-normalized + FP-tolerant + dualvar + aliasing/tie/overload). perl (S) is the sole oracle. (C corner deferred per PAAD: Perl-first.)
- A **gap map**: for the tier-1 corpus, which idioms CodeGen handles vs. doesn't-yet, ranked. This is the FIRST deliverable — red is expected and is the work-list, not a failure.

**Stage 2 — complete CodeGen to green, idiom by idiom:**
- Drive tier-1 to all-green (S = P) by COMPLETING CodeGen against the gap map, perl as spec. Then tier-2 (lib/) + tier-3 (pedagogical), growing the green set.
- Negative set: out-of-subset programs cleanly rejected.
- Determinism preserved (byte-identical Perl codegen).

**Stage 3 — add the C corner (gated):** once Perl-codegen is substantially green AND a free-standing-graph → C path exists (today the real C backend needs Program+SA+Context; the named `generate($mop)` is a stub), add C as the third corner for automatic IR-vs-codegen localization. Enforce same-IR-two-lowerings (F7).

**Stage 4 — capstone:** self-host the Earley parser via the harness (CodeGen output produces a parser that parses like the original). The eventual definitive certification, not a near-term requirement.

## Relationship to the kept evidence docs
- `2026-06-05-context-to-son-postpass-vision-validation.md` — established the 3-pieces decomposition + that disambiguation is IR-independent (why CodeGen/IR can be developed against an external oracle). Still valid context.
- `2026-06-05-clean-control-construction-design.md` / `-control-construction-alignment-audit.md` / `-rebuild-deletion-readiness-audit-pass3/4.md` — findings about the (now-paused) IR-generation layer. Kept as record; not active work.
