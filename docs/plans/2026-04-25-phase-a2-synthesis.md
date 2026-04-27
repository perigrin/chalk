# Phase A.2 Synthesis — Audit Findings → Remediation Roadmap

**Date:** 2026-04-25
**Inputs:**
- 2026-04-25-audit-1-grammar-findings.md (8399ec0e)
- 2026-04-25-audit-2-semirings-findings.md (0166a24e + addendum 0c19b8fb)
- 2026-04-25-audit-3-mop-ir-findings.md (736281f1)

**Status:** Synthesis. Proposes ordering. Decisions belong to perigrin.

## Executive summary

Phase A.2 ran three parallel read-only audits over the grammar, the
semiring stack, and the MOP+IR migration. The audits are finished.
Together they produce 17 grammar punch-list items, 7 semiring punch-list
items (3 filter bugs + 4 contract violators, with TI completeness gaps),
and a multi-phase MOP+IR migration whose acceptance-criterion completion
is materially below the figure quoted in CLAUDE.md. The most actionable
item across all three audits is not a fix to any specific bug — it is the
recognition that the *seed data* the audits started from contained drift
that the auditors had to correct in flight: the migration is closer to
30–40% of acceptance criteria (not 80%); the documented ambiguity-class
count is seven (not nine); two of three semiring "seed bugs" had their
triggers misidentified; the 61 `make('Constructor', …)` figure refers to
a renamed-but-not-eliminated dispatch surface.

The most surprising finding is that the polymorphic SoN IR migration's
*call literal* was changed but the *contract* it was meant to remove is
intact. The 61 sites that used to call `make('Constructor', …)` now call
`$typed->make('TypedClass', …, compat_class => 'LegacyClass', …)`. The
`compat_class` field, the legacy-class-name dispatch in three consumers
(Actions.pm, EmitHelpers.pm, StructPromotion.pm), and the Shim runtime
are all still load-bearing. The work that needs doing is the contract
deletion, not another call-shape rename.

The most important finding for the next phase of work is that **Phase
3a-infra of the MOP migration is the single highest-leverage unblock**
across all three audits. It is mechanical (promote `$graph` and `$scope`
to Context fields the same way `mop` already is), has a well-defined
boundary (Context.pm + SemanticAction.pm + ~50 Actions.pm callers), and
gates every subsequent migration phase. Without it, the SSA construction
work cannot start, codegen cannot migrate from `body()`, the Shim cannot
be deleted, and DepChaser cannot be retired.

## Cross-audit signals

These are observations that two or more audits independently surfaced.
They are higher-confidence than findings unique to one audit because
they cross-validate.

1. **Ambiguity-class documentation drift (Audit 1 + Audit 2).** Audit 1
   notes `docs/architecture/ambiguity-classes.md` says "seven known
   classes" while the maturity-audit plan and Audit 1's own brief say
   "nine documented classes." Audit 2 then reports its ambiguity-class
   ablation table covered only the seven (Classes 8 and 9 are excluded
   by grammar restriction, not handled by a semiring), confirming the
   doc is correct at seven and the plans drifted to nine. Two audits
   independently flagged the same drift.

2. **Ambiguity-class examples are insufficient for verification (Audit
   1 + Audit 2).** Audit 1 reports it could not record per-class
   derivation counts under Boolean alone — Boolean's `add()` collapses
   ambiguity, the chart is not externally accessible, and counting
   `add()` calls reflects Earley chart-cell sharing rather than
   class-specific derivation counts. Audit 2 then shows that all seven
   canonical examples in `ambiguity-classes.md` PASS with zero ties
   even when their claimed-owner semiring is removed from the stack —
   the canonical examples don't exercise the ambiguity at the Boolean
   level. Both audits independently arrive at the same conclusion: the
   doc's examples illustrate what each class is about but do not let a
   future auditor verify ownership empirically.

3. **The 27 conformance-failing files are dominated by an interaction
   bug (Audit 1 + Audit 2 + addendum).** Audit 1 reports 121/148 files
   pass the conformance harness; Audit 2 narrowed the brief's "12-15
   files" estimate for Bug 1 by showing the dominant `map BLOCK
   $ref->@*` pattern PASSES the per-stage probe. The IR-cluster
   addendum (commit `0c19b8fb`) then identified the actual root cause:
   **Bug 4 — TypeInference + SemanticAction interaction**. Neither TI
   alone nor SA alone rejects; only `[B, T, A]` rejects. The trigger
   is a named-unary or list-op builtin (`defined`, `ref`, `length`,
   `uc`, `lc`, `scalar`, `exists`, `delete`, `chr`, `ord`, `join`,
   `split`, `substr`, `sprintf`, `bless`, `chomp`, `chop`, `warn`,
   `print`, `say`, `push`) inside a `map`/`grep`/`sort` BLOCK parsed
   via `CallExpression` alt 3 (`Identifier WS Block WS ExpressionList`).
   Minimal failing case: `my @x = map { defined $_ } @arr;`. This is
   the first interaction-class bug in the audit; Bugs 1-3 each pinned
   to a single semiring. Site count: 9/9 IR-cluster files plus 5+
   non-cluster files (`Earley.pm`, `Optimizer/DCE.pm`, `EmitHelpers.pm`,
   `FilterComposite.pm`, `IR/Serialize/JSON.pm`). One trigger explains
   the cluster; no sub-patterns identified.

4. **CLAUDE.md migration estimate is materially overstated (Audit 3 +
   inferred from Audit 1 grammar gap state).** Audit 3 directly
   verifies the polymorphic migration is 0/9 fully met / 2 partial /
   7 not-started against acceptance criteria, contradicting CLAUDE.md's
   "approximately 80% complete." Audit 1 indirectly corroborates: the
   `-X` file tests scope-audit claim "Grammar gap. Not in grammar"
   was written against a state pre-commit `36fce12b`, which added the
   production. The drift pattern is the same on both layers — code
   changes happen, plan/CLAUDE.md narrative does not catch up.

5. **TypeInference does most of the rejection work (Audit 1 + Audit
   2).** Audit 1's per-class ablation found Class 7 (`grep { defined
   $_ } @a`) is grammar-recognized but semiring-rejected; Audit 1
   classifies this as an Audit 2 input. Audit 2 then confirms: the
   rejection is in TypeInference's CallExpression branch, same site as
   Bugs 1 and 2. Three independently-discovered Audit 1 inputs (Bug 1
   trigger, Bug 2 trigger, Class 7 grep-defined) all converge on the
   same TypeInference site (`TypeInference.pm:340-365`).

## Categorized punch list

This section is an index, not a re-statement. Each item cross-references
its originating audit and finding number for full detail.

### Documentation drift (highest leverage, lowest cost)

- **Ambiguity-class count drift** — audit plan and Audit 1 brief say
  "nine"; `ambiguity-classes.md` says "seven." Audit 1 Drift 1, Audit 2
  ambiguity-class verification.
- **CLAUDE.md migration estimate** — "approximately 80% complete" reads
  against acceptance criteria as 0/9 fully met. Audit 3 §"Plan
  Discipline check."
- **61-call framing** — the migration plan still describes "61
  `make('Constructor',...)` calls in Actions.pm" as remaining work,
  but those calls have already been renamed. The remaining surface is
  61 `compat_class` setters in Actions.pm + 19 in Shim + 12 readers
  across three consumers. Audit 3 §"Migration plan vs code state."
- **`-X` file tests scope claim** — `2026-04-24-self-hosting-scope-
  audit.md` says "Grammar gap. Not in grammar." Probe shows `-X`
  operators all parse (added by commit `36fce12b`). Audit 1 Drift 2.

A parallel reconciliation pass is updating these in flight; this synthesis
cross-references rather than duplicates.

### Grammar gaps (Audit 1)

Six confirmed Boolean-level grammar gaps, each with site count and
remediation shape suggested:

- **Gap 1 — `->@[range]` postfix array slice.** Zero current production
  sites; grammar reverted in `cf14d82e` after TI/Structural filtering
  interaction. Audit 1 Gap 1.
- **Gap 2 — anonymous-skip signature parameter `$,`.** 1 site
  (`Optimizer.pm:10`). Narrow fix to `ScalarSignatureParam`. Audit 1 Gap 2.
- **Gap 3 — `q(...)` and `qq(...)` paren-delimited quote-like ops.** 3
  sites in BNF targets. Currently misparses as `CallExpression(q,…)`,
  TI rejects. Audit 1 Gap 3.
- **Gap 4 — `qr{...}` and `tr/.../.../`.** Out of self-hosting scope;
  documented for completeness. Audit 1 Gap 4.
- **Gap 5 — `do { ... }` admitted as CallExpression.** Boolean parses
  `do BLOCK` as a builtin call; no dedicated production. Possibly an
  Audit 2 issue (KeywordTable). Audit 1 Gap 5.
- **Gap 6 — keywords admitted as bare expression atoms.** Six keywords
  (`my`, `our`, `state`, `local`, `sub`, `field`) admitted by Boolean,
  rejected by TypeInference. Coverage test for TI's keyword rejection
  rather than a gap to close in the grammar. Audit 1 Gap 6.

### Grammar over-permissiveness (Audit 1)

Four issues where the grammar admits inputs that aren't valid Perl:

- **Over-1 — multi-trailing-comma in `ExpressionList`.** Audit 1.
- **Over-2 — multi-trailing-comma in `SignatureParams`.** Audit 1.
- **Over-3 — lone semicolons admitted as statement chain.** Likely
  intentional (matches Perl 5's empty statement). Audit 1.
- **Over-4 — bare regex `/foo/;` admitted as statement-position
  expression.** Class 4 verification needed; Audit 2 territory. Audit 1.

### Pseudo-ambiguities beyond the documented seven (Audit 1)

Four items not in `ambiguity-classes.md`'s seven classes:

- **Item 1 — `ParenExpr` alt 1 vs alt 2** (single-element list overlap).
- **Item 2 — `ExpressionStatement` alt 1 vs alt 2** (same shape).
- **Item 3 — `MethodCall` no-args vs with-empty-args** (resolved by
  Earley deterministic completion; design intent).
- **Item 4 — `q(...)` admitted as CallExpression-shaped** (subset of
  Gap 3).

### Semiring filter bugs (Audit 2 + IR-cluster addendum)

Four confirmed filter bugs. Bugs 1 and 2 share a TypeInference site so
one fix retires both. Bug 4 is the first interaction-class bug.

- **Bug 1 — TypeInference rejects parenthesized literal LIST as
  block-form-builtin argument.** Site: `TypeInference.pm:340-365`.
  `map { … } (1, 2, 3)` fails; `map { … } @arr` passes. Audit 2 Bug 1.
- **Bug 2 — TypeInference rejects block-form builtin whose BLOCK
  return type isn't List.** Same site. `map { $_ => 1 } @arr` fails.
  Audit 2 Bug 2.
- **Bug 3 — Precedence rejects two AssignmentExpressions in a C-style
  `for` header.** Site: `Precedence.pm:170-186` (hypothesis from
  reading, not instrumentation). Pattern: `for (my $x = 0; …; $x +=
  2)`. Affects 1 file in `lib/`. Audit 2 Bug 3.
- **Bug 4 — TypeInference + SemanticAction interaction rejects
  named-unary/list-op builtin inside `map`/`grep`/`sort` BLOCK parsed
  via `CallExpression` alt 3.** Per-stage shows `[B] [B,P] [B,P,T]
  [B,P,T,S]` all PASS; only `[B,P,T,S,A]` rejects. Subset bisection
  confirms `[B,T,A]` is the minimal failing combo. Trigger builtins:
  `defined`, `ref`, `length`, `uc`, `lc`, `scalar`, `exists`, `delete`,
  `chr`, `ord`, `join`, `split`, `substr`, `sprintf`, `bless`, `chomp`,
  `chop`, `warn`, `print`, `say`, `push`. Non-trigger builtins:
  `return`, `die`, `pop`, `shift`, `keys`, `values`, `each`, `sort`,
  `reverse`. Minimal failing case: `my @x = map { defined $_ } @arr;`.
  Sites: 9/9 IR-cluster files + 5+ non-cluster (`Earley.pm`,
  `Optimizer/DCE.pm`, `EmitHelpers.pm`, `FilterComposite.pm`,
  `IR/Serialize/JSON.pm`). RCA of *why* TI+SA together reject
  (when neither alone does) is out of scope for the read-only probe;
  the addendum sketches three remediation directions without endorsing
  any. This is the dominant pattern in the 27 conformance failures.
  Audit 2 addendum (commit `0c19b8fb`).

### Semiring contract drift (Audit 2)

Four violators of the documented `(Context, Context) → Context`
contract; FilterComposite compensates via `_slot_val` helpers and
special-case branches:

- **Precedence** — uses hashref carriers. FC unwraps for `add`,
  Precedence unwraps for `multiply`. Bring-into-spec cost: medium.
- **Structural** — uses int bitfield carriers (-1 sentinel for zero).
  FC unwraps for `add`. Bring-into-spec cost: highest (would 100x
  allocations and break bitwise-OR shortcut).
- **TypeInference** — mixed return types (Context, undef, bare hashref).
  FC has the most special-cased compensation. Bring-into-spec cost:
  high but achievable; ~10 return sites to migrate.
- **SemanticAction (partial)** — `zero()` returns undef (violation);
  rest of the API honors the contract. Cosmetic to fix.

### TypeInference completeness (Audit 2)

- **Dead-code registry**: `_method_returns` populated by every
  MethodDefinition completion (`TypeInferenceActions.pm:62, 323`),
  accessor `lookup_method_return` exists, no consumer found in `lib/`.
  Either forward-looking infrastructure or producer-without-consumer.
- **`eval_context` tag with no documented consumer**: set on
  AssignmentExpression and ExpressionStatement completion; no consumer
  located in TI itself. Possibly consumed by SA for context narrowing;
  if so, should be documented as a TI→SA contract.
- **Architectural gap**: the implementation does not perform type
  *inference* in the Hindley-Milner sense — types are declared at
  scans and propagated. Closer to "type-checked annotation" than
  "type-inference engine."

### MOP+IR migration (Audit 3)

Per Audit 3 §"Migration plan vs code state":

- **2026-04-04 polymorphic plan**: 0 done / 2 partial / 7 not-started
  (9 acceptance criteria).
- **2026-04-04 Phase 4 structural split**: 3 done / 4 partial / 4
  not-started / 1 unclear-plan (12 items).
- **2026-04-21 MOP plan**: 1 done (Phase 0) / 1 partial (Phase 1) / 1
  done-as-scaffolding (Phase 2) / 10 not-started (13 phases).

Per-phase highlights:
- **Phase 1** — MOP populated *alongside* `IR::Program`/`ClassInfo`/etc.,
  not replacing them. Actions.pm still returns the legacy structs.
- **Phase 3a-infra** — flagged as **highest-leverage single unblock**.
  `Context.pm` has `mop` field but not `graph` or `scope`. Mechanical
  refactor with well-defined boundary.
- **Phase 3a-migration through Phase 8** — all not-started, dependency
  chain documented in Audit 3 §"Dependency graph for remediation."

### Dead code (Audit 3)

- **4 dead IR node types**: `Slice`, `Length`, `Stringify`, `Yada`.
  Declared in `Chalk::IR::NodeFactory`, class file in
  `lib/Chalk/IR/Node/`, no `isa` consumer anywhere.
- **92-site dispatch surface to retire**: 80 `compat_class` setter
  sites + 12 readers across Actions.pm/EmitHelpers.pm/StructPromotion.pm.
  Each reader uses `$node->class()` against legacy class-name strings
  for dispatch. All 12 readers are direct candidates for replacement
  with `isa`-against-typed-class checks once Phase 6 deletes
  `compat_class`.

## Proposed remediation ordering

The audits identified work with mostly-clear dependencies. This section
proposes an order that respects those dependencies and front-loads
leverage. Tier numbers are dependency rank, not priority: a Tier 2 item
may be worked in parallel with a Tier 1 item if no shared state is
touched.

### Tier 0: Documentation reconciliation (parallel, today)

- Update CLAUDE.md migration estimate from "approximately 80%" to a
  more accurate "infrastructure in place; cutover 0/9 acceptance
  criteria fully met."
- Update the migration plan's "61 Constructor calls" framing to
  describe the *current* shape (61 `compat_class` sites + 19 Shim
  setters + 12 readers).
- Reconcile the seven-vs-nine ambiguity-class count: either the doc
  becomes nine (renumbering to absorb the two excluded-by-restriction
  cases) or the plans become seven.
- Update the self-hosting scope audit's `-X` file test claim to reflect
  current grammar state (already admitted post-`36fce12b`).

These are documentation-only and unblock all future audit work by
removing inaccurate seed data. They are running in parallel with this
synthesis at the time of writing; cross-reference rather than duplicate.

### Tier 1: Highest-leverage single tasks

These items have the largest blast-radius unblock per unit of work:

- **Phase 3a-infra (MOP)** — promote `$graph` and `$scope` to Context
  fields, delete `annotations->{cfg}` / `update_cfg` / `cfg_state` /
  `inherited_cfg_state`. Mechanical refactor with well-defined
  boundary (`Context.pm`, `SemanticAction.pm`, ~50 Actions.pm
  callers). Unblocks Phase 3a-migration through Phase 8 (eight
  downstream phases).
- **Bug 4 (TI+SA interaction) RCA and fix** — promoted to Tier 1
  after the IR-cluster addendum identified it as the dominant pattern
  across the 27 conformance failures. Affects 14+ files (9 IR cluster
  + 5+ non-cluster). The audit punted RCA to remediation phase since
  it requires instrumenting `_complete_sa` action returns paired with
  TI annotations. Without this, no IR-cluster file parses
  end-to-end. **Should be resolved before Tier 4 migration phases
  start**, because Phase 3c plans to revive `ir-program-pipeline.t`
  and `ir-sub-info-pipeline.t`, which fail on the same pattern that
  Bug 4 triggers (parsing Shim.pm, NodeFactory.pm, etc.).
- **TypeInference CallExpression site fix (Bugs 1+2)** — single site
  (`TypeInference.pm:340-365`) retires both Bug 1 and Bug 2. Likely
  involves either changing `type_satisfies` (treat List as the union
  of List and any sequence of Scalars) or changing `_complete_type`
  (detect variadic LIST and accept per-position scalars or block
  return).
- **MOP migration Phase 2.5** — fixup classification and
  redistribution. Parallel-able with Phase 3a-infra; foundational for
  Phase 3a-migration.

### Tier 2: Grammar gap closures

The six confirmed grammar gaps, ordered by site count and blast radius:

- **Gap 2 (anonymous `$,`)** — narrow fix; one production touched; one
  affected file. Smallest blast radius.
- **Gap 3 (`q()`/`qq()`)** — three affected files; new alternatives in
  `StringLiteral`. Verify with tie probe (Boolean-level overlap with
  CallExpression alt; TI already rejects the misparse).
- **Gap 1 (`->@[range]`)** — zero current production sites but
  documented as a self-hosting consideration; remediation requires
  resolving the TI/Structural filtering interaction that caused
  `cf14d82e`'s revert.
- **Gap 5 (`do BLOCK`)** — borderline. Possibly an Audit 2 issue
  (KeywordTable) rather than a grammar gap.
- **Gap 6 (six keywords as bare atoms)** — coverage test for TI rather
  than a grammar gap. Useful as a regression harness.
- **Gap 4 (`qr{}`/`tr/`)** — explicitly deferred (out of self-hosting
  scope).

### Tier 3: Semiring contract bring-into-spec

Per Decision 4, all four violators wrap their carriers in Contexts.
Ordered by cost (cheapest first):

- **SemanticAction `zero()` → return Context** — cosmetic fix, matches
  Boolean/FilterComposite pattern.
- **TypeInference contract migration** — three sub-cases per Audit 2:
  make `zero()` return Context; make `multiply()` consistently return
  Contexts; decide whether tag hashes are carrier or focus. Bulk of
  work is the third sub-case. Couples to Decision 5's flow-typing
  completion — if TI's data shapes are about to change for flow-typing,
  the contract migration should land alongside or after, not before.
- **Precedence contract migration** — wrap hash-consed slot values in
  Contexts. Hardest issue is `add()`'s `refaddr()` identity check,
  which wrapping breaks.
- **Structural contract migration** — wrap integer bitfields in
  Contexts. Most expensive: ~100x allocations at the semiring
  boundary, accepted per Decision 4 as the price of a uniform
  contract. Bitwise OR shortcut becomes a Context-method call.

Each migration removes its FilterComposite compensation surface
(`_slot_val` helper, `_filter_compare` special-case, `_wrap_sa_result`
branch). Acceptance test per migration: the slot contract is uniform
across all call paths for that semiring. Final acceptance after all
four: write a mechanical test that asserts `is_zero($x)` iff
`$x->is_zero()` for every semiring, per
`2026-04-24-semiring-contract-drift.md` §"Long-term."

### Tier 4: Migration phase work

Per Audit 3's dependency graph, in order:

- Phase 3a-migration — bottom-up linear graph; delete
  `_build_method_graph`. *Depends on Phase 2.5 + Phase 3a-infra.*
- Phase 3b — if/else Phi insertion. *Depends on Phase 3a-migration.*
- Phase 3c — loop Phi insertion; revive `ir-program-pipeline.t` and
  `ir-sub-info-pipeline.t`. *Depends on Phase 3b.*
- Phase 4 — codegen reads MOP; migrate 18 `->body()` readers to graph
  walks; eliminate `($sa, $ctx)` backchannel. *Depends on Phase 3c.*
- Phase 5 — optimizer signatures (`run($mop)` / `run($graph)`).
  *Depends on Phase 4.*
- Phase 6 — delete residue: Shim, `compat_class`, `body` fields,
  `ClassInfo`/`MethodInfo`/`SubInfo`/`Program` legacy structs.
  *Depends on Phases 1, 4, 5 complete.*
- Phase 7 — restore bidirectional `Graph::nodes()`; delete
  `body_stmts`. *Depends on Phase 3c + Phase 2.*
- Phase 8 — `docs/architecture/mop.md` and update of architecture
  docs. *Depends on Phase 7 complete.*

### Tier 5: Cleanup and ambiguity-class doc enrichment

- **Dead IR node removal**: `Slice`, `Length`, `Stringify`, `Yada`.
  After Phase 6 if those phases land them in production.
- **Grammar over-permissiveness fixes**: Over-1 and Over-2
  (multi-trailing-comma) — small, well-bounded fixes. Over-3 likely
  documented as intentional. Over-4 verification with Audit 2.
- **Pseudo-ambiguity Items 1 and 2**: tighten `ParenExpr` alt 2 and
  `ExpressionStatement` alt 2 to require ≥2 elements, or drop the
  redundant alts.
- **`ambiguity-classes.md` enrichment**: add per-class verification
  examples that produce Boolean-level ambiguity, so a future auditor
  can verify ownership empirically (per Audit 2).
- **DepChaser retirement**: ranked separately. Blocks on MOP exposing
  transitive-import resolution (Audit 3's MOP-vs-DepChaser punch list,
  4 items).

## What is NOT on this roadmap

These are explicitly deferred or out-of-scope for the audit findings
this synthesis covers:

- **Behavioral-equivalence harness (the codegen oracle)** — the
  semantic-correctness oracle for "does the compiled output behave the
  same as the source." Audit 3 calls it out as out-of-scope; "compile
  X, lower X, run X, compare X" is a phase of its own.
- **Codegen audit (Audit 4)** — was scheduled in the maturity-audit
  plan as a fourth audit. Blocks on the behavioral-equivalence
  harness; cannot evaluate `_fixup_*` patches without an oracle for
  what correct output looks like. Not started in Phase A.2.
- **DepChaser retirement** — blocks on MOP gaining transitive-import
  resolution and on Phase 1 of the MOP migration completing. Audit 3
  §"MOP scope vs DepChaser" enumerates the 4-item punch list; the
  retirement order is correctly deferred until MOP exists end-to-end.
- **Architecture redesign** — the audits are remediation-oriented; no
  finding suggests redesigning the layered pipeline, the comonad
  Context, the Sea of Nodes IR, or the FilterComposite semiring stack.
  Out of scope by construction.
- **Performance optimization** — correctness-first per CLAUDE.md.

## Decisions recorded 2026-04-25

After Phase A.2 completed, perigrin made the following decisions on the
open questions below.

**Decision 4 — Strengthen the semiring contract.** All four violators
(Precedence, Structural, TypeInference, SemanticAction.zero()) wrap
their carriers in Contexts. The drift becomes a list of debts to repay,
not a design choice. Structural's ~100x allocation cost is accepted as
the price of a uniform contract — correctness over performance, per
CLAUDE.md. Bring-into-spec ordering follows
`2026-04-24-semiring-contract-drift.md` §"Proposed direction": cheapest
first (SemanticAction zero, then TypeInference, then Precedence, then
Structural). Each can be done independently. The four `_slot_val`
helpers and FilterComposite's special-case branches become removable
as each violator migrates.

**Decision 5 — TypeInference is flow-typing à la TypeScript, not
Hindley-Milner.** The current implementation is mid-completion of a
flow-following type-inference engine, not a misnamed annotation layer.
Audit 2's framing ("closer to type-checked annotation than
type-inference engine") describes what the code does *today*, not what
the layer is supposed to be. The `_method_returns` registry is
producer-landed-early infrastructure for flow-typing's return-type
inference; the consumer lands during TypeInference completion, not as
"dead code to delete." Prior art: `~/dev/pvm` (Go implementation, CST
instead of parse tree). The algorithm carries over; the data
structures don't. Whoever picks up TypeInference completion should
read pvm's Go implementation as reference. Likely lives between MOP
Phase 3c (typed-node SSA graphs land) and Phase 5 (optimizer
signatures benefit from flow-typed return values). The TI+SA
interaction bug (Bug 4) may naturally resolve as part of flow-typing
completion, depending on what specifically TI is rejecting today.

**Type-system specification.** TI's job is to model Perl's actual
type system as documented in `docs/architecture/perl-type-system-practical.md`
(landed 2026-04-27, commit `ab1b3be1`) and the companion formal
treatment `docs/architecture/perl-type-system-formal.md`. Whatever
flow-typing builds, it builds on that vocabulary. The 2026-04-27
TypeLibrary signature audit
(`docs/plans/2026-04-27-typelibrary-signature-audit-findings.md`)
is the first systematic check between the spec and `TypeLibrary.pm`'s
runtime encoding; subsequent audits should continue to use the
papers as the oracle. **Open architectural question (bookmarked):**
the formal paper treats Scalar and List as siblings under Any with
mutual circularity resolved via fixed-point semantics; a
round-trip-preserving alternative would make `Scalar <: List` a
linear hierarchy. Not settled. Bug 1's current `type_satisfies(X,
'List') → true` workaround in TypeLibrary is a stopgap that
becomes structural under the linear-hierarchy reading and remains a
workaround under the formal-paper reading.

**Decision 6 — DepChaser retirement lands with MOP Phase 6.** Not as a
follow-up after Phase 8.

## Open questions for perigrin

Question 1 was answered by the IR-cluster addendum (see Cross-audit
signals §3 above). Questions 4, 5, 6 are settled by the decisions
above. Remaining open:

1. **Tier 1 / Tier 2 parallelism.** Phase 3a-infra, the TI Bug 1+2
   fix, and Bug 4 RCA are all Tier 1; Tier 2's grammar gaps are
   smaller-scope. Can Tier 2 run in parallel with Tier 1? The audits
   don't show a hidden dependency, but TI Bug 1+2 might shift
   TypeInference's `_get_item_types` semantics in a way that interacts
   with Gap 1's `cf14d82e` revert reason (TI/Structural filtering
   interaction). Bug 4's TI+SA interaction RCA might also touch
   TypeInference. Worth clarifying before paralleling — the two TI
   touches probably want to be sequenced rather than parallel.

## Cross-references

- Audit 1 findings: `docs/plans/2026-04-25-audit-1-grammar-findings.md`
- Audit 2 findings: `docs/plans/2026-04-25-audit-2-semirings-findings.md`
- Audit 3 findings: `docs/plans/2026-04-25-audit-3-mop-ir-findings.md`
- Audit 1 brief: `docs/plans/2026-04-25-audit-1-grammar-brief.md`
- Audit 2 brief: `docs/plans/2026-04-25-audit-2-semirings-brief.md`
- Audit 3 brief: `docs/plans/2026-04-25-audit-3-mop-ir-brief.md`
- Maturity audit plan: `docs/plans/2026-04-24-maturity-audit-plan.md`
- Self-hosting scope audit: `docs/plans/2026-04-24-self-hosting-scope-audit.md`
- Semiring contract drift: `docs/plans/2026-04-24-semiring-contract-drift.md`
- Ambiguity decision record: `docs/plans/2026-04-24-ambiguity-decision-record.md`
- Toke sweep (22 undocumented points): `docs/plans/2026-04-24-toke-sweep-undocumented-ambiguity.md`
- Option B postmortem: `docs/plans/2026-04-24-option-b-grammar-refactor-postmortem.md`
- 2026-04-04 SoN IR polymorphic migration plan (archived):
  `docs/plans/2026-04-04-son-ir-polymorphic-migration.md`
- 2026-04-04 Phase 4 structural split plan (archived):
  `docs/plans/2026-04-04-phase4-structural-split.md`
- 2026-04-21 MOP migration plan (current operative):
  `docs/plans/2026-04-21-chalk-mop-migration-plan.md`
