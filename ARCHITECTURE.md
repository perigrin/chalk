# Chalk Architecture

Chalk is a self-hosted optimizing compiler for Perl, written in Perl.
It is built on a scanless Earley parser with semiring-based
disambiguation, targeting a Sea-of-Nodes IR following Cliff Click's
design. The parser emits SoN IR directly; there is no intermediate
parse tree or Shared Packed Parse Forest stage. This document provides
a high-level overview; detailed descriptions live in
`docs/architecture/`.

## System Overview

```
Perl Source
    |
    v
+---------------------------+
|  Earley Parser            |  Scanless parser with LR(0) DFA
|  + Semiring Pipeline      |  prediction and Aycock optimizations
|    1. Boolean             |  Structural validity
|    2. Precedence          |  Operator ordering
|    3. TypeInference       |  Semantic validity
|    4. Structural          |  Residual disambiguation
|    5. SemanticAction      |  IR construction
+---------------------------+
    |
    v
Sea of Nodes IR
    |
    v
+---------------------------+
|  MOP Layer                |  Per-class containers (Class, Method,
|                           |  Sub, Field, Phaser) each owning a
|                           |  per-parse IR Graph and NodeFactory
+---------------------------+
    |
    v
+---------------------------+
|  Target Lowering          |  Perl, XS, or C code generation
+---------------------------+
    |
    v
Output (Perl / XS / C)
```

## Parsing Pipeline

The parser processes input through five semiring layers. Each layer
narrows the set of valid parses. The grammar intentionally
over-generates; the semirings encode the knowledge needed to
disambiguate.

| Layer | Role | Question Answered |
|-------|------|-------------------|
| Grammar + Boolean | Structural validity | Could this be Perl? |
| Precedence | Operator ordering | Are operators binding correctly? |
| TypeInference | Semantic validity | Does this make type sense? |
| Structural | Residual disambiguation | Any remaining ambiguities? |
| SemanticAction | IR construction | Build the Sea of Nodes graph |

The filtering semirings (Boolean, Precedence, TypeInference, Structural)
are algebraically order-agnostic — they commute, so their relative
order is a performance choice rather than a correctness constraint.
SemanticAction runs last because it is the most expensive (it builds IR
nodes); deferring it avoids work on branches the filtering semirings
will kill. Swapping TypeInference and Precedence is a possible future
optimization, since TypeInference may prune more aggressively.

See [Parsing Pipeline](docs/architecture/parsing-pipeline.md) for the
full design rationale.

## Detailed Architecture Documents

| Document | Covers |
|----------|--------|
| [Earley Parser](docs/architecture/earley-parser.md) | Core parser, DFA prediction, Aycock optimizations, chart structure, error recovery |
| [Parsing Pipeline](docs/architecture/parsing-pipeline.md) | Semiring layers, FilterComposite, disambiguation strategy |
| [Context Comonad](docs/architecture/context-comonad.md) | Context, extract/extend/duplicate, parse history threading |
| [Sea of Nodes IR](docs/architecture/sea-of-nodes-ir.md) | IR node types, hash consing, use-def chains, Graph container |
| [MOP Layer](docs/architecture/mop.md) | Class/Method/Sub/Field/Phaser containers, per-parse factory ownership |
| [IR Lowering](docs/architecture/ir-lowering.md) | Target backends, Perl/XS/C code generation (LLVM IR planned) |
| [Optimization](docs/architecture/optimization.md) | Implemented and planned IR-level passes |

## Key Design Principles

- **Correctness over performance.** Each layer must be independently
  correct. Pragmatic shortcuts that produce incorrect parses are not
  acceptable.
- **Grammar over-generates, semirings narrow.** Structural possibilities
  in the grammar; semantic constraints in the semirings.
- **Progressive filtering.** Each layer sees fewer candidates than the
  previous one. By SemanticAction, exactly one parse survives.
- **Immutability.** IR nodes and parse contexts are immutable.
  Operations return new objects rather than mutating existing ones; this
  enables hash consing, safe sharing across passes, and
  refaddr-based identity comparison in FilterComposite.
- **Determinism.** Code generation produces byte-identical output across
  runs. Hash iteration is sorted, node identity is content-addressed
  (not allocation-order), and helper-rule names derive from source
  position.
- **Per-parse ownership.** The MOP, every IR Graph, and every
  NodeFactory are per-parse instances. Hash-cons identity of nodes is
  meaningful only within a single parse; cross-parse comparison uses
  `content_hash`, not refaddr. This is what allows
  `Graph::nodes()` to walk consumer edges safely without leaking into
  other parses' graphs.

## File Map

| Component | Location |
|-----------|----------|
| BNF Grammar | `docs/chalk-bootstrap.bnf` |
| Earley Parser | `lib/Chalk/Bootstrap/Earley.pm` |
| Core Item Index | `lib/Chalk/Bootstrap/CoreItemIndex.pm` |
| LR(0) DFA | `lib/Chalk/Bootstrap/LR0DFA.pm` |
| Grammar Desugaring | `lib/Chalk/Bootstrap/Desugar.pm` |
| Boolean | `lib/Chalk/Bootstrap/Semiring/Boolean.pm` |
| TypeInference | `lib/Chalk/Bootstrap/Semiring/TypeInference.pm` |
| Precedence | `lib/Chalk/Bootstrap/Semiring/Precedence.pm` |
| Structural | `lib/Chalk/Bootstrap/Semiring/Structural.pm` |
| SemanticAction | `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` |
| FilterComposite | `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` |
| Context Comonad | `lib/Chalk/Bootstrap/Context.pm` |
| IR Nodes | `lib/Chalk/IR/Node/*.pm` |
| IR NodeFactory | `lib/Chalk/IR/NodeFactory.pm` |
| IR Graph | `lib/Chalk/IR/Graph.pm` |
| MOP root (class registry) | `lib/Chalk/MOP.pm` |
| MOP Class | `lib/Chalk/MOP/Class.pm` |
| MOP Method | `lib/Chalk/MOP/Method.pm` |
| MOP Sub | `lib/Chalk/MOP/Sub.pm` |
| MOP Field | `lib/Chalk/MOP/Field.pm` |
| MOP Phaser (abstract + Adjust) | `lib/Chalk/MOP/Phaser.pm`, `lib/Chalk/MOP/Phaser/Adjust.pm` |
| MOP Import | `lib/Chalk/MOP/Import.pm` |
| BNF → Perl Target | `lib/Chalk/Bootstrap/BNF/Target/Perl.pm` |
| BNF → XS Target | `lib/Chalk/Bootstrap/BNF/Target/XS.pm` |
| BNF → C Target | `lib/Chalk/Bootstrap/BNF/Target/C.pm` |
| Perl → Perl Target | `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` |
| Perl → C Target (+ XS wrappers) | `lib/Chalk/Bootstrap/Perl/Target/C.pm` |
| EmitHelpers (shared base) | `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` |
