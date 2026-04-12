# Unified Context Design (#702)

**Date**: 2026-04-12
**Status**: Draft
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
as one object with five named slots, the algebra is the same. The
semiring operations (multiply, add, on_complete, on_scan, is_zero)
work identically either way.

The only practical difference is that a single object lets semirings
read each other's slots. Cross-semiring communication (TI writing type
tags, SA reading them) becomes natural field access instead of a
side-channel bridge.

## Design

### One Context, annotation slots

Replace the N-tuple with a single Context object. Each semiring
reads and writes its own named annotation slot:

```
Context:
  focus       => $ir_node          (SemanticAction's output)
  children    => [...]             (parse tree structure)
  annotations => {
      boolean    => true/false,
      precedence => $level,
      type       => { valid => true, type => 'Int', ... },
      structural => $bitfield,
  }
  rule        => $rule_name
  position    => $pos
```

### FilterComposite changes

FilterComposite passes one Context to each semiring instead of
extracting a per-semiring slot from an arrayref.

- **multiply($left, $right)**: Calls each semiring's multiply in
  sequence, each reading/writing its own annotation slot on the
  shared Context. The Context tree structure (children) is built
  once, not five times in parallel.

- **on_scan**: Each semiring annotates the scan result on the
  shared Context.

- **on_complete**: Each semiring extends the Context, adding its
  annotations. No `set_type_context` needed — SA reads TI's
  annotations directly from the Context.

- **add**: Each semiring's add reads its annotation slot from both
  alternatives. First semiring to express a preference wins, same
  as today.

- **is_zero**: Single field on Context. Any semiring can set it
  during on_complete to kill a derivation. One check instead of
  iterating through slots.

### Semiring interface changes

Each semiring's operations change from receiving their own value type
to receiving the shared Context:

| Operation | Before | After |
|-----------|--------|-------|
| multiply | `($my_val_left, $my_val_right)` | `($ctx_left, $ctx_right)` |
| on_scan | `($my_val, ...)` | `($ctx, ...)` |
| on_complete | `($my_val, ...)` | `($ctx, ...)` |
| add | `($my_val_left, $my_val_right)` | `($ctx_left, $ctx_right)` |
| is_zero | `($my_val)` | `($ctx)` |
| one | returns `$my_identity` | returns shared identity Context |
| zero | returns `$my_zero` | returns shared zero Context |

Boolean reads `$ctx->annotations()->{boolean}`.
Precedence reads `$ctx->annotations()->{precedence}`.
And so on.

### What goes away

- `set_type_context()` / `current_type_context()` bridge
- Parallel Context trees (TI and SA no longer build independent trees)
- N-tuple bookkeeping in FilterComposite
- Per-semiring hash-cons caches for Context objects (one cache)

### What stays the same

- The semiring algebra (product semiring, same axioms)
- Priority ordering in add (Boolean > Precedence > TI > Structural > SA)
- FilterComposite as orchestrator
- Context comonad operations (extract, extend, walk)
- The Earley parser (it sees one semiring, FilterComposite)

### is_zero simplification

Instead of each semiring maintaining its own zero sentinel and
FilterComposite checking `$sr->is_zero($val->[$i])` for each slot,
the Context has a single is_zero flag. Any semiring that determines
a derivation is invalid sets this flag (or returns the shared zero
Context). FilterComposite checks one field.

### Hash-consing

Currently TI and SA each maintain their own hash-cons caches. With a
unified Context, one cache keyed by the full annotation set. The
cache key includes all annotation slots so that two Contexts with
the same structure but different type tags or precedence levels
remain distinct.

### scanned_text() concern

`scanned_text()` has different traversal semantics from `walk()` —
it recurses into ref-focused nodes. With a unified tree (instead of
parallel trees), the focused values change (focus is now IR node,
not type tags). `scanned_text()` needs review to ensure it still
finds string scans correctly in the unified tree.

## Migration strategy

Incremental. Each step must leave all tests passing.

1. Add annotation slots to Context (backward compatible — empty by default)
2. Boolean: read/write annotations->{boolean} instead of returning bare values
3. Precedence: same
4. Structural: same
5. TypeInference: write to annotations->{type} instead of building separate Context tree
6. SemanticAction: read annotations->{type} directly, remove current_type_context()
7. FilterComposite: pass single Context instead of N-tuple
8. Remove set_type_context bridge
9. Clean up dead code

## Open questions

- Should `complete` be a first-class method on Context (separate from
  `extend`)? See #701 design note.
- Cache key strategy for unified annotations — how to efficiently
  hash-cons when the key includes all semiring data.
- Does the priority ordering in add need to change? (Probably not —
  same algebra, different representation.)
