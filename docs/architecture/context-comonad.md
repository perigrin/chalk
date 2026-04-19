<!-- ABOUTME: Architecture of Chalk's Context comonad for parse history threading. -->
<!-- ABOUTME: Covers extract/extend/duplicate operations, tree structure, and semiring integration. -->

# Chalk Context Comonad Architecture

**Last updated**: 2026-04-19
**Implementation**: `lib/Chalk/Bootstrap/Context.pm`
**Original spec**: `docs/comonad-specification.md`

---

## Overview

`Chalk::Bootstrap::Context` is the parse-history data structure threaded
through the Earley parser and semantic-action pipeline. It replaces the
Shared Packed Parse Forest (SPPF) that a conventional Earley
implementation would build: where an SPPF is a global structure holding
all derivations at once, Context is a per-derivation value that
accumulates as each parse step fires.

A single shared Context tree flows through every semiring. SemanticAction
owns the tree structure; TypeInference, Precedence, and Structural write
their results into the node's `annotations` hash (`annotations->{type}`,
`annotations->{precedence}`, `annotations->{structural}`); CFG state
lives in `annotations->{cfg}`; Boolean operates via the `is_zero` flag
on the Context. FilterComposite acts as an adapter, extracting annotation
values, dispatching to each component semiring's native methods, and
assembling results back into a new Context via `_wrap_sa_result()`. The
unified-Context design landed in PR #702 (Milestone 17); callback
elimination (`should_scan`, `on_complete`, `on_scan`, `on_skip_optional`,
`on_epoch_commit`) followed in Milestone 18 (#708, PR #715).

One transitional bridge remains: `set_type_context()` /
`current_type_context()` in `Chalk::Bootstrap::Semiring::SemanticAction`,
called by FilterComposite and consumed by `MethodDefinition` in
`Perl/Actions.pm` (which dies if the context is unavailable). The
bridge was expected to be removed alongside `on_complete`, but outlived
#708; removing it is follow-up work. The `on_merge` callback on
SemanticAction is also still live, called from FilterComposite as a
workaround for an Earley stale-value merge bug (see `_fix_postfix_chain`
in `Perl/Actions.pm` for related workarounds).

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
method extend($f, %opts) {
    my $new_focus = $f->($self);
    return Chalk::Bootstrap::Context->new(
        focus       => $new_focus,
        children    => [$self],    # wraps self, growing the tree
        position    => $position,
        rule        => (exists $opts{rule} ? $opts{rule} : $rule),
        annotations => (exists $opts{annotations} ? $opts{annotations} : $annotations),
    );
}
```

This is the operation that semantic actions use to produce a result: the action receives the full context (with access to its children) and returns a new value, which becomes the focus of the returned context.

`extend` wraps `$self` as a single child in the new context, rather than copying `$self->children()`. This means the tree grows monotonically as rules complete: each call to `extend` extends the chain by one node, preserving the full parse history below. The optional `%opts` parameters allow callers to supply `rule` and `annotations` overrides without mutating the original context.

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

Both sides apply `g` first (to `w`, yielding a context with focus `g(w)`), then apply `f` to the result. Because `extend` wraps `$self` as a child rather than copying `$self->children()`, the left-hand side passes a context derived from `w` that contains `w` in its child chain; `f` can therefore traverse down to `w` and see all of `w`'s descendants. The right-hand side passes `w` directly to `f`. For tree-traversing actions the two sides are still not identical — the left side has an extra wrapper node — but both preserve the full parse history, so actions that descend to find tags will reach the same leaves either way.

In summary: the implementation satisfies the laws for simple value-transforming actions. For tree-traversing actions, associativity holds at the level of reachable content, though the wrapper depth differs between the two evaluation orders.

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

### How Rule Completion Uses the Tree

When a rule completes, FilterComposite's `multiply` (in completion mode) calls `$value->extend(...)` where `$value` is the accumulated multiply tree for that rule's entire right-hand side.

SemanticAction's completion path:

```perl
$result_ctx = $value->extend(
    sub ($ctx) { $actions->$rule_name($ctx) },
    rule => $rule_name,
);
```

TypeInference's `_extend_ctx_with_focus` also delegates to `$value->extend(...)`:

```perl
$value->extend(
    sub ($ctx) { $focus },
    rule => $rule_name,
)
```

`_extend_ctx_with_focus` additionally wraps the `extend` call with hash-consing: if an identical context (same focus, same wrapped child, same rule) already exists in the hash-cons table, the cached object is returned instead of a new allocation.

Both operations wrap `$value` as a single child in the result, rather than copying `$value->children()`. The full multiply tree built during the rule's right-hand side scan is therefore reachable by descending from the new context's child.

### leaves, scanned_text, and Visitor Methods

Context provides both legacy tree-walking methods and a visitor API.

`leaves($node_class)` performs a depth-first traversal, stopping at any node with a defined focus and optionally filtering by class. It is used by SemanticAction action methods to collect child IR nodes. It is implemented via `walk_all`.

`scanned_text()` performs a depth-first traversal collecting string focuses (scan results), ignoring ref-type focuses (IR nodes). This reconstructs the source text covered by a subtree. It is **not** implemented via the visitor methods: `scanned_text` recurses into ref-focused nodes to find string scans beneath them, which is incompatible with the visitor methods' stop-at-all-focused-nodes behavior.

The visitor API added in #699 provides three methods:

- `walk($callback, %opts)` — depth-first traversal; returns the first focused node for which `$callback` returns true. Accepts `reverse => true` for right-to-left traversal.
- `walk_all($callback, %opts)` — same traversal; returns an arrayref of all focused nodes matching `$callback`.
- `walk_acc($init, $callback, %opts)` — accumulator variant; threads an accumulator value through all focused matching nodes, returning the final accumulated value.

All visitor methods stop descent when they reach a focused node (they do not recurse below it). All three support `reverse => true`. Recursive tree-walkers previously scattered across TypeInference, TypeInferenceActions, and ConciseTree have been replaced with `walk()` calls, removing approximately 100 lines of duplicated traversal logic.

All methods are iterative (explicit stack) to avoid stack overflow on tall parse trees.

---

## Current Usage

### SemanticAction

SemanticAction uses Context to build the Sea of Nodes IR. The focus of a completed Context is an IR node (or `undef` for rules with no registered action). Action methods in `Actions.pm` receive the full Context for a completed rule and call `$ctx->leaves(...)` or `$ctx->children()` to access child IR nodes by position.

CFG state (control flow, scope) lives in `annotations->{cfg}` on each Context node and propagates through `multiply` chains. Action methods update this state via `update_cfg()`.

### TypeInference

TypeInference uses Context to carry type information through the parse. Type tags are written to `annotations->{type}` on each Context node, with fields such as:

- `valid` — always true for non-zero contexts
- `type` — inferred type string (e.g., `'Str'`, `'Int'`, `'Regex'`, `'Scalar'`)
- `call_symbol` — name of a builtin function seen at scan time
- `ident_text` — raw identifier text from a QualifiedIdentifier scan
- `op_text` — operator text from a BinaryOp or UnaryExpression scan
- `item_types` — arrayref of per-position types from an ExpressionList

TypeInference computes these annotations during `multiply` (both scan and completion paths). Tag retrieval for completion actions uses thin wrapper methods (`_get_call_symbol`, `_get_item_types`, `_get_list_arity`) that delegate to `$ctx->walk()`.

Keyword-as-identifier rejection is handled by `multiply` returning a zero Context for rejected branches (see the Appendix for the history of the earlier `should_scan` mechanism).

---

## Summary of Structural Properties

| Property | Specified | Implemented |
|---|---|---|
| extract returns focus | Yes | Yes |
| extend produces new context with function result as focus | Yes | Yes |
| extend preserves children from original | Yes (copies) | Yes (wraps self as child) |
| duplicate derived from extend(id) | Yes | Yes |
| Comonad left identity law | Required | Holds |
| Comonad right identity (value equality) | Required | Holds at value level, not identity level |
| Comonad associativity (tree-traversing actions) | Required | Holds for reachable content; wrapper depth differs between evaluation orders |
| Single shared context across all semirings | Intended | Realized (#702, M17); `set_type_context` bridge outstanding (see Appendix) |
| Tree-flattening issue in completion | Not anticipated | Resolved (#698, #701) |
| Diagnostic test for tree-depth contract | Not in spec | Present: t/bootstrap/semiring-value-propagation.t |
| Visitor methods for tree traversal | Not in spec | Present: walk/walk_all/walk_acc (#699) |

---

## Related Files

- `lib/Chalk/Bootstrap/Context.pm` — implementation
- `lib/Chalk/Bootstrap/Semiring/TypeInference.pm` — writes type annotations
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — builds IR nodes and CFG state
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` — orchestrates the shared Context across component semirings
- `lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm` — rule-specific type computation methods
- `t/bootstrap/semiring-value-propagation.t` — diagnostic test for the parse history contract
- `t/bootstrap/context-visitor.t` — visitor method tests (walk/walk_all/walk_acc)
- `t/bootstrap/context-extend-wrap.t` — extend wrapping behavior tests
- `t/bootstrap/context-extend-opts.t` — extend opts override tests
- `docs/comonad-specification.md` — original design specification

---

## References

- Uustalu, Tarmo and Varmo Vene. "The Essence of Dataflow Programming." *Central European Functional Programming School (CEFP)*, Lecture Notes in Computer Science 4164, 2005. Comonads as a framework for context-dependent computation — the theoretical basis for using a comonad to thread parse history.
- Mac Lane, Saunders. *Categories for the Working Mathematician*. Springer, 1971. Original categorical definition of comonads (as the dual of monads).
- Scott, Elizabeth. "SPPF-Style Parsing From Earley Recognisers." *Electronic Notes in Theoretical Computer Science*, 203(2):53-67, 2008. The conventional SPPF approach to Earley parse forests that Context replaces.

---

## Appendix: History

### Tree Flattening (Resolved in #698, #701)

The tree-flattening issue that previously existed has been fixed.

The root cause was that `extend` and `_extend_ctx_with_focus` copied
`$value->children()` into the result context rather than wrapping
`$value` as a single child. This meant each completion produced a
context whose tree depth was at most two levels from the point of
completion, discarding the full parse history built up during the rule's
right-hand side.

The fix: `extend` now wraps `$self` as a single child (`children =>
[$self]`), and both `_extend_ctx_with_focus` (#701) and completion
handling (#701) call `$value->extend(...)` rather than constructing
`Context->new(...)` directly. The tree now grows monotonically as rules
complete, and the full multiply tree built during scanning remains
reachable by descending through the chain.

The diagnostic test `t/bootstrap/semiring-value-propagation.t` validates
this contract. The recursive tree-walkers that were the workaround for
tree flattening have been replaced with visitor methods on Context
(#699).

### Orphaned EvalContext

The `semiring-optimizations` branch contained a prototype called
`EvalContext` (introduced in commit `9b12e1f8`) that was designed to be
a single shared context object accessible to all semirings
simultaneously. Rather than each semiring maintaining its own parallel
Context tree, a single EvalContext would accumulate all tags and all IR
nodes together.

This prototype was not abandoned for technical reasons. The
`semiring-optimizations` branch was orphaned in March 2026 when the
bootstrap branch became the new `pu` (the old `pu` was archived as
`archive/pu-2026-03-24`). At that point the EvalContext work was not in
a state that could be cleanly ported, and the per-semiring Context
approach was already working well enough to move forward.

The EvalContext design was the conceptual predecessor of the
unified-Context architecture that eventually landed in PR #702.

### Callback Elimination (#702, #708)

Earlier versions of the Context architecture relied on a set of
semiring callbacks — `should_scan`, `on_scan`, `on_complete`,
`on_skip_optional`, `on_epoch_commit`. These were removed in Milestone
17 (#702) and Milestone 18 (#708, PR #715) in favor of a pure
`multiply`-based interface, where rejected branches produce a zero
Context and accepted branches produce a Context with updated
annotations. The callbacks were a premature optimization: the `multiply`
path already produces the same semantic result, and the separate
callback surface added complexity without earning its weight.
`should_scan` may be restored in the future as a multiply fast-path if
profiling demands it.

`on_merge` survived the elimination and is still called from
FilterComposite as a workaround for an Earley stale-value merge bug
where `add()` can pick the older value over a CFG-state-updated winner.
It is live architecture in the sense that it runs on every merge, but
its justification is a parser-level bug, not a clean semiring-layer
abstraction.

### `set_type_context` Bridge (Outstanding)

The `set_type_context()` / `current_type_context()` pair in
`Chalk::Bootstrap::Semiring::SemanticAction` is a transition mechanism
predating the fully unified Context. FilterComposite calls
`set_type_context()` during `multiply` (after TypeInference completes,
before SemanticAction runs), and `MethodDefinition` in `Perl/Actions.pm`
reads it via `current_type_context()`. The bridge was expected to be
removed alongside `on_complete` in #708, but outlived that work.
Removing it — by having `MethodDefinition` read types from
`annotations->{type}` on the shared Context instead — is outstanding
follow-up work.
