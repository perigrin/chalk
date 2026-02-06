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

## Error Handling

If a semantic action fails during `extend`:

1. Capture the error with context information (position, rule, input)
2. Return a special `Error` context that propagates upward
3. `extract` on an `Error` context throws with full context trace

This provides detailed parse error messages with rule stack traces.

## Integration with Semirings

The comonad operates **inside** the semantic action semiring:

- **Boolean semiring**: No context needed (just true/false)
- **Semantic action semiring**: Each value is a `Context`
- **Composite semiring**: Boolean × SemanticAction = (Bool, Context)

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

## Implementation Phases

### Phase 1a (Earley Parser)

Implement only `extract`:
- Context holds a single IR node (or undef for Boolean semiring)
- `extract` returns that node
- Defer `extend` and `duplicate`

### Phase 2b (Semantic Actions)

Implement full comonad:
- Add `children` field to Context
- Implement `extend` to map semantic actions over children
- Implement `duplicate` (if needed for ambiguous parses)
- Add position/rule fields for error reporting

## Testing Strategy

Create `t/bootstrap/comonad-threading.t` with these test cases:

1. **Simple extract**: Context with single IR node
2. **Sequence extend**: Two-child context with combining action
3. **Alternative extend**: Multiple alternatives, action chooses/merges
4. **Nested extend**: Three-level rule hierarchy (e.g., Grammar → Rule → Alternatives)
5. **Error propagation**: Failed semantic action creates Error context

Each test should:
- Create contexts manually (no parser needed)
- Apply semantic actions via `extend`
- Verify `extract` returns expected IR node
- Verify comonad laws hold

## References

- **Comonad theory**: Uustalu & Vene, "The Essence of Dataflow Programming" (2005)
- **Parsing comonads**: Kmett, "Cofree Comonads and the Expression Problem" (blog post)
- **Chalk parser**: `lib/Chalk/Parser.pm` (does not use comonads, but shows Earley structure)
