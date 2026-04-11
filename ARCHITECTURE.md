# Chalk Architecture

Chalk is a self-hosting Perl compiler built on a scanless Earley parser
with semiring-based disambiguation. This document provides a high-level
overview; detailed descriptions live in `docs/architecture/`.

## System Overview

```
Perl Source
    |
    v
+---------------------------+
|  Earley Parser            |  Scanless parser with LR(0) DFA
|  + Semiring Pipeline      |  prediction and Aycock optimizations
|    1. Boolean             |  Structural validity
|    2. TypeInference       |  Semantic validity
|    3. Precedence          |  Operator ordering
|    4. Structural          |  Residual disambiguation
|    5. SemanticAction      |  IR construction
+---------------------------+
    |
    v
Sea of Nodes IR
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
| TypeInference | Semantic validity | Does this make type sense? |
| Precedence | Operator ordering | Are operators binding correctly? |
| Structural | Residual disambiguation | Any remaining ambiguities? |
| SemanticAction | IR construction | Build the Sea of Nodes graph |

Semiring operations are commutative — ordering affects performance,
not correctness. TypeInference runs before Precedence because it
prunes more aggressively.

See [Parsing Pipeline](docs/architecture/parsing-pipeline.md) for the
full design rationale.

## Detailed Architecture Documents

| Document | Covers |
|----------|--------|
| [Earley Parser](docs/architecture/earley-parser.md) | Core parser, DFA prediction, Aycock optimizations, chart structure, error recovery |
| [Parsing Pipeline](docs/architecture/parsing-pipeline.md) | Semiring layers, FilterComposite, disambiguation strategy |
| [Context Comonad](docs/architecture/context-comonad.md) | EvalContext, extract/extend/duplicate, parse history threading |
| [Sea of Nodes IR](docs/architecture/sea-of-nodes-ir.md) | IR node types, hash consing, use-def chains, Graph container |
| [IR Lowering](docs/architecture/ir-lowering.md) | Target backends, Perl/XS/C code generation |

## Key Design Principles

- **Correctness over performance.** Each layer must be independently
  correct. Pragmatic shortcuts that produce incorrect parses are not
  acceptable.
- **Grammar over-generates, semirings narrow.** Structural possibilities
  in the grammar; semantic constraints in the semirings.
- **Progressive filtering.** Each layer sees fewer candidates than the
  previous one. By SemanticAction, exactly one parse survives.

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
| Perl Target | `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` |
| XS Target | `lib/Chalk/Bootstrap/BNF/Target/XS.pm` |
| C Target | `lib/Chalk/Bootstrap/BNF/Target/C.pm` |
