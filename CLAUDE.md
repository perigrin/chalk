# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the mainline Chalk worktree. Chalk is a self-hosted optimizing compiler for Perl, written in Perl. It began as a clean-room reimplementation ("Chalk::Bootstrap") undertaken to resolve architectural constraints in an earlier implementation; that reimplementation has since replaced the earlier version and is now the only Chalk. Many code paths still carry the `Bootstrap` name (`lib/Chalk/Bootstrap/`, `t/bootstrap/`, `docs/chalk-bootstrap.bnf`) — those are historical and do not indicate a separate project.

**Goal**: A self-hosted optimizing compiler for Perl. Chalk parses a restricted Perl subset into a Sea-of-Nodes IR and lowers it to Perl, XS/C, and (planned) LLVM IR backends. The BNF-meta-grammar self-hosting validation gate (generating a recognizer equivalent to the hand-written version) has been passed; self-hosted compilation of the full Perl subset is ongoing.

**Origin doc**: The original clean-room PRD lives at https://gist.githubusercontent.com/perigrin/eb2b536c312b6fee3584bb0f7d97cde0/raw/af1e52bd340ce7b588a6c2fca4b0de141c74f8f9/cleanroom.md — useful as history, not as current spec.

**Design Philosophy**: Correctness > Simplicity. See `ARCHITECTURE.md` Design Principles for the current principle set (immutability, determinism, progressive filtering, correctness over performance).

**Architecture**: Read [ARCHITECTURE.md](ARCHITECTURE.md) for the layered
parsing pipeline design. Read [CONTRIBUTING.md](CONTRIBUTING.md) for where
different types of fixes belong.

## Development Environment

**Perl Version**: This project requires Perl 5.42.0 for `feature class` support.

**CRITICAL**: Always use these skills when working on this project:

1. **writing-perl-5.42.0** - For all Perl code
   ```
   /skill writing-perl-5.42.0
   ```
   Ensures proper use of modern Perl 5.42.0 features including `feature class`, auto-exported builtins, and correct idioms.

2. **test-driven-development** - For all new code implementation
   ```
   /skill test-driven-development
   ```
   Enforces TDD workflow: write failing test → implement → verify pass. This is a strict requirement per the implementation plan.

**Run tests**:
```bash
perl -Ilib t/bootstrap/file.t          # Single test
perl -Ilib t/bootstrap/*.t             # All bootstrap tests
```

**Code Style**: Modern Perl 5.42.0 with:
- `use 5.42.0; use utf8;` at the top of all files
- `feature class` for OO (requires `no warnings 'experimental::class';`)
- Postfix dereferencing (`$ref->@*` not `@$ref`)
- `true`/`false` builtins (not 1/0)
- Signatures for subs/methods
- ABOUTME comments: All code files start with 2-line `# ABOUTME:` comments explaining file purpose

## Architecture

### Three-Layer Compilation Pipeline

1. **Parser Layer** (Phase 1a): Scanless Earley parser with Boolean semiring
   - Recognize grammar using Predict/Scan/Complete algorithm
   - Terminal matching with regex patterns anchored at `\G`
   - Progressive testing: unambiguous → ambiguous → full grammar

2. **IR Layer** (Phases 2a-2b): Sea of Nodes intermediate representation
   - Hash-consed immutable graph nodes (4 types: Start, Return, Constant, Constructor)
   - Use-def chains for optimization passes
   - Semantic actions thread through comonad Context (extract/extend/duplicate operations)

3. **Code Generation Layer** (Phase 3): Emit Perl code
   - Deterministic output (byte-identical across runs)
   - Target abstraction supports multiple backends
   - Generates `feature class` recognizers

### Comonad-Based Context Threading

The `Chalk::Bootstrap::Context` implements a comonad interface to thread evaluation context functionally:

- **extract**: Get current focus value (IR node)
- **extend**: Apply semantic action to children, aggregate results
- **duplicate**: Create nested contexts for alternatives

This enables semantic actions to compose without mutation. See `docs/comonad-specification.md` for details.

### Sea of Nodes IR

Graph-based IR with explicit data-flow:

- **Hash consing**: Identical nodes share single object (key = operation + input IDs)
- **Immutable**: Nodes never mutated after construction
- **Use-def chains**: Bidirectional producer/consumer tracking
- **4 node types**: Start (entry), Return (exit), Constant (literals), Constructor (grammar construction — parameterized by class: Symbol, Expression, Rule)

See `docs/ir-node-types.md` for complete taxonomy.

### BNF Meta-Grammar

10-rule self-hosting grammar (see `docs/bootstrap-meta-grammar.md`):
- Grammar, Rule, Alternatives, Sequence, Element, Atom, Quantifier, Comment, Identifier, InlineRegex
- Quantifiers (`*`, `+`, `?`) desugar to helper rules during compilation
- Whitespace/comments: `/(?:\s|#[^\n]*)*/` pattern throughout

## Testing Strategy

**Progressive Layer Testing** (per Chalk architecture patterns):

1. **Layer 1**: Boolean semiring only (recognition)
   - Test: Unambiguous grammars accept/reject correctly
   - Files: `t/bootstrap/earley-boolean.t`

2. **Layer 2**: Boolean + Semantic semiring (IR construction)
   - Test: Parse produces expected IR nodes
   - Files: `t/bootstrap/semantic-ir.t`, `t/bootstrap/comonad-threading.t`

3. **Layer 3**: Full pipeline with codegen
   - Test: Generated code structure + determinism
   - Files: `t/bootstrap/codegen-*.t`

4. **Integration**: Self-hosting validation
   - Test: Generated recognizer ≡ hand-written recognizer
   - File: `t/bootstrap/bootstrap-validation.t` (currently TODO until Phase 3)

**All tests must pass 100%** - no TODO tests on critical path after their phase is complete.

## Development Workflow

Implementation follows a **build-then-review** pattern. Reviews happen after
every issue (milestone task), not just after phases. Use the `paad:agentic-review`
skill for automated multi-agent review.

### Step 1: Implementation

Follow TDD (test-driven-development skill). Write failing test, implement
minimal code to pass, refactor, commit. Use the required skills
(`writing-perl-5.42.0`, `test-driven-development`). Commit frequently.

**Bilateral coverage rule for precedence levels:** When adding spec tests
for a new precedence level (or any new comparable numeric ranking among
operators), the test must cover at least one operator on EACH side of the
new level — one that is tighter and one that is looser. A test that checks
only one direction can pass even when the new level is grossly misnumbered,
because the wrong number is still numerically defined and compares correctly
in one direction. See `docs/plans/2026-05-11-step2-second-blocker.md` for
the case study where this rule would have caught a 2-attempt rollback cycle.

### Step 2: Review (after every issue completes)

Run `/paad:agentic-review` after completing each milestone issue. This dispatches
specialist agents (Logic, Error Handling, Contract, Concurrency, Security) in
parallel, verifies findings, and produces a report in `paad/code-reviews/`.

Do NOT proceed to the next issue until review findings are addressed.

**Why per-issue**: Reviewing after each issue catches problems before they
compound. A bug in Issue #2 (DFA construction) that isn't caught until Issue #5
(completion refactoring) is much harder to fix. The earlier review found the
DFA terminal_map built-but-never-consumed gap at Milestone 12 — per-issue
review would have caught it at the issue where it was built.

### Step 3: Address Findings

Fix Critical and Important issues before proceeding. Suggestions can be
deferred. Use the `receiving-code-review` skill for guided implementation
of review feedback.

### Step 4: Simplify

After addressing review findings and committing fixes, run `/simplify` to
review all changed code for reuse opportunities, quality issues, and
efficiency problems. This catches redundant state, copy-paste divergence,
stringly-typed patterns, and dead code introduced during the fix cycle.

## Code Review Standards

Reviews (whether via `paad:agentic-review` or ad-hoc) MUST verify:

1. **Test coverage** — all implemented methods have tests, tests use real
   grammars (not just toy examples), integration tests exist
2. **Missing artifacts** — required data files, grammar specs, config files
3. **Test reality** — tests parse real input, generate real output, validate
   against actual grammar specifications

**Why**: We reached 299 passing tests across Phases 0-2b but never tested
parsing the actual BNF meta-grammar — all tests used inline toy grammars.
Reviews must verify tests are comprehensive and realistic, not just passing.

## Implementation Phases

### Perl Parsing Roadmap

See **`docs/chalk-parse-perl-plan.md`** for the detailed 9-phase roadmap:

- **Phase 0**: Wire 65-rule Perl grammar through existing BNF pipeline
- **Phases 1-5**: Progressive grammar recognition with synthetic tests,
  adding Precedence/Type/Structural semirings and Aycock optimizations as needed
- **Phase 6**: Perl IR from parsed source (file-driven, least to most complex)
- **Phase 7**: Lower to Perl (validate against existing source)
- **Phase 8**: Lower to XS (validate functional equivalence)
- **Phase 9**: Optimizations (Peephole, GCM, Aycock)

## Critical Design Constraints

1. **Strict TDD**: Write failing tests before implementation code (use test-driven-development skill)
2. **Immutability**: All Context operations return new contexts (no mutation)
3. **Determinism**: Code generation must produce byte-identical output across runs
   - Sort all hash iteration
   - Stable helper-rule naming (derive from source position)
   - Content-based node IDs (not creation order)
4. **Progressive Testing**: Test each layer independently before integration

## Key Files

**Documentation**:
- `docs/bootstrap-meta-grammar.md` - 10-rule BNF specification
- `docs/comonad-specification.md` - Context comonad semantics with examples
- `docs/ir-node-types.md` - Sea of Nodes IR taxonomy

**Data Model**:
- `lib/Chalk/Grammar/Symbol.pm` - Immutable symbol (type/value/quantifier)
- `lib/Chalk/Grammar/Rule.pm` - Immutable rule (name/alternatives)

**Tests**:
- `t/bootstrap/grammar-data-model.t` - Data model tests (24 passing)
- `t/bootstrap/bootstrap-validation.t` - Self-hosting integration test (TODO)

## Validation Gates

### Perl Parsing Gate

Progressive validation targets per `docs/chalk-parse-perl-plan.md`:

- **Phase 5**: All 31 `.pm` files recognized by Perl grammar, producing a unambiguous valid parse tree
- **Phase 7**: Generated Perl matches existing source
- **Phase 8**: Generated XS functionally equivalent to Perl

## Relationship to Main Chalk

This is an **independent clean-room implementation** in an isolated worktree:

- **Learn from** Chalk patterns (Earley structure, progressive testing, semiring architecture)
- **Free to diverge** on implementation details (comonad, Sea of Nodes IR, hash consing)
- **After validation passes**: Compare performance/quality, decide on integration strategy

Reference files in main Chalk (read-only):
- `lib/Chalk/Parser.pm` - Existing Earley implementation
- `docs/semiring-architecture.md` - Progressive layer testing patterns
- `docs/MARPA_COMPARISON.md` - Leo optimization background

## Common Pitfalls

1. **Not using required skills**: This project REQUIRES both `writing-perl-5.42.0` and `test-driven-development` skills
2. **Writing code before tests**: Always write the failing test first (TDD), never implementation code first
3. **Missing `use utf8`**: Always include after `use 5.42.0;` (5.42 defaults to ASCII source encoding)
3. **Old-style dereferencing**: Use `$ref->@*` not `@$ref`
4. **Returning 1/0 for booleans**: Use `true`/`false` builtins
5. **Non-deterministic codegen**: Sort all hash keys, use stable naming schemes
6. **Mutation**: Context/IR nodes are immutable - always return new objects
7. **Premature optimization**: Focus on correctness first
8. **DO NOT use multi-class XS compilation**: The `generate_distribution_multi_class` approach
   was explicitly abandoned. Multi-class XS bundles all classes into one .so but `_run_parse`
   still falls back to `eval_pv`, making it no faster than pure Perl. The correct approach is
   **per-class XS compilation** with **semiring intrinsics** to inline hot-path operations
   (e.g., `is_zero()`) and reduce Perl/C bridge crossings. See `xs_bootstrap_approach.md` in
   the memory directory for the full rationale.

## Working with This Codebase

1. **Invoke required skills**: Always start by invoking `writing-perl-5.42.0` and `test-driven-development` skills
2. **Read the architecture docs first**: Especially comonad-specification.md and ir-node-types.md before implementing parser/IR
3. **Follow strict TDD**: Write failing test → implement minimal code → verify pass (use test-driven-development skill)
4. **Test progressively**: Each layer independently before integration
5. **Commit frequently**: After each sub-phase or working feature
6. **Validate determinism**: Run codegen tests multiple times, diff outputs

## Plan Discipline (Chalk-specific)

Before any "next step" discussion, check `docs/plans/` for relevant existing
plans. This project has a documented history of 80-90% migrations that drift
before completion — do not contribute to that pattern.

Specifically:

1. **Check `docs/plans/` first**: before proposing IR, parser, codegen, or
   semiring work, grep the plan files for existing coverage. Quote the
   relevant "Remaining Work" or equivalent sections.
2. **Audit against plan acceptance criteria, not commits**: when asked "is X
   done?", answer against what the plan says needs to happen, not what has
   been committed. The April 4-7 migration was declared "Final" while its own
   plan listed outstanding Remaining Work.
3. **Known stalled migration**: the April 4-7 SoN IR polymorphic migration
   (see `docs/plans/2026-04-04-son-ir-polymorphic-migration.md` and
   `docs/plans/2026-04-04-phase4-structural-split.md`, both superseded by
   `docs/plans/2026-04-21-chalk-mop-migration-plan.md`) has substantial
   *infrastructure* in place (typed nodes, NodeFactory, Graph.merge, MOP
   scaffolding) but the cutover has not landed. Per Audit 3 findings
   (`docs/plans/2026-04-25-audit-3-mop-ir-findings.md`), only **~30–40% of
   acceptance criteria** are met — not the previously-claimed ~80%. Of the
   polymorphic plan's 9 acceptance criteria, 0 are fully done, 2 are
   partial, and 7 are not-started.

   Remaining work — the legacy class-name dispatch surface to retire — is
   **92 sites total**: 61 `compat_class` setters in Actions.pm + 19
   setters in Shim.pm + 12 `$node->class()` string-compare reader sites
   across Actions.pm, EmitHelpers.pm, and StructPromotion.pm. Note: the
   prior framing of "61 `make('Constructor', ...)` calls remaining" is
   misleading — those literal calls *were* renamed to
   `$typed->make('OpClass', ..., compat_class => 'BinaryExpr', ...)`,
   but the contract (legacy class-name dispatch via `compat_class`) was
   preserved. The literal moved; the contract did not.

   Other open items: Shim.pm deletion (1 production consumer + 4 test
   files), codegen migration from `body()` to graph-walk (18 reader
   sites), removal of `body` field from MethodInfo / ClassInfo / SubInfo,
   removal of `compat_class` from Chalk::IR::Node, `_build_method_graph`
   completion (currently a Return-collector + body_stmts seeder, not a
   real SoN construction pass). Commit c7361f3c is explicitly a
   prototype, not a fix; its behavior (Graph::body_stmts seeding) is
   still in production.

   **Highest-leverage single unblock:** Phase 3a-infra of the MOP
   migration plan — promote `$graph` and `$scope` to Context fields and
   delete the `update_cfg`/`cfg_state`/`inherited_cfg_state` side
   channel. Mechanical, well-scoped, and unblocks every later phase
   (3a-migration, 3b, 3c, 4, 5, 6, 7). Without it, bottom-up SSA
   construction cannot start.
4. **Prototype commits are promises**: commits labeled "prototype:", "draft:",
   "stopgap:", or "WIP:" in Chalk's git history must have a follow-up plan
   or issue. Do not treat prototype state as final. When summarizing work
   that includes prototype commits, preserve the prototype status — do not
   use completion-oriented language.
5. **Use `/paad:alignment` before new spec work**: the paad:alignment skill
   exists specifically for auditing plan-vs-code drift. Run it against
   relevant plans before proposing new specs.
