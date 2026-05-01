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

## What the next session should consider doing

Three reasonable directions, listed by what each gates:

### Direction 1: Resume C-library/XS path (long arc)

**Triggers:** S1 confirmed C-backed chart is the right next perf lever.
Phase A.2's foundations are stable.

**Substantial design work needed:**
- Bootstrap strategy: chicken-and-egg between Chalk-building-Chalk and
  the C parser
- Chart packed-store layout
- API surface for FilterComposite ↔ chart
- Sequencing relative to MOP Phases 3a-migration through 8

**Cost:** Multi-week project. High value if it lands; high coordination
overhead.

### Direction 2: Continue MOP migration (medium arc)

**Triggers:** Phase 3a-infra is done; 3a-migration retires the
`cfg_state()` shim and unblocks 3b/3c.

**Cost:** Per-phase work, each phase ~1-2 days. Orderly progression
through Phases 3a-migration → 3b → 3c → 4 → 5 → 6 (Decision 6 lands here)
→ 7 → 8.

**Trade-off:** Each phase is concrete; the C-backed chart can run in
parallel without conflict.

### Direction 3: Tier-2 cleanup (short arc)

**Triggers:** TypeLibrary signature audit's punch list has high-leverage
small items.

- `keys`/`values`/`each` Hash → List (151 sites, 3-line change)
- Other `min_arity` and `Num`→`Int` fixes

**Cost:** Bounded. Each fix retires latent rejection sites. Several can
land in one session.

**Trade-off:** Doesn't unblock anything strategic; just cleans up. But
keeps the project healthy and reduces future surprise rejections.

## Recommendation for the next session

I'd suggest starting with a **scoping conversation** rather than diving
into implementation:

1. Read this handoff doc + the synthesis at
   `docs/plans/2026-04-25-phase-a2-synthesis.md` + perf investigation at
   `docs/plans/2026-04-30-parser-performance-investigation.md`.
2. Decide between Direction 1, 2, or 3 (or a combination).
3. If Direction 1: a separate planning session for the C-bootstrap design
   probably comes first. Don't dive into implementation without the
   design.
4. If Direction 2: Phase 3a-migration is the natural next implementation
   step.
5. If Direction 3: TypeLibrary `keys`/`values`/`each` fix is the
   smallest, highest-leverage starting point.

The session-resumption pattern that's worked well: start by reading the
relevant findings docs, surface any framing corrections needed (they
will exist), then dispatch with strict TDD + brief skepticism + latent
probes.

## Cross-references

- Synthesis: `docs/plans/2026-04-25-phase-a2-synthesis.md`
- Perf: `docs/plans/2026-04-30-parser-performance-investigation.md`
- Maturity audit plan: `docs/plans/2026-04-24-maturity-audit-plan.md`
- Type-system papers: `docs/architecture/perl-type-system-{practical,formal}.md`
- Memory: `~/.claude/projects/-home-perigrin-dev-chalk/memory/MEMORY.md`
  is the index; `pvm_typeinference_reference.md` and other topic files
  carry the load
- Code-auditor agent: `~/.claude/agents/code-auditor.md`
