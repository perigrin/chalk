# Audit 3 — MOP + IR (subagent brief)

**Date:** 2026-04-25
**Companion to:** `docs/plans/2026-04-24-maturity-audit-plan.md`
**Status:** Brief, ready to dispatch.

## What this audit is

A read-only investigation that produces a punch list for the
MOP + IR layers' implementation maturity. The audit does not fix
anything. It produces a markdown report (sibling, suffix
`-findings.md`) and stops.

The plain English version of the audit's question:

> The 2026-04-04 polymorphic IR migration was reported ~80%
> complete months ago. What is the actual completion percentage
> today, what concrete tasks remain, and what does each blocking
> task block downstream?

## Oracle — and its limit

MOP+IR is an **interstitial form**. There is no external oracle
for "is this IR correct?" — the IR is an invention; correctness
is only definable through end-to-end behavior.

This audit therefore relies on three internal-invariant oracles:

1. **Plan oracle.** The 2026-04-04 polymorphic migration plan and
   the Phase-4 structural-split plan name acceptance criteria.
   Audit verifies code state against those criteria. The plan is
   the spec; deviation from the plan is a finding.

2. **Internal-invariant oracle.** IR claims to satisfy laws:
   hash-consing identity, immutability, use-def chain consistency,
   determinism. The audit identifies which laws are claimed
   (read the architecture docs and code comments), determines
   whether tests exist for each, and documents gaps. No new tests
   get built — that's a separate phase.

3. **Compat-trail oracle.** The codebase contains explicitly
   transitional code (`Shim.pm`, `compat_class`, `body()` fallback,
   the `_build_method_graph` Return-collector prototype, ~61
   `make('Constructor', ...)` calls in `Actions.pm`). Each
   transitional entry is a marker that a migration step hasn't
   happened. Audit inventories every such marker and matches it to
   the migration step that retires it.

The audit has no oracle for "MOP+IR semantically represents the
source program." That requires a behavioral-equivalence harness
which doesn't exist yet and is out of scope here. Audit 3
produces structural and procedural findings; semantic correctness
falls to a future phase.

## Seed data — the migration's reported state

From `CLAUDE.md` (Plan Discipline section):

> the April 4-7 SoN IR polymorphic migration is approximately 80%
> complete. Remaining: ~61 `make('Constructor', ...)` calls in
> Actions.pm, Shim.pm deletion, codegen migration from `body()` to
> graph-walk, removal of `body` field from MethodInfo, removal of
> `compat_class` from Chalk::IR::Node, `_build_method_graph`
> completion (currently a Return-collector, not a real SoN
> construction pass). Commit c7361f3c is explicitly a prototype,
> not a fix.

The audit verifies each item against current code. Each item is a
boolean: the work is done, or it isn't. Where it isn't, the audit
produces a per-item punch list entry.

Additional seed:

- `DepChaser.pm` is transitional and exists because MOP can't
  answer dependency queries today. MOP completion retires
  DepChaser. Audit identifies what specifically MOP needs to learn
  for DepChaser to go away.

- `Shim.pm` is transitional. Currently `lib/Chalk/IR/Shim.pm`
  exists. Audit confirms: is anything in production code still
  consuming it? If yes, what specifically?

## Audit tasks

### Task 1: Migration plan vs code state

For each named acceptance criterion in:

- `docs/plans/2026-04-04-son-ir-polymorphic-migration.md`
- `docs/plans/2026-04-04-phase4-structural-split.md`

determine current code state. Output a table:

| Criterion | Plan says | Code today | Status |
|---|---|---|---|

Status column: done | partial | not-started | unclear-plan.

For partial items, name what specifically is left.

### Task 2: Inventory transitional code

For each of the following, find every site in `lib/`:

- `make('Constructor', ...)` calls — count, list files
- `Shim.pm` references — `use Chalk::IR::Shim`, method calls,
  package usage
- `compat_class` field on `Chalk::IR::Node` — declarations and
  reads
- `body()` method on `Chalk::IR::MethodInfo` — declarations and
  callers
- `_build_method_graph` — the prototype; what does it actually do
  vs. what does the plan say it should do
- Commits prefixed `prototype:`, `draft:`, `stopgap:`, `WIP:` —
  enumerate, link to follow-up issues if any
- Any `# TODO` / `# FIXME` / `# HACK` comments specifically about
  migration state

Output: per-marker inventory with file:line citations.

### Task 3: Dependency graph for the punch list

For each remaining migration task, identify:

- What does this task block? (downstream consumers)
- What does this task depend on? (upstream prerequisites)
- Is there a single "first task" that unblocks several others?

This produces a recommended ordering for remediation, but the
ordering is a proposal — perigrin decides actual order.

### Task 4: MOP scope vs DepChaser

DepChaser exists because MOP doesn't answer some questions today.
Identify:

- What queries does DepChaser perform on source code?
  (e.g., "what classes does this file declare," "what does it `use`,"
  etc.)
- Which of those queries should MOP own?
- For each query MOP should own, what specifically is missing
  from MOP today?

This produces a "MOP completeness" punch list specifically scoped
to "what makes DepChaser retirable."

### Task 5: IR invariant claims vs test coverage

For each invariant the IR claims:

- **Hash-consing:** identical inputs produce identical node IDs
- **Immutability:** no node mutation post-construction
- **Use-def chain consistency:** `defs(x)`'s every node has `x` in
  its `uses`
- **Determinism:** byte-identical IR across runs for same input

Determine:
- Where is the claim documented? (architecture doc, file comment,
  none)
- What test coverage exists? (specific test files / cases)
- Is the test coverage adequate for the claim?

Output: per-invariant gap analysis.

### Task 6: Polymorphic dispatch maturity

The migration moves from `Constructor`-based shim to typed nodes
with polymorphic dispatch. Verify:

- Are all node types in `lib/Chalk/IR/Node/` actually
  instantiable directly (without going through Shim)?
- Are there node types declared in `lib/Chalk/IR/Node/` that
  nothing uses?
- Are there call sites that do `if (ref($node) eq '...') { ... }`
  type-tagging patterns that should be polymorphic methods?

This is a code-shape audit, not a feature audit.

## Constraints — what this audit MUST NOT do

- Do NOT modify any production code or test files.
- Do NOT delete `Shim.pm`. (That's the migration's job, not the
  audit's.)
- Do NOT migrate `make('Constructor', ...)` calls.
- Do NOT propose architectural redesigns. The architecture is
  per the existing plan; the audit reports completion against
  that plan.
- Do NOT touch `DepChaser.pm` itself; only document what MOP
  needs to learn to retire it.
- Do NOT attempt grammar or semiring work. Audits 1 and 2 own
  those.
- Do NOT build a round-trip behavioral-equivalence harness. That
  blocks anything semantic; out of scope here.
- If you find yourself writing "let me just delete this dead
  field," stop and add it to the punch list.

## Tools available

- `Read`, `Grep`, `Glob`, `Bash` (diagnostic runs only)
- Existing test suite (passes today on `worktree-pu`; useful as
  a sanity check that the audit's read-only diagnostic runs don't
  break things, but the suite is NOT a correctness oracle for
  this audit per the test-suite-as-oracle conversation)
- The conformance harness — primarily as a "what doesn't parse"
  signal, since 7 IR/MOP files don't parse and that's relevant
  here too

## Skills required

- `superpowers:writing-perl-5.42.0`
- `superpowers:systematic-debugging`
- `chalk-development`

## Output

A markdown file at:
`docs/plans/2026-04-25-audit-3-mop-ir-findings.md`

Structure:

```markdown
# Audit 3 — MOP + IR Findings

## Summary
- Migration plan acceptance criteria status: N done / N partial / N not-started
- Transitional code markers: N
- IR invariant test coverage gaps: N
- MOP capabilities needed to retire DepChaser: N

## Migration plan vs code state
[Table per Task 1]

## Transitional code inventory
### `make('Constructor', ...)` calls — N total
[List by file]

### Shim.pm — N consumer sites
[Inventory]

### compat_class — N reads, N declarations
[Inventory]

### body() — N declarations, N call sites
[Inventory]

### _build_method_graph — current capability
[Description]

### Prototype/WIP/stopgap commits
[List with follow-up issue links if any]

## Dependency graph for remediation
[Per-task entry: what it blocks, what it depends on]

## MOP scope vs DepChaser
### Query N: <description>
**DepChaser site:**
**Should MOP own?** (yes | no)
**Missing from MOP today:**

## IR invariant coverage
### Invariant N: <name>
**Claim documented at:** (path | none)
**Test coverage:** (test file:case list | none)
**Gap:** (no claim | claim no tests | claim incomplete tests | claim full coverage)

## Polymorphic dispatch maturity
### Node type N
**Instantiable directly:** (yes | no — Shim required)
**Used at sites:** (count)
**Call-site patterns checking ref():** (sites)

## Cross-references
- Audit 2 inputs (semiring code that depends on IR shape): ...
- Future round-trip-harness phase inputs: ...
- Plan documents needing update: ...
```

Length target: 2000–4000 words. Findings before opinions.

## Acceptance — how the audit knows it's done

1. Every named criterion in both migration plans has a current-state
   verdict.
2. All transitional-code markers are inventoried with file:line
   citations.
3. The remediation dependency graph is drawn (even if simple).
4. MOP-vs-DepChaser scope is documented per-query.
5. Each IR invariant has a coverage entry.
6. Findings file committed to `worktree-pu` directly.
7. Subagent reports: completion percentage, ordered punch list,
   no claims of "fixed."

## Reading list before starting

- `docs/plans/2026-04-24-maturity-audit-plan.md` — master plan
- `docs/plans/2026-04-04-son-ir-polymorphic-migration.md`
- `docs/plans/2026-04-04-phase4-structural-split.md`
- `docs/plans/2026-04-21-target-interface-design.md`
- `docs/plans/2026-04-21-chalk-mop-migration-plan.md`
- `docs/plans/2026-04-20-program-graph-of-graphs-design.md`
- `docs/architecture/sea-of-nodes-ir.md`
- `docs/ir-node-types.md`
- `lib/Chalk/IR/` — the entire layer
- `lib/Chalk/MOP/` — the metaobjects
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm`
- `lib/Chalk/Bootstrap/ConciseTree/Actions.pm` — where the
  ~61 Constructor calls live
- `lib/Chalk/IR/Shim.pm` — the file scheduled for retirement
- `CLAUDE.md` Plan Discipline section — the migration's known
  state
- Memory: `~/.claude/projects/-home-perigrin-dev-chalk/memory/`
  files: `son_migration_direction.md`, `son_comparison_*`,
  `ir_correctness_rca_2026_04_14.md`,
  `ir_design_exploration_2026_04_14.md`, `bottom_up_context_graph_design.md`
