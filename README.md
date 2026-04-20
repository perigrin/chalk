# Chalk

**Chalk** is a self-hosted optimizing compiler for Perl, written in Perl.
It compiles a restricted subset of Perl — small enough to analyze
statically, large enough to express Chalk itself — to a Sea-of-Nodes
intermediate representation, and from there to Perl, XS/C, and (planned)
LLVM IR backends. The parser emits Sea-of-Nodes IR directly; there is
no intermediate parse tree or Shared Packed Parse Forest stage.

Progressive disambiguation during the parse — via a composition of five
semirings (Boolean, Precedence, TypeInference, Structural, and
SemanticAction) — collapses ambiguity as parsing proceeds rather than
after the fact. Semantic actions thread through a `Context` comonad and
build Sea-of-Nodes IR directly.

The current codebase is a clean-room reimplementation of the compiler's
front end, undertaken to resolve architectural constraints in the
original implementation around parsing, disambiguation, and IR
construction. Code paths still reflect that history (`lib/Chalk/Bootstrap/`,
`t/bootstrap/`), but the reimplementation is the mainline compiler and
no separate "main Chalk" exists.

## Where to go next

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — architecture overview, semiring
  pipeline, file map
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — development workflow and
  contribution guidelines
- **[docs/architecture/](docs/architecture/)** — detailed architecture
  docs (Earley parser, parsing pipeline, Context comonad, Sea of Nodes
  IR, IR lowering)
