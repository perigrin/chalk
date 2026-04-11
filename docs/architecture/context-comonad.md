<!-- ABOUTME: Architecture of Chalk's Context comonad for parse history threading. -->
<!-- ABOUTME: Covers extract/extend/duplicate operations, tree structure, and semiring integration. -->

# Chalk Context Comonad Architecture

**Last updated**: 2026-04-10  
**Implementation**: `lib/Chalk/Bootstrap/Context.pm`  
**Original spec**: `docs/comonad-specification.md`

---

## Overview

`Chalk::Bootstrap::Context` is the parse history data structure threaded through the Earley parser and semantic action pipeline. It replaces the Shared Packed Parse Forest (SPPF) that a conventional Earley implementation would build. Where an SPPF is a global data structure holding all derivations at once, Context is a per-derivation value that accumulates as each parse step fires.

The design goal was to make Context a single shared object across all semirings: every semiring layer — Boolean, Precedence, TypeInference, Structural, SemanticAction — would hold a Context value, and each could read the parse history recorded by others. In the current implementation that goal is partially realized. Each semiring that stores meaningful state (TypeInference and SemanticAction) builds its own parallel Context tree. The shared-access mechanism is provided by `FilterComposite`, which passes the TypeInference Context to SemanticAction via `set_type_context()` just before SemanticAction's `on_complete` runs.

---

## Comonad Operations

A comonad is a functor equipped with two operations — `extract` and `extend` — satisfying three laws. The `duplicate` operation is derived from `extend`.

### extract

```
extract : Context -> Value
```

Returns the focus value stored in this context node. The focus is whatever the most recent semantic action or scan placed here:

- For a scan leaf: a string (the matched text) in SemanticAction, or a tag hashref (e.g., `{ valid => true, type => 'Str' }`) in TypeInference.
- For a rule completion: an IR node (SemanticAction) or a tag hashref with computed type information (TypeInference).
- For a multiply node: `undef`. Multiply nodes are structural combinators; they have no focus of their own.

The implementation is a direct field reader:

```perl
method extract() {
    return $focus;
}
```

### extend

```
extend : (Context -> Value) -> Context -> Context
```

Applies a function to this context and returns a new context whose focus is the function's return value. All other fields (`children`, `position`, `rule`, `annotations`) are copied from the original.

```perl
method extend($f) {
    my $new_focus = $f->($self);
    return Chalk::Bootstrap::Context->new(
        focus       => $new_focus,
        children    => $children,
        position    => $position,
        rule        => $rule,
        annotations => $annotations,
    );
}
```

This is the operation that semantic actions use to produce a result: the action receives the full context (with access to its children) and returns a new value, which becomes the focus of the returned context.

Note: `extend` copies `$children` from the original. This has a significant consequence described in the Tree Flattening section below.

### duplicate

```
duplicate : Context -> Context<Context>
```

Creates a context whose focus is the context itself. Derived directly from `extend`:

```perl
method duplicate() {
    return $self->extend(sub ($ctx) { return $ctx });
}
```

In practice, `duplicate` is not called by any current semiring code. It exists to satisfy the comonad interface and to support future use cases such as exploring alternative parses or implementing ambiguity-aware actions.

---

## Comonad Laws

A comonad must satisfy three laws. Using Perl pseudocode where `w` is a Context and `f`, `g` are functions from Context to value:

**Left identity**: `extract(extend(f, w)) == f(w)`

The focus of `extend(f, w)` is `f(w)` by construction. Calling `extract` on the result returns that focus. The law holds.

**Right identity**: `extend(extract, w) == w`

`extend(extract, w)` produces a new Context with focus `extract(w)` (i.e., `$focus`) and children/position/rule copied from `w`. This is structurally identical to `w` but is a distinct object because `Context->new(...)` always allocates. The law holds at the value level (same focus and same child references) but not at the identity level (different refaddr). This matters for hash-consing: the hash-cons caches in TypeInference and SemanticAction use refaddr equality as a fast-path check, so `extend(extract, w) != w` by object identity even though they are semantically equal.

**Associativity**: `extend(f, extend(g, w)) == extend(compose(f, g), w)`

Both sides apply `g` first (to `w`, yielding a context with focus `g(w)`), then apply `f` to the result. The current `extend` copies children from `$self`, not from the intermediate context. This means the right-hand side `extend(compose(f, g), w)` passes `w` directly to `f`, whereas the left-hand side passes a context derived from `w` with `g`'s focus but `w`'s children. The laws hold only when `f` accesses the focus and not the children, which is the normal case for single-value actions. Actions that traverse children to extract tags (as TypeInference does) will see different results depending on evaluation order.

In summary: the implementation satisfies the laws for simple value-transforming actions. It does not satisfy associativity for tree-traversing actions.

---

## Tree Structure

### How multiply Builds Trees

The Earley parser builds a Context tree through `multiply`. When recognizing a sequence `A B C`, the parser calls `multiply(one(), a_ctx)` after scanning `A`, then `multiply(prev, b_ctx)` after scanning `B`, and so on. Each `multiply` call creates a new Context node with `focus => undef` and `children => [$left, $right]`.

The resulting tree for `A B C` is:

```
multiply(multiply(one, scan_A), scan_B)
        /                           \
multiply(one, scan_A)            scan_B (focus = "B")
      /           \
    one         scan_A (focus = "A")
  (focus=undef)
```

This is a left-leaning binary tree. The leaves hold scan results (string text in SemanticAction, tag hashrefs in TypeInference). The internal nodes have `undef` focus and exist solely to connect children.

Both SemanticAction and TypeInference hash-cons their multiply nodes: given the same left and right operands (by refaddr), `multiply` returns the same object. This ensures that the FilterComposite identity-collapse optimization (detecting same-derivation alternatives) works correctly.

### How on_complete Uses the Tree

When a rule completes, the parser calls `on_complete($value, $rule_name, ...)` where `$value` is the accumulated multiply tree for that rule's entire right-hand side.

SemanticAction's `on_complete` does:

```perl
my $new_focus = $actions->$rule_name($value);
$result = Chalk::Bootstrap::Context->new(
    focus    => $new_focus,
    children => $value->children(),   # copies top-level children only
    position => $value->position(),
    rule     => $value->rule(),
);
```

TypeInference's `on_complete` calls `_extend_ctx_with_focus($value, $focus_hash, $rule_name)`, which does:

```perl
Chalk::Bootstrap::Context->new(
    focus       => $focus,
    children    => $value->children(),  # copies top-level children only
    position    => $value->position(),
    rule        => $value->rule(),
    annotations => $value->annotations(),
);
```

Both operations copy `$value->children()`, which are the children of the top-level multiply node (i.e., two children: the left subtree and the most recently scanned/completed item). They do not wrap `$value` itself as a child. This is the tree-flattening issue described in the next section.

### leaves and scanned_text

Context provides two tree-walking methods:

`leaves($node_class)` performs a depth-first traversal, stopping at any node with a defined focus and optionally filtering by class. It is used by SemanticAction action methods to collect child IR nodes.

`scanned_text()` performs a depth-first traversal collecting string focuses (scan results), ignoring ref-type focuses (IR nodes). This reconstructs the source text covered by a subtree.

Both methods are iterative (explicit stack) to avoid stack overflow on tall parse trees.

---

## Current Usage

### SemanticAction

SemanticAction uses Context to build the Sea of Nodes IR. The focus of a completed Context is an IR node (or `undef` for rules with no registered action). Action methods in `Actions.pm` receive the full Context for a completed rule and call `$ctx->leaves(...)` or `$ctx->children()` to access child IR nodes by position.

The `cfg_state` side-table (`%_cfg_state`, keyed by `refaddr`) stores control-flow graph state (current control token and variable scope) alongside the Context tree without polluting the focus. This state propagates through `multiply` chains and is updated by action methods via `update_cfg()`.

SemanticAction also provides `on_skip_optional` to create placeholder contexts for absent `X?` symbols, preserving positional child indexing for action methods that access children by position.

### TypeInference

TypeInference uses Context to carry type tags through the parse. The focus of a TypeInference Context is a hashref with fields such as:

- `valid` — always true for non-zero contexts
- `type` — inferred type string (e.g., `'Str'`, `'Int'`, `'Regex'`, `'Scalar'`)
- `call_symbol` — name of a builtin function seen at scan time
- `ident_text` — raw identifier text from a QualifiedIdentifier scan
- `op_text` — operator text from a BinaryOp or UnaryExpression scan
- `item_types` — arrayref of per-position types from an ExpressionList

TypeInference's `on_scan` produces these tag contexts and multiplies them into the accumulating value. TypeInference's `on_complete` dispatches to TypeInferenceActions methods (or to inline logic for CallExpression), computes a new focus hashref, and calls `_extend_ctx_with_focus` to attach it.

Tag retrieval for on_complete actions uses tree-walking methods (`_get_call_symbol`, `_get_item_types`, `_get_list_arity`) that descend through unfocused multiply nodes and stop at focused leaf nodes.

The `on_scan`/`on_complete` pairing also drives scan-time keyword rejection via `should_scan`. This does not use the Context tree directly; it uses the accumulated value's focus (if defined) or walks the multiply tree via `_get_call_symbol` to detect the `keys %hash` disambiguation case.

---

## Known Design Issue: Tree Flattening

The most significant gap between the design intent and the current implementation is that `extend` and `_extend_ctx_with_focus` both copy `$value->children()` into the result, rather than wrapping `$value` as a single child.

Consider a rule `CallExpression ::= QualifiedIdentifier ExpressionList`. After parsing `foo(1, 2)`, the accumulated value passed to `on_complete` is a multiply tree roughly shaped as:

```
multiply
  ├── multiply
  │     ├── ... (deeper history leading to QualifiedIdentifier completion)
  │     └── scan(QualifiedIdentifier, "foo") -- tagged with call_symbol => 'foo'
  └── complete(ExpressionList) -- tagged with item_types => ['Int', 'Int']
```

When TypeInference's `_extend_ctx_with_focus` fires for CallExpression, it produces:

```
Context(
  focus    => { valid => true, type => 'Int' },
  children => [left_subtree, complete(ExpressionList)]   # from value->children()
)
```

The call_symbol tag that came from the QualifiedIdentifier scan is now buried in `left_subtree`, not in the children of the CallExpression context. If a parent rule later tries to walk the tree to find `call_symbol`, it must descend into `left_subtree`. This works as long as there is no intervening `on_complete` that replaces the children with only the top-level pair.

The problem occurs across rule boundaries. If `on_complete` fires for a wrapper rule (e.g., `Expression ::= CallExpression`) and the wrapper's action returns a new focus without preserving the CallExpression subtree, the `call_symbol` tag from two levels down becomes unreachable via the new context's children. The tree-walkers in TypeInference (`_get_call_symbol` etc.) are the workaround: they descend through multiply nodes to find tags regardless of depth. But they only work when the children of each node still point back to the full multiply tree. Once `_extend_ctx_with_focus` replaces children with a shallow copy of `$value->children()`, the depth of the tree seen from the new context is only two levels deep: left-of-multiply and right-of-multiply at the point `on_complete` was called.

The correct fix would be to wrap `$value` as a single child in the resulting context:

```perl
# Correct extend for tree preservation:
Chalk::Bootstrap::Context->new(
    focus    => $new_focus,
    children => [$self],    # wrap self, not copy self's children
    ...
)
```

This would make the tree grow monotonically as rules complete, preserving the full parse history in the child chain. The diagnostic test `t/bootstrap/semiring-value-propagation.t` demonstrates that the Earley chart does build correct multiply trees (the tree-depth assertions in Tests 1, 2, and 3 pass), so the problem is specifically in the `on_complete` implementations in TypeInference and SemanticAction, not in the Earley infrastructure.

Until this is fixed, TypeInference actions that need to read tags across rule boundaries must use tree-walking methods and accept that some tag propagation paths are fragile.

---

## Historical Context: Orphaned EvalContext

The `semiring-optimizations` branch contained a prototype called `EvalContext` (introduced in commit `9b12e1f8`) that was designed to be a single shared context object accessible to all semirings simultaneously. Rather than each semiring maintaining its own parallel Context tree, a single EvalContext would accumulate all tags and all IR nodes together.

This prototype was not abandoned for technical reasons. The `semiring-optimizations` branch was orphaned in March 2026 when the bootstrap branch became the new `pu` (the old `pu` was archived as `archive/pu-2026-03-24`). At that point the EvalContext work was not in a state that could be cleanly ported, and the per-semiring Context approach was already working well enough to move forward.

The EvalContext design remains relevant as a future direction. If the tree-flattening issue is fixed and the per-semiring Context trees are unified into a single structure, the result would closely resemble what EvalContext was prototyping.

---

## Design Intent vs. Current Reality

The intended design, as described in `docs/comonad-specification.md`, is:

> The comonad operates inside the semantic action semiring... The semiring's multiply operation chains contexts.

The intent was a single Context type shared across all semirings, with multiply building a unified parse history tree that any semiring could read. Concretely:

- TypeInference would store type tags as focuses in the shared tree.
- SemanticAction would call `ctx->leaves(IR::Node)` to find child IR nodes, and separately call `ctx->leaves()` with a filter for tag nodes to read TypeInference's annotations.
- The `FilterComposite.set_type_context()` bridge would be unnecessary; SemanticAction would find type information in its own Context tree because the tree would contain it.

The current reality is:

- TypeInference and SemanticAction each maintain separate, independent Context trees.
- The trees are built in parallel from the same Earley events but carry different focus types and different hash-cons caches.
- FilterComposite bridges them by calling `set_type_context($ti_ctx)` before SemanticAction's `on_complete` runs, making the TypeInference Context for the current completion available via the `current_type_context()` class method.
- SemanticAction actions that need type information (e.g., MethodDefinition reading the return type) call `SemanticAction::current_type_context()` and walk its tree directly.

This arrangement works but creates coupling between the two semirings that the comonad design was intended to avoid. A SemanticAction action method now needs to understand TypeInference's tag structure to extract type information, which mixes concerns across semiring layers.

---

## Summary of Structural Properties

| Property | Specified | Implemented |
|---|---|---|
| extract returns focus | Yes | Yes |
| extend produces new context with function result as focus | Yes | Yes |
| extend preserves children from original | Yes (copies) | Yes (copies, not wraps) |
| duplicate derived from extend(id) | Yes | Yes |
| Comonad left identity law | Required | Holds |
| Comonad right identity (value equality) | Required | Holds at value level, not identity level |
| Comonad associativity (tree-traversing actions) | Required | Does not hold |
| Single shared context across all semirings | Intended | Not implemented; parallel trees with bridge |
| Tree-flattening issue in on_complete | Not anticipated | Present; workaround via tree-walkers |
| Diagnostic test for tree-depth contract | Not in spec | Present: t/bootstrap/semiring-value-propagation.t |

---

## Related Files

- `lib/Chalk/Bootstrap/Context.pm` — implementation
- `lib/Chalk/Bootstrap/Semiring/TypeInference.pm` — uses Context for type tags
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — uses Context for IR nodes and CFG state
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` — bridges TypeInference and SemanticAction contexts
- `lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm` — rule-specific type computation methods
- `t/bootstrap/semiring-value-propagation.t` — diagnostic test for the parse history contract
- `docs/comonad-specification.md` — original design specification
