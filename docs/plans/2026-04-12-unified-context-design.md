# Unified Context Design (#702)

**Date**: 2026-04-12
**Status**: Draft (revised after pushback and concern review)
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

The semiring axioms guarantee correct results regardless of evaluation
order. A child rule's value accumulates through `add` as alternatives
are discovered and through `multiply` as sequential items combine.
There is no special "completion" step — `add` and `multiply` are
sufficient. This is why `on_complete` can be eliminated.

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
other's named annotation slots. Formal algebraic treatment of this
construction (e.g., characterizing the annotation reads as
endomorphisms on a semidirect product) is left as an exercise.

## Design

### Semiring interface

The semiring interface reduces to five operations, aligning with
Goodman's formalism:

```
multiply($left, $right)   → Context    # sequential combination
add($left, $right)        → Context    # alternative combination
is_zero($value)           → bool       # annihilator test
one()                     → Context    # multiplicative identity
zero()                    → Context    # additive identity / annihilator
```

All non-standard callbacks are eliminated:

| Removed | Replacement |
|---------|-------------|
| `on_complete` | Work moves to `multiply` (incremental reification) |
| `on_scan` | Becomes `multiply($value, $scan_context)` |
| `should_scan` | Removed; invalid scans produce zero through `multiply` |
| `on_merge` | Eliminated; was a side-table coherence bug |
| `on_skip_optional` | Absent optionals = `multiply($value, one())` |
| `on_epoch_commit` | Deferred; not a semiring concern (parser-level GC) |

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
      cfg        => { control => $node, scope => $scope },
  }
  token       => $token_name       (what symbol this fills in parent)
  rule        => $rule_name
  position    => $pos
  is_zero     => true/false        (single flag, any semiring can set)
```

Notes:
- Boolean does not need an annotation slot. It operates entirely
  through `is_zero`.
- `cfg` (control-flow graph state) moves from SemanticAction's
  `%_cfg_state` refaddr-keyed side-table to an annotation slot.
  Each Context is self-contained — no external state to go stale.

### multiply — incremental reification

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
it in, because that's when the full context is available. This is
consistent with Goodman: the semiring axioms guarantee correct
results regardless of evaluation order.

### add — disambiguation

`add` combines two alternative Contexts for the same span and rule.
FilterComposite's add is the product of each component's add:

```
product map { $_->add($left, $right) } @components
```

Each component's `add` reads its annotation slot from both
alternatives and returns its result (like Viterbi picks the higher
probability). The product of all results determines the outcome:

- Any component returns zero → product is zero → alternative eliminated
- All components return non-zero → alternative survives

Each component disambiguates independently on its own concern.
Validity is the product of all components.

As an optimization, components can be evaluated in order from most
likely to return zero (Boolean, Precedence, TI, Structural, SA).
If any component returns zero, the product is zero — remaining
components can be skipped. This is short-circuit evaluation of the
product, not a semantic ordering.

If no component can disambiguate (both alternatives are equivalent
from every component's perspective), this is unresolved ambiguity.
The Context can pack both alternatives and flag `is_ambiguous`.
Higher rules get a chance to resolve it through subsequent
multiplies. Only if ambiguity reaches `Program` does the parser
throw an exception.

### is_zero — single flag

Any semiring can kill a derivation by returning a Context with
`is_zero` set. One field, one check. Replaces the current pattern of
iterating through N-tuple slots checking each semiring's zero.

### FilterComposite changes

FilterComposite passes one Context to each semiring. For each
operation (multiply, add), all semirings receive the same Context,
each returns a Context with its annotation slot updated, and
FilterComposite merges the annotation slots into one result.

Each semiring's operation is pure: `(Context, Context) -> Context`.
The operations are idempotent per-slot — each semiring writes only
its own slot, so merging is conflict-free.

### Eliminated mechanisms and why

**on_complete**: Not part of Goodman's formalism. Was a pragmatic
extension to batch work at rule boundaries. With incremental
reification through `multiply`, this work happens naturally as
values are combined. SemanticAction's rule-name dispatch moves to
multiply, keyed by the token name on the Context.

**on_merge**: Existed to transfer `cfg_state` from a losing
alternative to the winner during `add`. This was necessary because
`cfg_state` was a refaddr-keyed side-table that could get out of
sync when `add` picked one Context over another. With cfg as an
annotation slot, each Context carries its own cfg state — there's
nothing to transfer. The stale-value problem was a side-table
coherence bug, not a semantic issue.

**on_skip_optional**: Created placeholder Contexts for absent
optional symbols (`X?`). The Goodman-aligned approach: an absent
optional is the multiplicative identity. `multiply($value, one())`
produces the right result. SA handles positional placeholders
internally in its multiply when it encounters `one`.

**should_scan**: Pre-scan filter letting semirings veto a scan
before it happens. Removed for theoretical purity. Invalid scans
produce zero through the normal multiply path. Can be restored as
a multiply fast-path optimization later if needed.

**on_epoch_commit**: GC signal for chart memory management. Entirely
orthogonal to semiring algebra. Deferred to a post-refactor
optimization pass. The Earley parser can detect StatementItem
boundaries directly without semiring involvement.

### What goes away

- `on_complete`, `on_scan`, `on_merge`, `on_skip_optional`,
  `should_scan` callbacks on all semirings
- `on_epoch_commit` threading through semiring callbacks
- `set_type_context()` / `current_type_context()` bridge
- `_filter_compare` in FilterComposite
- `%_cfg_state` refaddr-keyed side-table in SemanticAction
- `_pending_cfg_update` / `update_cfg()` / `inherited_cfg_state()`
- `$_current_instance` / `current_instance()` class accessors
- Parallel Context trees (TI and SA no longer build independent trees)
- N-tuple bookkeeping in FilterComposite
- Per-semiring hash-cons caches (one unified cache)

### What stays the same

- The semiring algebra (product semiring: validity is the product
  of all components)
- FilterComposite as orchestrator
- Context comonad operations (extract, extend, walk)
- The Earley parser core (predict, scan, complete steps)
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

1. Add `token` field, `is_zero` flag, and `cfg` annotation to Context
2. Add annotation slots to Context (backward compatible, empty default)
3. Move cfg_state from side-table to `annotations->{cfg}`
4. Move Boolean to is_zero-only (no annotation slot)
5. Move Precedence to read/write `annotations->{precedence}`
6. Move Structural to read/write `annotations->{structural}`
7. Move TypeInference to write `annotations->{type}`
8. Move SemanticAction to read `annotations->{type}` directly
9. FilterComposite: pass single Context instead of N-tuple
10. Remove set_type_context bridge, _filter_compare, on_merge
11. Migrate on_complete logic into multiply (token-name dispatch)
12. Remove on_complete, on_scan, should_scan from semiring interface
13. Remove on_skip_optional (use multiply with one)
14. Remove on_epoch_commit (defer to post-refactor optimization)
15. Clean up dead code, update tests

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

## Subsumes

- **#700 (Leo optimization)**: Without on_complete, Leo's
  "skip intermediate completions" becomes the default behavior.
  Reification is always deferred to multiply.
- **#702 original scope**: Unified annotation slots replace the
  N-tuple, eliminating the TI/SA bridge.

## References

- Goodman, Joshua. "Semiring Parsing." *Computational Linguistics*
  25(4):573-606, 1999. The semiring parsing framework.
- Eisner, Jason. "Expectation Semirings." *ESSLLI Workshop on
  Finite-State Methods in NLP*, 2001. Cross-component dependency
  via R-module structure.
- Wirsching, Huber, Kolbl. "The Confidence-Probability Semiring."
  Technical Report 2010-04, Universitat Augsburg, 2010. Semidirect
  product of semirings with cross-component action.
