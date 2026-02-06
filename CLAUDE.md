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
   - Hash-consed immutable graph nodes (6 types: Start, Return, Constant, MakeSymbol, MakeExpression, MakeRule)
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
- **6 node types**: Start (entry), Return (exit), Constant (literals), MakeSymbol/MakeExpression/MakeRule (grammar construction)

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

## Code Review Requirements

**CRITICAL**: Whenever conducting a code review (via code-reviewer subagent or similar), you MUST:

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

### Current Status: Phase 0 Complete ✅

- ✅ Data model classes: `Chalk::Grammar::Symbol`, `Chalk::Grammar::Rule`
- ✅ Architecture docs: comonad spec, IR node types, meta-grammar
- ✅ Test skeleton: `bootstrap-validation.t` (fails with TODO)

### Next: Phase 1a - Standard Earley Parser

Deliverables:
- `lib/Chalk/Bootstrap/Earley.pm` - Scanless Earley recognizer
- `lib/Chalk/Bootstrap/Semiring/Boolean.pm` - Recognition semiring
- `lib/Chalk/Bootstrap/Context.pm` - Basic comonad (extract only)
- `lib/Chalk/Bootstrap/Terminal.pm` - Regex terminal matching
- Tests: `t/bootstrap/earley-*.t` (progressive: boolean → ambiguous → regex)

### Phase 2a - IR Infrastructure

Deliverables:
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm` - Hash consing factory
- `lib/Chalk/Bootstrap/IR/Node.pm` - Base class with use-def chains
- `lib/Chalk/Bootstrap/IR/Node/*.pm` - 6 node subclasses
- Tests: `t/bootstrap/ir-*.t` (hash consing, use-def chains)

### Phase 2b - Semantic Actions

Deliverables:
- Complete comonad: add `extend`/`duplicate` to Context
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` - IR construction semiring
- `lib/Chalk/Bootstrap/Actions.pm` - 10 semantic action callbacks
- Tests: `t/bootstrap/semantic-ir.t`, `t/bootstrap/comonad-threading.t`

### Phase 3 - Code Generation (MILESTONE)

Deliverables:
- `lib/Chalk/Bootstrap/Target.pm` - Target abstraction
- `lib/Chalk/Bootstrap/Target/Perl.pm` - Emit feature class code
- Generated: `lib/Chalk/Grammar/BNF/Generated.pm`
- Tests: `t/bootstrap/codegen-*.t`, **bootstrap-validation.t PASSES**

### Phase 4 - Optimization Pipeline

Deliverables:
- `lib/Chalk/Bootstrap/Optimizer/*.pm` - Peephole, DCE, GCM passes
- Tests: `t/bootstrap/optimizer-*.t` (correctness + effectiveness)

### Phase 5 - Leo Optimization (DEFERRED, off critical path)

Not required for self-hosting validation.

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

## Validation Gate

The `t/bootstrap/bootstrap-validation.t` test is the integration gate:

- **Phase 0**: Fails "parser not implemented" ✅ (current state)
- **Phase 1a**: Fails "IR construction not implemented"
- **Phase 2b**: Fails "codegen not implemented"
- **Phase 3**: **PASSES** (milestone - self-hosting works)
- **Phase 4**: Still passes (validates optimization correctness)

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
7. **Premature optimization**: Focus on correctness first (Leo optimization is Phase 5, deferred)

## Working with This Codebase

1. **Invoke required skills**: Always start by invoking `writing-perl-5.42.0` and `test-driven-development` skills
2. **Read the architecture docs first**: Especially comonad-specification.md and ir-node-types.md before implementing parser/IR
3. **Follow strict TDD**: Write failing test → implement minimal code → verify pass (use test-driven-development skill)
4. **Test progressively**: Each layer independently before integration
5. **Commit frequently**: After each sub-phase or working feature
6. **Validate determinism**: Run codegen tests multiple times, diff outputs
