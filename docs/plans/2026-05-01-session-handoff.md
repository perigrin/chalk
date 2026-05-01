# Session Handoff — 2026-05-01

**Purpose:** Bridge document for resuming Chalk maturity audit work in a fresh
session. The current session is at a natural stopping point: Phase A.2's
Tier-A is closed, the parser performance investigation is complete, and S1
(set-reuse registry deletion) experiment confirmed the next architectural
decision direction.

This doc gives the next session enough context to start without re-deriving
the picture.

## What's done

### Phase A.2 — three audits + synthesis (closed)

- `docs/plans/2026-04-25-audit-1-grammar-findings.md` (commit `8399ec0e`)
  — 17 grammar punch-list items
- `docs/plans/2026-04-25-audit-2-semirings-findings.md` (commit `0166a24e`
  + addendum `0c19b8fb` + Bug 3 reframe addendum from `1374cabb`) — 4 filter
  bugs, 4 contract violators, TI completeness gaps
- `docs/plans/2026-04-25-audit-3-mop-ir-findings.md` (commit `736281f1`)
  — migration is ~30%, not ~80% as CLAUDE.md previously claimed
- `docs/plans/2026-04-25-audit-5-semiring-contract-reality-findings.md`
  (commit `c612735e`) — 5 findings about the semiring layer's actual contract
- `docs/plans/2026-04-25-phase-a2-synthesis.md` (commit `57763d4e`, with
  decisions added `b648cb46`, Bug 4 integrated `fd50cf6e`, doc-drift
  reconciliation across multiple commits) — tiered remediation roadmap

### Tier-A complete (every Tier-1 item)

| Item | Commit | What it did |
|---|---|---|
| Bug 4 walker fix | `1ec8cae1` | TI walker stops at completed sub-CallExpression boundaries |
| MOP Phase 3a-infra | `885beb87` | promoted `$graph` and `$scope` to Context fields, deleted cfg backchannel |
| Bug 1 fix | `a1013c4f` | `type_satisfies(X, 'List')` permissive for Perl flattening |
| Bug 5 fix | `d7432d43` | walker depth tracking; never prune at root |
| A1 (`$,` placeholder) | `28f8d991` | grammar admits anonymous-skip signature param |
| Fix A (`->@[range]`) | `ac0e66ce` | grammar + Precedence bracket reset for postfix slice |
| Fix B (`$#{ expr }`) | `ff8f1f49` | grammar admits block-form array-length-of-deref |
| A3 walker hygiene | `fc4524ef`, `45d8c131` | applied `_is_completed_sub_expr` prune to all 9 unfixed walker callers |
| A4 Bug 3 | `25364037`, `1374cabb` | Precedence dead-code removed; AssignmentExpression and TernaryExpression now explicitly right-associative |

### Performance investigation (Phase B)

- `docs/plans/2026-04-30-parser-performance-investigation.md` (commit
  `3f855845` + S1 addendum `5c917293`)
- S1 implementation: `bc733b24` (set-reuse registry deletion)
- **Verdict**: `chart_has` per-call cost stays super-linear after S1 dead
  infrastructure cleanup. The memory-pressure-on-the-chart hypothesis
  stands. Next meaningful lever is **C2: C-backed chart with contiguous
  packed backing store**, not pure-Perl optimization.

### Documentation infrastructure

- `docs/architecture/perl-type-system-practical.md` (commit `ab1b3be1`)
- `docs/architecture/perl-type-system-formal.md` (commit `ab1b3be1`)
- These are the spec for what TypeInference should be modeling. References
  wired into `parsing-pipeline.md §6`, `phase-a2-synthesis.md` Decision 5,
  and the `pvm_typeinference_reference` memory note (`8d6e4b14`).
- `~/.claude/agents/code-auditor.md` — read-only auditor agent created
  during Phase A.2. Reusable for future audits.

## Recorded decisions

1. **Decision 4 (semiring contract):** strengthen the contract. All four
   violators (Precedence, Structural, TypeInference, SemanticAction.zero)
   wrap their carriers in Contexts. Structural's ~100x allocation cost is
   accepted. Migration ordering: SemanticAction → TypeInference → Precedence
   → Structural. Documented in `2026-04-24-semiring-contract-drift.md`'s
   2026-04-25 addendum. **Not started.**

2. **Decision 5 (TypeInference direction):** flow-typing à la TypeScript,
   NOT Hindley-Milner. `pvm` (Go, CST-based) is the algorithmic prior art;
   the type-system papers in `docs/architecture/` are the vocabulary
   reference. Lives between MOP Phase 3c and Phase 5. **Not started.**

3. **Decision 6 (DepChaser retirement):** lands with MOP Phase 6, not after
   Phase 8. **Not started.**

## Bookmarked architectural questions

These are open and should NOT be resolved in passing:

1. **Type hierarchy: Position A (formal paper, mutual circularity) vs.
   Position C (linear `Scalar <: List`).** The formal paper treats Scalar
   and List as siblings under Any with mutual circularity resolved via
   fixed-point semantics. The round-trip-preserving framing would make
   `Scalar <: List` a linear hierarchy. Bug 1's current
   `type_satisfies(X, 'List') → true` workaround is a stopgap that becomes
   structural under linear-hierarchy and remains a workaround under formal-
   paper. Settling this affects the formal paper, the practical guide,
   `TypeLibrary.pm`'s `%PARENT` table, and flow-typing's design.

2. **C-backed chart migration (C2 in the perf doc).** The S1 experiment
   confirmed memory pressure is the real bottleneck. C-backed chart would
   address it but requires deciding bootstrap strategy (how does Chalk's
   own toolchain build C with the parser-under-development) and packed
   backing store design.

3. **Resuming the C-library + XS-shims path.** Per perigrin's framing
   during the perf discussion: this approach was paused (not abandoned)
   because foundations had to be correct first. Tier-A closure has moved
   foundations forward materially. The next session should re-evaluate
   whether to resume.

## Active punch lists (work not done, prioritized)

### TypeLibrary signature audit punch list

`docs/plans/2026-04-27-typelibrary-signature-audit-findings.md` (commit
`82608344`). 22 of 28 signatures have at least one defect. Top items:

- `keys`/`values`/`each` first arg `Hash` → `List` (151 sites in `lib/`,
  3-line trivial change). Confirmed leverage; pending.
- `defined` `min_arity` 1 → 0 (840 sites of latent issue, mostly not
  triggering).
- `pop`, `shift`, `chr`, `ref` same `min_arity` defect.
- `Num` → `Int` for integer-only positions (`splice`, `substr`, `split`
  LIMIT). Backward-compatible.
- `split` first arg `Regex` → permissive (Bug 6 anchor). Needs union-type
  vocabulary or interim `Any`.
- 2 vocabulary gaps: union types, context-dependent return types.

### Performance follow-ups

Per the perf investigation:

- **C2 (C-backed chart with packed backing store):** the S1-confirmed
  next lever. Substantial design work. Couples to "resume C-library/XS
  path" decision.
- **S2 (GC tuning):** Aycock safe-set GC reclaims only 4.6-6% of
  positions; conservative `safe_to_free` may be too cautious. Pure-Perl
  win possible but smaller than C2.
- **S3 (terminal clustering):** infrastructure exists, only 0.7% of
  scans use it. Activate or remove.
- **S4 (Context allocation reduction):** 334K `Context::new` calls on
  the largest profiled file. Caching candidates.

### MOP migration phases

Per Audit 3 (`736281f1`) and Decision 6:

- **Phase 3a-migration**: retires the `cfg_state()` shim that 3a-infra
  left behind. Touches Actions.pm and SemanticAction.
- **Phase 3b** (if/else Phis), **3c** (loop Phis + revives
  `ir-program-pipeline.t`/`ir-sub-info-pipeline.t`).
- **Phase 4** (codegen reads MOP, migrates `body()` callers).
- **Phase 5** (optimizer signatures).
- **Phase 6** (deletes Shim/`compat_class`/legacy structs +
  DepChaser retirement per Decision 6).
- **Phases 7-8** (cleanup).

### Other

- 4 dead IR node types (`Slice`, `Length`, `Stringify`, `Yada`) — Audit 3
  finding. Cleanup candidate.
- `${EXPR}` block-form scalar deref — discovered during Fix B as adjacent
  gap.
- 2 conformance files still timeout: `Optimizer/StructPromotion.pm`,
  `Perl/Target/C.pm`. Bug 3 fixed; remaining issue is parse speed on
  large files (C2 territory).

## Methodology lessons (for the next session)

1. **Probe-driven isolation works.** Multiple audit passes corrected
   prior framings by re-probing under current state. The pattern: the
   audit (or brief) names a trigger; the RCA verifies it under current
   HEAD. Five or six instances in this session where trigger
   identification was wrong on first pass.

2. **Brief skepticism is now standard.** Future briefs should explicitly
   instruct agents to re-probe rather than trust upstream framings. The
   `code-auditor` subagent (`~/.claude/agents/code-auditor.md`) encodes
   this.

3. **Latent-rejection probes before any walker/semiring fix.** A3's
   walker hygiene fix retired Findings 7 and 8 plus 7 latent walker
   callers. Bug 5's fix unmasked one latent issue (split). A4's Bug 3
   fix preemptively retired a latent TernaryExpression issue. Pattern:
   if a fix touches a hot path, probe similar constructs before/after.

4. **Per-stage discrimination is the disambiguating tool.** Building
   `FilterComposite` with subsets (`[B]`, `[B, P]`, `[B, P, T]`, etc.)
   identifies which semiring rejects. This is the single most valuable
   diagnostic the project has.

5. **Performance work needs profiling first.** S1 saved time by being
   the *experimental cheap thing first* — a result that gates the
   bigger architectural decision. Any future perf work should follow
   the same pattern.

6. **Conformance harness wall time is unsustainable.** The 120s/file
   budget is now the binding constraint. Three of the last four Tier-A
   fixes produced FAIL→TIMEOUT transitions. Future work needs either
   a budget increase, a faster harness, or the C-backed chart that
   makes parses faster. Metric isn't reliable for measuring progress
   until this is addressed.

## Strategic framing — correctness before performance

The C-library/XS-shim work is paused (not abandoned), and resuming it
remains the right long-arc direction. **But Phase A.2's pattern shows
why correctness work has to clear first**: every audit pass corrected
upstream framings, often substantially. Bug attributions were wrong six
or seven times. The migration completion estimate was off by 2x.
Performance bottlenecks weren't where prior memory notes assumed.

If we resume C-library/XS work while the foundations are still surfacing
surprises, three failure modes are likely:

1. **Re-implementing wrongness in C.** The C parser would faithfully
   reproduce whatever bug the Perl parser has. Now there are two
   implementations to fix instead of one.
2. **Mid-implementation correctness discoveries.** Either the C work
   pauses (wasted bootstrap effort) or it hacks around the issue
   (architectural debt that's worse than the original problem).
3. **Premature optimization.** S1's profiling result was "memory
   pressure on the chart" — but that finding presumes the chart is
   *correct*. If the chart structure itself has bugs we haven't found,
   C-backed chart locks them in at lower level.

**Therefore: the C work is gated until correctness work clears.**

## Correctness gate (work that must clear before C)

These are the real correctness questions still open. None are "small
fixes" — each is a phase of work in itself.

### G1: Decision 4 — semiring contract migration

**Status:** Decided 2026-04-25, not started.

Three semirings violate `(Context, Context) → Context`. FilterComposite
papers over with special cases. Until they're brought into contract,
the semiring layer's algebraic properties are aspirational. Migration
ordering already specified: SemanticAction → TypeInference → Precedence
→ Structural.

**Reference:** `docs/plans/2026-04-24-semiring-contract-drift.md`'s
2026-04-25 addendum.

### G2: Type hierarchy decision (Position A vs Position C)

**Status:** Bookmarked, not settled.

The formal type-system paper treats Scalar and List as siblings with
mutual circularity. The round-trip-preserving framing would make
`Scalar <: List` a linear hierarchy. Bug 1's current
`type_satisfies(X, 'List') → true` is a workaround pending this
decision. Affects the formal paper, the practical guide,
`TypeLibrary.pm`, and flow-typing's design.

**Reference:** Discussion in this session's handoff context;
`docs/architecture/perl-type-system-{practical,formal}.md`.

### G3: TypeLibrary signature audit fixes (correctness-relevant subset)

**Status:** Audit complete, fixes not started.

22 of 28 signatures have at least one defect. Subset relevant to
correctness (latent rejection sites in real code):

- `keys`/`values`/`each` first arg — 151 sites in `lib/`
- `defined`/`pop`/`shift`/`chr`/`ref` `min_arity` defects — 840+ sites
- `Num` → `Int` for integer-only positions
- `split` first arg (Bug 6 anchor) — couples to G2 (union types)

**Reference:** `docs/plans/2026-04-27-typelibrary-signature-audit-findings.md`.

### G4: MOP migration through Phase 6 (eliminates dual representation)

**Status:** 3a-infra done; 3a-migration through 6 not started.

Until Phase 6 lands (deletes Shim, `compat_class`, legacy structs +
DepChaser per Decision 6), the IR layer has dual representation
(typed nodes + legacy class-name dispatch via `compat_class`). Dual
representation obscures correctness reasoning — every codegen change
has to consider both paths.

Phase ordering: 3a-migration → 3b → 3c → 4 → 5 → 6.

**Reference:** Audit 3 findings doc, MOP migration plan.

### G5: Equivalence oracles (the oracle gap)

**Status:** Splits into two pieces with different dependencies. Refined
during the 2026-05-01 scoping session.

The original framing — "no oracle for codegen behaviour" — is correct
but conflated two different oracles. Separating them:

#### G5a: Structural oracle — SoN-JSON comparison

Compares Chalk's IR to perl(1)'s optree-derived IR via JSON
serialization. Substantially built:

- 70-node parity between `Chalk::IR::Node::*` and perl5-son
- `Chalk::IR::Serialize::JSON` (`to_json`/`from_json`) — Chalk side
- `B::SoN` backend (`perl -MO=SoN,json,package=Foo file.pm`) — perl(1) side
- 25-test cross-load harness validating JSON loads cleanly into Chalk IR
- 6-file pilot run (2026-04-11) producing the divergence catalogue
- `script/chalk-emit-son-json` CLI

Oracle architecture: cross-process IR comparison requires serialization.
JSON IS the oracle interface — both processes emit the same schema, the
diff is the oracle. There is no "in-process IR comparison" alternative.

**Remaining work for G5a:**
- Divergence-triage annotation mechanism (mark expected divergences —
  Perl folds `+=` to `add+STACKED`, etc. — vs. real bugs)
- Corpus expansion from 6-file pilot to full `lib/` (the
  `map BLOCK LIST` blocker, issue #691, is retired post-Tier-A;
  see "2026-05-01 verification" below)
- Decide whether `--emit-son-json` joins the codegen Target hierarchy
  (cleanup, not a precondition)

**Dependencies:** G5a-as-functional-harness is parallel-able with G1
and G4. Does not require single-representation IR or clean codegen
contract — JSON diff works against current dual-representation IR,
the `compat_class` artifacts are noise but not a blocker.

**G5a-as-contract-proof** (using the oracle to prove "IR is the
contract") wants G4-Phase-6 (single-representation IR) to land first.
That makes the comparison meaningful as evidence of correctness, not
just "two different IR encodings happen to roundtrip."

#### G5b: Behavioural oracle — run-and-diff

Compares stdout/stderr/exit code between perl(1) and chalk-compiled
output on the same input. Not started; greenfield.

**Two sub-readings:**
- **Synthetic corpus** (Phase 1-5 idiom catalogue from
  `docs/chalk-parse-perl-plan.md`): wrap each idiom in a runnable
  program, diff outputs.
- **Real-file corpus** (`lib/*.pm`): compile, redirect `@INC`, run
  existing test suite against compiled `lib/`. This is the
  self-hosting gate.

**Dependencies:** Both readings depend on **G4-Phase-4** (clean
codegen contract). Today, `Perl::Target::C` takes
`generate_c_files($ir, $sa, $ctx)` — three arguments, two of which
are parse-time leakage from the Context comonad because the IR
doesn't yet carry CFG shape in walkable form. That's not a stylistic
issue; it's evidence that the IR-as-codegen-contract isn't real yet.
G4-Phase-4 ("codegen reads MOP, migrate `body()` readers to graph
walks; eliminate `($sa, $ctx)` backchannel") fixes this. Building
G5b before G4-Phase-4 means anchoring the oracle to a broken
contract — either the oracle accommodates the leakage (baking it in)
or it tests a contract codegen doesn't honor (failing for reasons
unrelated to codegen correctness).

**Reference:** Audit 3's "Oracle situation" section; 2026-05-01
scoping conversation.

### G6: Audit 4 (codegen)

**Status:** Not started. Deferred from Phase A.2 pending G5b.

The maturity plan named four audits; only three completed. Codegen
audit was deferred because it requires the behavioural-equivalence
harness as its oracle. Specifically G5b — G5a's structural oracle
isn't sufficient because it tests IR construction, not codegen.

**Reference:** Maturity audit plan, original brief deferral.

## Codegen Target hierarchy — adjacent finding

Surfaced during the 2026-05-01 scoping conversation, not in the
original audit set. Not a separate gate item, but informs G4-Phase-4
scope and G5a's `--emit-son-json` integration question.

**Current state:** `Chalk::Bootstrap::Target` exists as a 15-line
abstract base with `generate($ir)` and `generate_distribution($ir)`
named as abstract methods. Subclass conformance is partial:

| Class | Entry method | Conforms to base? |
|---|---|---|
| `BNF::Target::Perl` | `generate($ir)` | yes |
| `BNF::Target::C` | `generate($ir)` | yes |
| `Perl::Target::Perl` | `generate($ir)` + `generate_with_cfg($ir, $sa, $ctx)` | partial — extends contract |
| `Perl::Target::C` | `generate_c_files($ir, $sa, $ctx)` + `generate_xs_wrapper(...)` | **no** — doesn't override `generate()` |
| `EmitHelpers` | `generate_typedefs()` (no IR) | no — different shape |
| `IR::Serialize::JSON` | `to_json(\%named_graphs)` (exported sub, no class) | not in hierarchy |

`Perl::Target::C` extends `Perl::Target::EmitHelpers`, not `Target`
directly. EmitHelpers is misnamed — it's not "shared by Perl and C
targets," it's the C target's parent class with ~50 helper methods
(field maps, slugs, regex statics, etc.). `Perl::Target::Perl` does
NOT extend EmitHelpers. So Perl-target and C-target share the
abstract base only, not helper plumbing.

**Implication for G4-Phase-4:** The phase isn't just "migrate
`body()` readers to graph walks." It's also where the codegen
contract becomes structurally enforceable. After Phase 4, every
codegen target's signature is uniform (`generate($graph)` or
`generate($mop)`), the abstract base class is honored by all
subclasses, and joining `IR::Serialize::JSON` to the hierarchy as
a peer becomes meaningful.

**Implication for G5a:** Don't unify `--emit-son-json` into the
codegen hierarchy now — the hierarchy is in mid-fix. JSON emission
correctly lives outside until G4-Phase-4 gives the hierarchy a real
contract for it to join.

## 2026-05-01 verification — issue #691 closed

Issue #691 ("Grammar: map BLOCK LIST cannot terminate") was open at
the time of this handoff doc's first writing and named as a blocker
for SoN-comparison corpus expansion in
`son_comparison_divergences.md` (memory note, 17 days old: "4/6
files fail Chalk-parse on `map { ... } LIST`").

Verified during the 2026-05-01 scoping session: all five
reproductions from the issue body PASS on current branch under both
Boolean-only and full FilterComposite stack. Closed as retired by
Tier-A's Bug 4 fix (commit `1ec8cae1`) and A3 walker hygiene
(commits `fc4524ef`, `45d8c131`).

The memory note's "4/6 files fail Chalk-parse on `map { ... } LIST`"
claim is **stale** — that surface is cleared post-Tier-A. Earley.pm
remains slow (TIMEOUT-class) but that's the C2 chart-memory-pressure
perf-gate item, not a grammar gap.

**Implication for G5a corpus expansion:** the parse-failure blocker
the memory note named is gone. Other parse failures may exist in
`lib/`, but they're independent grammar issues, not G5 work.

## Performance gate (depends on correctness clearing)

After correctness gate clears: C-backed chart, C-library/XS path
resumption. The S1 profiling result confirms this is the right next
perf lever, but it's gated, not next.

## Quality cleanup (parallel-able anytime, low priority)

Items that don't affect correctness and don't unblock C work:

- Dead IR node removal (`Slice`, `Length`, `Stringify`, `Yada`)
- `${EXPR}` block-form scalar deref grammar gap
- Doc reconciliation polish
- Performance follow-ups S2-S4 (per the perf doc) — minor wins

## Recommendation for the next session

Start with a **scoping conversation** to pick which correctness gate
item to tackle first:

1. Read this handoff doc + `docs/plans/2026-04-25-phase-a2-synthesis.md` +
   `docs/plans/2026-04-30-parser-performance-investigation.md`.
2. Decide which of G1-G6 to start with.

Sequencing — refined 2026-05-01:

| Track | Depends on | Parallel-safe with |
|---|---|---|
| G1 (SA-zero, Prec, Struct) | none | G4, G5a |
| G1 (TI) | wants alignment with Decision 5 flow-typing | G4, G5a (but may want sequencing) |
| G4 (each phase sequential within) | prior G4 phase | G1, G5a |
| G5a (harness functional) | #691 (cleared); divergence triage TODO | G1, G4 |
| G5b (oracle-as-contract-proof) | G4-Phase-6 (single-rep IR) | sequential after G4 |
| G5b (behavioural oracle) | G4-Phase-4 (codegen contract) | sequential after G4 |
| G2 / G3 (type hierarchy + signatures) | G2 blocks G3 | partial parallel |
| G6 (codegen audit) | G5b + G4-Phase-4 | sequential |

**Three parallel tracks are viable now: G1, G4, G5a.** G1 and G4
touch different files; G5a is harness work that doesn't touch IR or
semirings. The bottleneck is human review bandwidth, not technical
parallelism.

If picking two tracks: **G4 (mechanical, highest leverage, unblocks
the most) + G5a (gives empirical signal everything else can be
measured against)**. G1 waits and lands in G4 lulls.

If picking one: **G4-Phase-3a-migration**, the next phase in the G4
spine. Audit 3 names this as the next sequential phase after
3a-infra (already done).

If picking quick wins instead: G3's `keys`/`values`/`each` Hash→List
fix is small (3 lines, 151 sites of latent rejection retired).
Doesn't clear a correctness gate by itself, but starts moving the
punch list.

The session-resumption pattern that's worked well: start by reading
the relevant findings docs, surface any framing corrections needed
(they will exist), then dispatch with strict TDD + brief skepticism +
latent-rejection probes.

## Cross-references

- Synthesis: `docs/plans/2026-04-25-phase-a2-synthesis.md`
- Perf: `docs/plans/2026-04-30-parser-performance-investigation.md`
- Maturity audit plan: `docs/plans/2026-04-24-maturity-audit-plan.md`
- Type-system papers: `docs/architecture/perl-type-system-{practical,formal}.md`
- Memory: `~/.claude/projects/-home-perigrin-dev-chalk/memory/MEMORY.md`
  is the index; `pvm_typeinference_reference.md` and other topic files
  carry the load
- Code-auditor agent: `~/.claude/agents/code-auditor.md`
