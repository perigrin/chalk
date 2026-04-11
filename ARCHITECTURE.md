# Chalk Architecture

Chalk is a self-hosting Perl compiler built on a scanless Earley parser
with semiring-based disambiguation. This document describes the parsing
architecture and the role of each component.

## Parsing Pipeline

The parser processes input through a layered pipeline. Each layer
narrows the set of valid parses, from structural possibility down to a
single unambiguous interpretation that the semantic actions consume.

```
Input string
    |
    v
Grammar + Boolean ---- "Could this be Perl?"
    |
    v
TypeInference --------- "Does this make semantic sense?"
    |
    v
Precedence ------------ "Are operators binding correctly?"
    |
    v
Structural ------------ "Any remaining ambiguities?"
    |
    v
SemanticAction --------- Build IR from unambiguous parse
```

### Layer 1: Grammar + Boolean — Structural Validity

The BNF grammar (`docs/chalk-bootstrap.bnf`) defines all possible parse
trees. The Boolean semiring confirms that at least one valid parse
exists at each position. Together they answer: **could this string be
valid Perl?**

At this level, `keys % h` is structurally valid because
`Expression BinaryOp Expression` is a legal production. The grammar is
intentionally permissive — it over-generates, allowing strings that are
syntactically plausible but semantically wrong. The semirings filter
these down.

### Layer 2: TypeInference — Semantic Validity

TypeInference narrows parses based on semantic knowledge. It answers:
**does this parse make sense given what we know about types?**

TypeInference knows:
- Builtin function signatures (parameter types, arity, return types)
- That `use strict` is always enforced (barewords are not values)
- Variable types from sigils (`$` scalar, `@` array, `%` hash)
- Keyword-to-rule mappings (which grammar rules consume which keywords)
- Type compatibility (does this argument satisfy this parameter?)

At this level, `keys % h` is rejected: `keys` is a builtin (not a
numeric value), so it cannot be the left operand of modulo. The `%`
must be a hash sigil, making `%h` the argument to `keys`.

TypeInference runs before Precedence because it has stronger opinions
about which parses are valid. By pruning semantically invalid paths
early, it reduces the work for later semirings.

### Layer 3: Precedence — Operator Ordering

Given semantically valid parses, Precedence ensures operators bind in
the correct order. It answers: **are the operators binding correctly?**

Precedence knows the 15-level operator precedence table from `perlop`
and operator associativity (left, right, nonassoc, chained). It rejects
parses where a lower-precedence operator appears as a child of a
higher-precedence one without parentheses.

At this level, `$a + $b * $c` correctly groups as `$a + ($b * $c)`
because `*` (level 2) binds tighter than `+` (level 3). The parse
`($a + $b) * $c` is rejected because `+` cannot be a child of `*`.

### Layer 4: Structural — Final Disambiguation

Structural handles residual ambiguities that survive type and precedence
filtering. Examples include block-vs-hash disambiguation (`{` after
`map` is a block, not a hash constructor) and call-vs-dereference
context tagging.

This layer may become superfluous as TypeInference matures. If
TypeInference correctly handles all semantic disambiguation, Structural
would have no remaining work to do. This needs validation.

### Layer 5: SemanticAction — IR Construction

SemanticAction receives a stream of semantically correct, unambiguous
tokens and triggers action methods that build the IR. Each grammar rule
has a corresponding action method in `Chalk::Bootstrap::Perl::Actions`
that constructs IR nodes (Sea of Nodes graph).

SemanticAction does not disambiguate — it consumes the single surviving
parse and produces the IR.

## Semiring Properties

### Commutativity

The semiring operations (multiply, add) are order-independent. Changing
the order of semirings in the FilterComposite should not change the
correctness of the result — only the performance. TypeInference comes
before Precedence because it prunes more aggressively, not because
ordering affects correctness.

### FilterComposite

The five semirings are combined in a `FilterComposite` that runs them
as a tuple:

```
[Boolean, TypeInference, Precedence, Structural, SemanticAction]
```

Each semiring operates on its own value independently. FilterComposite
propagates zero (rejection) from any component to the whole tuple: if
any semiring rejects a parse, it is dead.

For `add` (merging alternative parses at the same chart position),
FilterComposite uses first-wins ordered priority for disambiguation
when semirings disagree. Because TypeInference appears before
Precedence, its disambiguation choices take priority — which is
correct, since type information is more specific than operator ordering.

## Key Design Principles

### Correctness over performance

Each layer must be correct independently. A parse that survives all
layers is guaranteed to be valid Perl (within the subset Chalk
supports). Pragmatic shortcuts that produce incorrect parses are not
acceptable.

### Grammar over-generates, semirings narrow

The grammar is intentionally permissive. It defines structural
possibilities, not semantic constraints. Semirings encode the knowledge
needed to disambiguate: type signatures, precedence tables, structural
context. This separation keeps the grammar simple and puts intelligence
in the semirings where it can be tested independently.

### Progressive filtering

Each layer sees fewer candidate parses than the previous one. Boolean
prunes structural impossibilities. TypeInference prunes semantic
nonsense. Precedence prunes misordered operators. By the time
SemanticAction runs, there should be exactly one surviving parse for
each position.

## File Map

| Component | Location |
|-----------|----------|
| BNF Grammar | `docs/chalk-bootstrap.bnf` |
| Earley Parser | `lib/Chalk/Bootstrap/Earley.pm` |
| Boolean | `lib/Chalk/Bootstrap/Semiring/Boolean.pm` |
| TypeInference | `lib/Chalk/Bootstrap/Semiring/TypeInference.pm` |
| TypeInference Actions | `lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm` |
| Type Library | `lib/Chalk/Grammar/Perl/TypeLibrary.pm` |
| Keyword Table | `lib/Chalk/Grammar/Perl/KeywordTable.pm` |
| Precedence | `lib/Chalk/Bootstrap/Semiring/Precedence.pm` |
| Precedence Table | `lib/Chalk/Grammar/Perl/PrecedenceTable.pm` |
| Structural | `lib/Chalk/Bootstrap/Semiring/Structural.pm` |
| SemanticAction | `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` |
| Perl Actions | `lib/Chalk/Bootstrap/Perl/Actions.pm` |
| FilterComposite | `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` |
