# Contributing to Chalk

## Architecture

Read [ARCHITECTURE.md](ARCHITECTURE.md) before making changes to the
parser or semirings. It describes the layered parsing pipeline and the
role of each component.

## Development Environment

Chalk requires Perl 5.42.0 for `feature class` support. See
[CLAUDE.md](CLAUDE.md) for full environment setup, testing conventions,
and coding standards.

## Key Principles

- **Correctness over performance.** A correct slow implementation beats
  a fast incorrect one. We can always make correct code faster.
- **Grammar over-generates, semirings narrow.** The BNF grammar defines
  structural possibilities. Semantic constraints belong in the semirings,
  not the grammar.
- **Test-driven development.** Write the failing test first. Every
  change needs a test that would have caught the bug or verified the
  feature.
- **Small commits.** Each commit should be independently testable and
  reversible.

## Where to Put Fixes

| Problem | Fix belongs in |
|---------|---------------|
| String won't parse at all | Grammar (`chalk-bootstrap.bnf`) |
| Parses but wrong interpretation | TypeInference or Precedence semiring |
| Parses correctly but wrong IR | SemanticAction / Actions.pm |
| Correct IR but wrong output | Target emitter (Target/Perl.pm, Target/XS.pm) |
