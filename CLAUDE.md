# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Chalk::Bootstrap** worktree - a clean-room implementation of a BNF-to-Perl compiler designed as an experimental foundation that could evolve into the main Chalk compiler if it proves superior.

**Goal**: Build a self-hosting BNF meta-grammar compiler that passes validation by generating a recognizer equivalent to the hand-written version.

**Source**: Implementation follows the PRD at https://gist.githubusercontent.com/perigrin/eb2b536c312b6fee3584bb0f7d97cde0/raw/af1e52bd340ce7b588a6c2fca4b0de141c74f8f9/cleanroom.md

**Design Philosophy**: Correctness > Learn from Chalk patterns > Simplicity

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

Implementation follows a **build-then-review** pattern using specialized agents.
This workflow applies to every phase in `docs/chalk-parse-perl-plan.md`.

### Step 1: Implementation (software-engineer agent)

A `software-engineer` subagent performs the implementation work for each phase.
It follows TDD, writes code, and runs tests. It should invoke the required
skills (`writing-perl-5.42.0`, `test-driven-development`) and commit frequently.

### Step 2: Triple Review (after every phase completes)

After each phase, launch **three review agents in parallel** to evaluate the work:

1. **code-reviewer** — Correctness and accuracy
   - Does the implementation match the phase requirements in `docs/chalk-parse-perl-plan.md`?
   - Are there logic errors, security issues, or violations of project conventions?
   - Does the code follow the architecture (immutability, determinism, semiring contracts)?

2. **test-architect** — Test coverage and quality
   - Are all implemented features covered by tests?
   - Do tests use real data (actual grammars, actual source files), not just toy examples?
   - Are there missing integration tests or edge cases?
   - Are there test anti-patterns (testing mocks, brittle assertions)?

3. **code-reviewer** (performance focus) — Performance and scalability
   - Are there O(n²) algorithms where O(n) is possible?
   - Will the implementation scale to the 65-rule grammar / 31 source files?
   - Are there unnecessary allocations, redundant computations, or missed caching?
   - Is this the point where Aycock optimizations (`docs/chalk-ayock-optimizations.md`)
     become necessary?

### Step 3: Address Findings

Fix issues identified by reviewers before proceeding to the next phase. This
prevents technical debt from accumulating across phases.

**Why three reviewers**: A single reviewer tends to focus on one dimension
(usually correctness) while missing test gaps or performance issues. The triple
review caught the missing integration test gap at Phase 2b — 299 tests passing
but none using the actual BNF meta-grammar.

## Code Review Requirements

**CRITICAL**: In addition to the triple review workflow above, any ad-hoc code
review (via code-reviewer subagent or similar) MUST:

1. **Verify Test Coverage** - Launch a test coverage verification subagent (test-architect or similar) to check:
   - Unit test coverage for all implemented functionality
   - **Integration test coverage** - especially verify tests use real data/grammars, not just toy examples
   - Test quality - do tests actually validate behavior or just exercise code?

2. **Check for Missing Artifacts** - Ensure all required data files, grammar specifications, or configuration files exist and are tested

3. **Validate Test Reality** - Verify tests use real production data:
   - If building a grammar compiler, tests should use the actual grammar specification
   - If building a parser, tests should parse real input files
   - If building a code generator, tests should generate and validate real output

**Why This Matters**: It's easy to pass 100% of tests while missing critical integration testing. Code reviews must verify not just that tests pass, but that tests are comprehensive and realistic.

**Example**: In this bootstrap project, we reached 299 passing tests across Phases 0-2b but never tested parsing the actual 10-rule BNF meta-grammar - all tests used toy grammars created inline. This gap wasn't caught until explicitly invoking test-architect to review test coverage.

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
