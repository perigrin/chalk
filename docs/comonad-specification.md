# Comonad Specification for Chalk::Bootstrap::Context

## Overview

The `Chalk::Bootstrap::Context` implements the comonad interface to thread evaluation context through the Earley parser and semantic action pipeline. This enables functional composition of semantic actions without mutation.

## Comonad Laws

A comonad must satisfy three laws:

```
extract(extend(f, w)) ≡ f(w)                    # Left identity
extend(extract, w) ≡ w                          # Right identity
extend(f, extend(g, w)) ≡ extend(f ∘ g, w)     # Associativity
```

Where:
- `w` is a comonad context
- `f` and `g` are functions from context to value
- `∘` is function composition

## Operations

### extract

**Signature**: `Context → Value`

**Purpose**: Extract the current focus value from the context.

**Semantics**: Returns the IR node at the current focus position. For Earley items, this is the semantic value computed by the most recent semantic action.

**Example**:
```perl
my $ctx = Context->new(
    focus => $ir_node,
    ...
);

my $value = $ctx->extract();  # Returns $ir_node
```

### extend

**Signature**: `(Context → Value) → Context → Context`

**Purpose**: Apply a function to every possible focus of the context, creating a new context.

**Semantics**: For parsing, `extend` applies a semantic action to all children of the current parse node, aggregating their IR nodes into a new parent node.

**Implementation convenience — `%opts`**: The implementation of `extend` accepts an optional `%opts` hash: `$ctx->extend($f, rule => $name, annotations => $ann, token => $tok, is_zero => $flag, error => $err)`. Any field passed in `%opts` overrides the value propagated from the original context. This is an implementation extension for cases where a semantic action wants to override a single field without re-allocating from scratch; it does not change the formal comonad signature.

**Example**:
```perl
# Semantic action that combines child IR nodes
my $action = sub ($ctx) {
    my @child_nodes = map { $_->extract() } $ctx->children();
    return IR::Node::Constructor->new(class => 'Expression', elements => \@child_nodes);
};

my $new_ctx = $ctx->extend($action);
my $parent_node = $new_ctx->extract();  # Aggregated result
```

### duplicate

**Signature**: `Context → Context<Context>`

**Purpose**: Create a context of contexts, where each sub-context represents a different focus.

**Semantics**: For parsing, `duplicate` creates nested contexts for each alternative or child in the parse tree. Used to explore ambiguous parses or parallel alternatives.

**Example**:
```perl
my $ctx_of_ctxs = $ctx->duplicate();

# Each child context can be extracted independently
for my $child_ctx ($ctx_of_ctxs->children()) {
    my $child_value = $child_ctx->extract();
    # Process child_value
}
```

**Note**: `duplicate` is derived: `duplicate(w) = extend(id, w)` where `id` is the identity function.

## Context Structure

A `Context` contains:

1. **Focus**: The current IR node or parse value
2. **Children**: List of child contexts (for sequences/alternatives)
3. **Position**: Current input position (for error reporting)
4. **Rule**: Current grammar rule being evaluated (for debugging)
5. **Annotations**: Hash keyed by slot name (e.g. `type`, `precedence`, `structural`, `cfg`) that filtering semirings populate during the parse (see `architecture/parsing-pipeline.md` for the slot protocol)
6. **Token**: Scan token payload, carried through `extend` so downstream consumers can reach the original scan
7. **is_zero**: Boolean flag marking the algebraic zero element — a parse-rejection value that propagates through `multiply` and short-circuits FilterComposite dispatch. Normal during backtracking; not an error.
8. **error**: Optional structured error value for system failures (malformed IR, semantic action raised, invariant violations) that are distinct from parse-rejection. An errored Context keeps propagating through composition; because `extend` preserves the children chain, the Context tree below serves as the error trace without a separate stack-trace mechanism.

## Threading Through Semantic Actions

When an Earley completion occurs:

1. **Create child contexts**: One context per symbol in the completed sequence
2. **Apply semantic action**: Use `extend` to map the action over children
3. **Extract result**: The new focus becomes the parent IR node
4. **Return new context**: With the parent node as focus

**Example flow**:
```perl
# Completed rule: Element ::= Atom Quantifier?
# Child 1 context: focus = IR::Constructor(class='Symbol', Atom)
# Child 2 context: focus = IR::Constructor(class='Symbol', Quantifier, quantifier='?')

my $element_action = sub ($ctx) {
    my @children = map { $_->extract() } $ctx->children();
    my $atom = $children[0];
    my $quant = $children[1];  # May be undef for '?'

    return IR::Node::Constructor->new(
        class      => 'Symbol',
        type       => $atom->type,
        value      => $atom->value,
        quantifier => $quant ? $quant->value : undef,
    );
};

my $parent_ctx = $child_ctx->extend($element_action);
my $element_node = $parent_ctx->extract();
```

## Immutability

All context operations return **new contexts**. The original context is never mutated. This ensures:

- Thread safety (if needed later)
- Referential transparency
- Ability to backtrack in ambiguous parses
- Deterministic evaluation order

## Failure Modes

Chalk distinguishes two kinds of failure on a Context, and handles them separately so they do not conflate.

**Parse rejection (algebraic).** A semiring's `multiply` may return a zero Context, represented by `is_zero=true`. This means "this branch is not a valid parse" and is a normal value in the algebra — FilterComposite short-circuits, the branch is discarded, the parser backtracks. No error is raised. `extract` on a zero Context is total and simply returns whatever focus the zero has (typically `undef`). This is the right primitive for parse rejection because rejection is a value, not an exception.

**System failure (recorded).** A semantic action may raise because the IR is malformed, an invariant is violated, or some other real problem occurred. For these cases the Context carries an `error` slot (see Context Structure above) that records the structured error alongside the history. Because `extend` preserves the children chain, the Context tree below an errored Context is the error trace: walking down gives you "where we were when the error happened" for free.

**`extract` stays total in both cases.** It is a projection (`Context<T> -> T`) and never throws. This preserves the comonad laws:

- Left identity: `extract(extend(f, w)) == f(w)`
- Right identity: `extend(extract, w) == w` (at the value level)
- Associativity: `extend(f, extend(g, w)) == extend(compose(f, g), w)` (for reachable content)

A throwing `extract` would break totality and, through it, break the composition laws that make the comonad framework useful. Errors are therefore data carried on the Context, not exceptions thrown from its projection.

An earlier version of this specification described a distinct `Error` subclass of Context whose `extract` threw on failure. That design is superseded: it conflated parse rejection with system failure, and its throwing `extract` violated the comonad laws.

## Integration with Semirings

The comonad operates inside the semantic-action branch of Chalk's five-semiring FilterComposite pipeline: Boolean, Precedence, TypeInference, Structural, and SemanticAction. The full pipeline and its ordering rationale are documented in [`architecture/parsing-pipeline.md`](architecture/parsing-pipeline.md); only SemanticAction carries Context values — the filtering semirings write their results into `Context.annotations` slots.

The semiring's `multiply` operation chains contexts:
```perl
# Multiply two contexts (sequence)
sub multiply($left_ctx, $right_ctx) {
    return Context->new(
        focus    => undef,  # Will be computed by semantic action
        children => [$left_ctx, $right_ctx],
        ...
    );
}
```

## Testing

Test coverage for the comonad implementation lives in `t/bootstrap/` — principally `t/bootstrap/semiring-value-propagation.t` for the tree-depth contract and `t/bootstrap/context-visitor.t`, `context-extend-wrap.t`, `context-extend-opts.t` for individual behaviors. Tests exercise the laws against small hand-built contexts and verify that complete parse pipelines produce expected Context shapes. See the test files for the current coverage surface.

## References

- **Comonad theory**: Uustalu & Vene, "The Essence of Dataflow Programming" (2005)
- **Parsing comonads**: Kmett, "Cofree Comonads and the Expression Problem" (blog post)
- **Chalk parser**: `lib/Chalk/Parser.pm` (does not use comonads, but shows Earley structure)
