# Plan: CodeGen Behavioral Harness + Idiom Corpus

**Date:** 2026-06-05
**Scope:** Build a behavioral verification harness for Chalk's CodeGen, grounded in a corpus of real Perl idioms with **perl itself as the oracle**. This is a verification-asset plan, NOT an architecture rewrite. It supersedes the abandoned v3 "construction-layer reset" framing.

## Why this, why now

The session that produced this established (with evidence) a dependency-ordered trust problem:
- The **Parser** (Grammar + Aycock DFA + Leo + 4 filter semirings) is VERIFIED correct (produces a single unambiguous survivor; confirmed by instrumentation).
- **IR-generation** (SemanticAction) is KNOWN broken.
- The **IR** and **CodeGen** are UNVERIFIED — they sit downstream of the broken IR-gen, so "it produces output" is not "it produces correct output." (perigrin: "standing on sand.")

The fix is to verify bottom-up against an EXTERNAL oracle, not against Chalk's own (suspect) output. The external oracle is **perl**: "does the code Chalk generates behave the same as the source program run under perl?" The root-of-trust corpus already exists in seed form: `t/fixtures/ir-audit-corpus.pl` (~40 categorized `feature class` idioms with human-obvious intended results, verified to run natively under perl 5.42).

**Verification order (each layer grounded on something already trusted):**
1. CodeGen — verified against the idiom corpus + perl behavior. (THIS PLAN.)
2. (later) B::SoN / optree front-end — verified using the now-trusted CodeGen as the instrument.
3. (later) IR-generation bridge — verified against the now-trusted IR target.

CodeGen-first is deliberate: two unverified things cannot validate each other. The corpus is small and behaviorally-known enough that when generated output diverges from perl, a human can read the one-line idiom and tell WHICH layer broke — that is what breaks the circular-oracle trap.

## What this plan builds (and explicitly does NOT)

BUILDS:
- A **behavioral-equivalence harness**: source program → run under perl (capture behavior) vs. Chalk CodeGen output → run → diff. perl is the oracle; never "match Chalk's prior output."
- An **expanded idiom corpus** (tier 1 seed → mined from lib/ → sampled from CPAN), each entry carrying a perl-derived expected behavior.

DOES NOT (out of scope here):
- No rewrite of SemanticAction / IR-generation (paused).
- No B::SoN integration (a later phase, once CodeGen is the trusted instrument).
- No parser-to-IR bridge decision (deferred; it becomes well-posed once the IR target is verified).

## Open seam (named honestly): where does the graph come from to drive CodeGen?

To run CodeGen we need an IR/MOP graph per corpus program. Today the only producers are (a) Chalk's parser+SemanticAction (the broken/unverified path) and (b) B::SoN (itself unverified). The corpus does NOT eliminate this — it makes it **auditable**: for the smallest tier-1 idioms the correct graph is hand-confirmable, so CodeGen's mechanics can be certified on hand-trusted graphs first; as CodeGen earns trust, it becomes the probe that finds a graph-producer's bugs (a corpus idiom diverging from perl, isolatable to the producer because CodeGen is trusted). Tier-1 smallness is what keeps each bootstrap rung small enough to trust. This seam is the reason CodeGen is verified FIRST.

## The corpus — three tiers, escalating coverage, each with a perl-grounded oracle

The discipline that keeps the corpus trustworthy as it grows: **expected behavior for mined programs is never hand-specified — it is whatever perl does when the program runs.** Only classification is manual.

- **Tier 1 — hand-written idioms (`ir-audit-corpus.pl`, ~40):** tiny, categorized (decls, side-effects, assignments, control flow, returns, fields, methods), human-obvious result. Trusted by INSPECTION. This is the root that grounds CodeGen first.
- **Tier 2 — mined from `lib/`:** real, complex 5.42 `feature class` — and the eventual self-hosting workload (capstone: regenerate the Earley parser). Trusted by PERL behavior (libraries need exercise harnesses — instantiate, call methods, observe; not "run and print").
- **Tier 3 — sampled from CPAN:** maximal real-world breadth / adversarial diversity. Role is coverage-discovery + NEGATIVE testing (most CPAN is outside Chalk's subset). Classification per program: (a) in-subset → must compile + behave like perl; (b) out-of-subset → must be cleanly rejected; (c) undecided feature → flag for a scope decision.

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

### Phase 2 — Corpus expansion: sample CPAN
- Sample real CPAN modules; classify each (in-subset / reject / scope-decision). Build the negative-test set (must-reject) alongside the must-compile set.
- Use as a coverage-discovery instrument: what real-world idioms exist that tier 1+2 missed.

### Phase 3 — Capstone: self-hosting via the harness
- The hardest tier-2 target: the Earley parser + semirings. CodeGen output must produce a parser that parses like the original. This is the definitive CodeGen certification (and, later, the gate for the whole optree→IR→codegen path once a front-end is trusted).

## Acceptance criteria
- A repeatable harness: `program → perl behavior` vs `program → CodeGen → run`, diffing behavior, with perl as the sole oracle.
- Tier-1 corpus: all ~40 idioms green (CodeGen output behaves like perl).
- Tier-2 corpus: a growing set of lib/ units with classified results; divergences attributed to a specific layer.
- Negative set: out-of-subset programs cleanly rejected.
- Determinism preserved (byte-identical codegen).
- Capstone tracked as the eventual gate, not a near-term requirement.

## Relationship to the kept evidence docs
- `2026-06-05-context-to-son-postpass-vision-validation.md` — established the 3-pieces decomposition + that disambiguation is IR-independent (why CodeGen/IR can be developed against an external oracle). Still valid context.
- `2026-06-05-clean-control-construction-design.md` / `-control-construction-alignment-audit.md` / `-rebuild-deletion-readiness-audit-pass3/4.md` — findings about the (now-paused) IR-generation layer. Kept as record; not active work.
