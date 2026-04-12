# Unified Context Design (#702)

**Date**: 2026-04-12
**Status**: Draft (revised after pushback)
**Depends on**: #698 (extend wraps), #699 (visitor), #701 (refactor to extend)

## Problem

TypeInference and SemanticAction each build separate Context trees from
the same Earley events. FilterComposite bridges them with
`set_type_context()` so SA can read TI's type annotations. This
coupling exists because the N-tuple representation
`[$bool, $prec, $ti_ctx, $struct, $sa_ctx]` stores five separate
values that cannot see each other.

## Insight

The N-tuple is a product semiring `S1 × S2 × S3 × S4 × S5`. Whether
the product is represented as five separate objects in an arrayref or
as one object with five named slots, the algebra is the same.

A single object lets semirings read each other's slots. Cross-semiring
communication (TI writing type tags, SA reading them) becomes natural
field access instead of a side-channel bridge.

## Theoretical foundation

The design aligns with Goodman's semiring parsing framework (1999).
Goodman defines two operations: `multiply` for sequential combination
and `add` for alternative combination. All parse values are computed
through these two operations. There is no `on_complete` callback in
the formalism.

Our semirings perform disambiguation analogous to the Viterbi semiring,
which picks the highest-probability parse through its `add` operation.
Precedence picks the highest-precedence parse. TypeInference picks the
type-valid parse. Structural picks the structurally richer parse. Each
semiring's `add` IS its disambiguation function.

Cross-component communication (one semiring reading another's
annotations) has no direct precedent in the parsing literature. The
closest algebraic models are Eisner's expectation semiring (2001),
where a probability component drives an accumulator component via
R-module structure, and Wirsching's semidirect product of semirings
(2010), where one semiring acts on another via endomorphisms. Our
approach is pragmatic: semirings share a Context object and read each
other's named annotation slots.

## Design

### One Context, annotation slots

Replace the N-tuple with a single Context object. Each semiring
reads and writes its own named annotation slot:

```
Context:
  focus       => $ir_node          (SemanticAction's output)
  children    => [...]             (parse tree structure)
  annotations => {
      precedence => $level,
      type       => { valid => true, type => 'Int', ... },
      structural => $bitfield,
  }
  token       => $token_name       (what symbol this fills in parent)
  rule        => $rule_name
  position    => $pos
  is_zero     => true/false        (single flag, any semiring can set)
```

Note: Boolean does not need an annotation slot. It operates entirely
through `is_zero` — a valid derivation is non-zero, an invalid one
is zero.

### Pure semiring operations: multiply, add, zero, one

`on_complete` is eliminated. All work happens in `multiply` and `add`,
aligning with Goodman's formalism.

#### multiply — incremental reification

`multiply` combines two Contexts sequentially and *reifies* the value.
The value isn't fully real until multiply provides the context that
gives it meaning. A scanned identifier is just text until it's
multiplied with `(` and an argument list — then it becomes a call.

Each semiring's multiply:
1. Receives the full Context (reads its own annotation slot)
2. Computes its contribution given the combined children
3. Returns a new Context with its annotation slot updated

The parser annotates the Context with the **token name** — what
symbol in the parent rule this value fills. This is how SemanticAction
knows what to build: not "rule CallExpression completed" but "token
CallExpression is being multiplied into Statement."

Reification is incremental. A child doesn't need to be fully reified
when its own rule completes — it reifies when the parent multiplies
it in, because that's when the full context is available.

#### add — disambiguation

`add` combines two alternative Contexts for the same span and rule:

- Both zero → return zero
- Left zero → return right
- Right zero → return left
- Both non-zero → each semiring disambiguates via its annotation slot

Each semiring's `add` reads its annotation slot from both alternatives
and picks the winner (like Viterbi picks the higher probability). The
priority ordering (Precedence > TypeInference > Structural > SA)
determines which semiring disambiguates first.

If no semiring can disambiguate (both alternatives are equivalent from
every semiring's perspective), this is unresolved ambiguity. The
Context can pack both alternatives and flag `is_ambiguous`. Higher
rules get a chance to resolve it through subsequent multiplies. Only
if ambiguity reaches `Program` does the parser throw an exception.

#### is_zero — single flag

Any semiring can kill a derivation by returning a Context with
`is_zero` set. One field, one check. Replaces the current pattern of
iterating through N-tuple slots checking each semiring's zero.

### FilterComposite changes

FilterComposite passes one Context to each semiring. For each
operation (multiply, add, on_scan), all semirings receive the same
Context, each returns a Context with its annotation slot updated, and
FilterComposite merges the annotation slots into one result.

Each semiring's operation is pure: `(Context, ...) -> Context`. The
operations are idempotent per-slot — each semiring writes only its
own slot, so merging is conflict-free.

`_filter_compare` goes away. The priority ordering moves into `add`:
semirings are consulted in order, first to disambiguate wins.

`set_type_context` / `current_type_context` go away. SA reads TI's
annotations directly from the shared Context.

### on_complete elimination

`on_complete` is not part of Goodman's semiring formalism. It was a
pragmatic extension to batch work at rule boundaries. With
incremental reification through `multiply`, this work happens
naturally as values are combined.

SemanticAction's rule-name dispatch (calling `$actions->$rule_name`)
moves to multiply, keyed by the token name on the Context. The parser
annotates the Context with the token name — what symbol in the parent
rule was just satisfied — so SA's multiply knows which action to run.

This also subsumes the Leo optimization (#700). Leo skips intermediate
completions and resolves them later. Without `on_complete`, there are
no intermediate completions to skip — reification is always
incremental through multiply.

### What goes away

- `on_complete` callback on all semirings
- `set_type_context()` / `current_type_context()` bridge
- `_filter_compare` in FilterComposite
- Parallel Context trees (TI and SA no longer build independent trees)
- N-tuple bookkeeping in FilterComposite
- Per-semiring hash-cons caches for Context objects (one cache)

### What stays the same

- The semiring algebra (product semiring, same axioms)
- FilterComposite as orchestrator
- Context comonad operations (extract, extend, walk)
- The Earley parser core (predict, scan, complete)
- Hash-consing (one unified cache)

### Hash-consing

One cache keyed by the full annotation set. Two Contexts with the same
tree structure but different type tags or precedence levels remain
distinct.

### scanned_text() concern

`scanned_text()` has different traversal semantics from `walk()` — it
recurses into ref-focused nodes. With a unified tree, the focused
values change (focus is now IR node, not type tags). Needs review to
ensure it still finds string scans correctly.

## Migration strategy

Incremental. Each step must leave all tests passing.

1. Add `token` field and `is_zero` flag to Context
2. Add annotation slots to Context (backward compatible, empty default)
3. Move Boolean to is_zero-only (no annotation slot)
4. Move Precedence to read/write annotations->{precedence}
5. Move Structural to read/write annotations->{structural}
6. Move TypeInference to write annotations->{type}
7. Move SemanticAction to read annotations->{type} directly
8. FilterComposite: pass single Context instead of N-tuple
9. Remove set_type_context bridge and _filter_compare
10. Migrate on_complete logic into multiply (token-name dispatch)
11. Remove on_complete from semiring interface
12. Clean up dead code

## Open questions

- Cache key strategy for unified annotations — how to efficiently
  hash-cons when the key includes all semiring data.
- Token name annotation: does the parser set this on the Context
  before calling multiply, or does multiply infer it from the
  grammar structure in the Context?
- Ambiguity packing: what does the packed Context look like when
  add returns both alternatives? Is `children => [$left, $right]`
  with `is_ambiguous => true` sufficient, or do we need a distinct
  packed node type?
- How does `should_scan` fit? It's also not in Goodman's formalism.
  Could it become part of multiply (multiply with a scan result
  returns zero if the scan is invalid)?

## Subsumes

- **#700 (Leo optimization)**: Without on_complete, Leo's
  "skip intermediate completions" becomes the default behavior.
  Reification is always deferred to multiply.
- **#702 original scope**: Unified annotation slots replace the
  N-tuple, eliminating the TI/SA bridge.
