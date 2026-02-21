# Migration: _complete_ctx/_tags() to Comonad extend()

**Supersedes**: Phase 2c of `2026-02-20-typeinference-redesign.md` (which deferred
`_tags()` removal after discovering focused nodes shadow children).

## Problem

TypeInference's `on_complete` uses two hand-rolled helpers that work against the
comonad instead of with it:

1. **`_complete_ctx`** creates a new focused Context with a tags hash as focus
   and the original children underneath. This shadows the children — parent
   rules can't see child focuses without flat-merging.

2. **`_tags()`** compensates for shadowing by recursively merging all leaf
   focuses into a flat hash. Every intermediate rule must propagate every tag
   through the catch-all so `_tags()` finds them at the current level.

The comonad already provides `extend()`: apply a function to the whole tree,
get a new Context with the result as focus and children preserved. Parent rules
access children via tree-walking. No shadowing, no flat merge, no propagation.

## Design

### New Helper: `_extend_ctx`

Replaces `_complete_ctx`. Calls `extend()`, then hash-conses the result:

```perl
my sub _extend_ctx($value, $f, $rule_name) {
    my $extended = $value->extend($f);
    my $focus = $extended->extract();
    my $focus_key = _tag_key($focus);
    my $children_key = join(":", map { refaddr($_) } $extended->children()->@*);
    my $key = "ext:$rule_name:" . $extended->position() . ":$focus_key:$children_key";
    return ($_ctx_cache{$key} //= $extended);
}
```

Hash-consing after extend preserves identity-based disambiguation in
FilterComposite's `_filter_compare` and TypeInference's `add()`.

### Actions Methods: Context-Only Signature

Actions methods change from `($ctx, $tags, $alt_idx)` to `($ctx)`. They use
tree-walking helpers to access child information:

- `$_get_rightmost_type->($ctx)` — child's type (wrappers, boundaries)
- `$_get_op_text->($ctx)` — operator text (BinaryExpr, UnaryExpr) — **new**
- `$_get_call_symbol->($ctx)` — function name (CallExpression) — exists
- `$_get_list_arity->($ctx)` — list arity from ExpressionList child — **new**
- `$_get_item_types->($ctx)` — per-position types from ExpressionList — **new**
- `$_get_prev_item_types->($ctx)` — moved from TypeInference to Actions

Alt-dependent rules capture `$alt_idx` via closure in the `extend()` call.

### Catch-All: Passthrough

Intermediate rules without Actions methods return `$value` unchanged:

```perl
# No action registered — transparent passthrough
return $value;
```

No propagation needed. Tree-walkers in Actions methods find tags in child
focuses regardless of how many intermediate rules sit between producer and
consumer.

### `$builtin_lookup` for CallExpression

CallExpression moves fully into Actions. Actions uses
`TypeLibrary::get_builtin` directly (already imported). The `$builtin_lookup`
callback stays in TypeInference for scan-time `call_symbol` tagging only
(`get_validated_builtin` in `on_scan`).

### Dispatch Pattern

TypeInference `on_complete` becomes:

```perl
method on_complete($item, $alt_idx, $pos) {
    my $value = $item->{value};
    return undef if !defined $value;
    my $rule_name = $item->{rule}->name();

    my $method = $actions->can($rule_name);
    if ($method) {
        my $result = _extend_ctx(
            $value,
            sub($ctx) { $actions->$method($ctx) },
            $rule_name,
        );
        return undef unless defined $result && defined $result->extract();
        return $result;
    }

    # No action: transparent passthrough
    return $value;
}
```

No `_tags()` call. No catch-all propagation. No `_complete_ctx`.

## Migration Steps

Each step produces a green commit. No step leaves dead code behind.

### Step 1: Add `_extend_ctx` helper
- Add alongside `_complete_ctx` (both coexist temporarily)
- No behavior change
- Test: existing tests pass

### Step 2: Migrate fixed-type rules
- PostfixIncDec, AnonymousSub, QwLiteral, ArrayConstructor, HashConstructor
- These return constant focuses — simplest to migrate
- Actions methods: remove `$tags`/`$alt_idx` params, receive `($ctx)` only
- TypeInference dispatch: `_extend_ctx($value, sub { $actions->$method(@_) }, $rule_name)`

### Step 3: Migrate wrapper rules
- Atom, Expression, PostfixExpression
- Actions: `$tags->{type}` → `$_get_rightmost_type->($ctx)`

### Step 4: Migrate operator rules
- BinaryExpression, UnaryExpression
- Add `$_get_op_text` walker to Actions
- Actions: `$tags->{op_text}` → `$_get_op_text->($ctx)`

### Step 5: Migrate boundary rules
- ParenExpr, Block, Signature, Attribute
- Same as wrappers: `$_get_rightmost_type->($ctx)` for type, omit op_text/call_symbol

### Step 6: Migrate alt-dependent rules
- PostfixDeref, Subscript, TernaryExpression, AssignmentExpression, MethodCall
- `$alt_idx` captured by closure: `sub($ctx) { $actions->$method($ctx, $alt_idx) }`

### Step 7: Migrate ExpressionList into Actions
- Move inline logic from TypeInference
- Add `$_get_list_arity`, `$_get_item_types` walkers
- Move `$_get_prev_item_types` from TypeInference to Actions

### Step 8: Migrate CallExpression into Actions
- Move inline logic from TypeInference
- Actions uses `TypeLibrary::get_builtin` directly
- Reuse `$_get_item_types` and `$_get_list_arity` from Step 7

### Step 9: Make catch-all passthrough
- Replace `_complete_ctx({...propagation...})` with `return $value`
- All tag consumers now use tree-walkers — propagation unnecessary

### Step 10: Remove legacy infrastructure
- Delete `_complete_ctx`, `_tags()`, `_tag_key` (if only used by `_complete_ctx`)
- Remove `my $tags = _tags($value)` from on_complete
- Grep for stale references, fix or remove
- `_tag_key` stays if `_extend_ctx` uses it for hash-consing

## What Gets Removed

- `_complete_ctx` function
- `_tags()` function
- Catch-all 5-tag propagation block
- `$tags` variable in `on_complete`
- ExpressionList/CallExpression inline blocks in TypeInference

## What Stays

- `_extend_ctx` (new, replaces `_complete_ctx`)
- `_tag_key` (used by `_extend_ctx` for hash-consing)
- `%_ctx_cache` (hash-cons cache, shared by `_extend_ctx` and `multiply`)
- `$_get_rightmost_type`, `$_get_call_symbol`, `$_get_prev_item_types` in TypeInference
  (may be moved to Actions as they migrate)
- `on_scan` (unchanged — scan-time tagging stays in TypeInference)
- `$builtin_lookup` field (used by `on_scan` for `call_symbol` tagging)

## Risks

- **Medium**: Tree-walkers are slower than direct tag access. Mitigated by
  shallow trees (most rules have 1-3 children) and hash-consing reducing
  the number of distinct trees.
- **Low**: ExpressionList/CallExpression migration (Steps 7-8) is the most
  complex. Mitigated by extensive existing tests (319 unit + 389 integration).
- **Low**: Catch-all passthrough (Step 9) changes identity semantics for
  intermediate rules — they now share refaddr with their child's value.
  Mitigated by TypeInference `add()` already handling identity collapse.

## Verification

After each step:
```bash
SHELL=/bin/bash /bin/bash -c 'cd /home/perigrin/dev/chalk/.worktrees/bootstrap && \
  for t in semiring-type-inference semiring-type-inference-actions \
    semiring-composite semiring-should-scan earley-zero-propagation \
    concise-actions concise-validation concise-per-file \
    perl-actions-fixup perl-actions-tier-c; do \
    result=$($HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/bootstrap/lib \
      t/bootstrap/$t.t 2>&1 | tail -1); echo "$t: $result"; done'
```

After Step 10: grep for `_complete_ctx`, `_tags(`, and `keyword_as_identifier`
to confirm no stale references remain.
