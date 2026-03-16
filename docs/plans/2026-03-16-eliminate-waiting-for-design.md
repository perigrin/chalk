# Eliminate %waiting_for: Chart-Based Completion Lookup

## Problem

The `%waiting_for` index creates persistent cross-boundary references
that prevent safe-set GC from freeing chart positions. When a nonterminal
is predicted at position P, `waiting_for{rule}{P}` stores `[$core_id, $origin]`
where `$origin` can be any earlier position. These references survive
beyond safe-set boundaries, causing the Completer to reach back into
freed positions.

Aycock's DFA-based parser doesn't have this problem because prediction
doesn't create per-position waiting lists — the DFA state encodes which
items are predicted. Eliminating `%waiting_for` aligns our implementation
with Aycock's architecture and unblocks safe-set GC.

## Current Architecture

### How %waiting_for Works

When `_run_parse` encounters a nonterminal symbol:
```perl
# Line 400-401 of Earley.pm
$waiting_for{$w_rule}{$pos} //= [];
push $waiting_for{$w_rule}{$pos}->@*, [$core_id, $origin];
```

When the Completer processes a completion of rule R at position Q
with origin P:
```perl
# In _complete
my $waiters = $waiting_for{$rule_name}{$origin};
for my $entry ($waiters->@*) {
    my ($w_core_id, $w_origin) = $entry->@*;
    # Look up item at chart[$origin][$w_core_id]{$w_origin}
    # Advance it and add to chart[$pos]
}
```

### The Cross-Boundary Problem

`waiting_for{Expression}{50}` might contain `[$core_id, 3]` — an item
at position 50 whose origin is position 3. If safe-set GC frees position
3, the Completer's lookup `chart[50][$w_core_id]{3}` either finds a
freed slot (segfault) or empty data (wrong result).

## Solution: Derive Waiting Items from Chart

Instead of maintaining a separate `%waiting_for` index, the Completer
derives waiting items by scanning the chart at the completion's origin
position.

When rule R completes at position Q with origin P:
1. Scan `chart[P]` for items whose dot is before nonterminal R
2. For each such item, advance the dot and add to `chart[Q]`

### Precomputed Lookup Table

The naive scan is O(core_ids × origins) per completion. But the
CoreItemIndex already enumerates all core items. We can precompute:

```
waiting_core_ids{rule_name} = [core_id_1, core_id_2, ...]
```

Where each `core_id_N` is a core item whose dot is before nonterminal
`rule_name`. This is computed once at grammar construction time from
the CoreItemIndex.

The Completer then does:
```perl
my $waiters = $waiting_core_ids{$rule_name};
for my $w_core_id ($waiters->@*) {
    my $oh = $chart[$origin][$w_core_id];
    next unless defined $oh;
    for my $w_origin (keys $oh->%*) {
        # Advance item and add to chart[$pos]
    }
}
```

This is O(waiting_core_ids × origins_per_core_id) — typically very
small because most core IDs have 1 origin.

### What waiting_core_ids Contains

For each nonterminal R in the grammar, the set of core items where:
- The dot is immediately before R in the rule's RHS
- i.e., items of the form [B → α • R β, _]

This is derivable from the CoreItemIndex:
```perl
for my $id (0 .. $core_index->count() - 1) {
    my $info = $core_index->item_for($id);
    my $rule = $rule_table->{$info->{rule_name}};
    my $rhs = $rule->expressions()->[$info->{alt_idx}];
    my $dot = $info->{dot};
    if ($dot < scalar($rhs->@*)) {
        my $sym = $rhs->[$dot];
        if ($sym->is_reference()) {
            push $waiting_core_ids{$sym->value()}->@*, $id;
        }
    }
}
```

## What Changes

### Removed
- `field %waiting_for` — the per-position waiting index
- `$_waiting_for_min` — the minimum position tracking for GC
- All `$waiting_for{...}{...}` writes in `_run_parse`
- The `waiting_for` parameter in `_complete` and `_advance_from_completed`

### Added
- `field %_waiting_core_ids` — precomputed in ADJUST from CoreItemIndex
- Chart-based lookup in `_complete`: scan `chart[origin]` for waiting core IDs
- Chart-based lookup in `_advance_from_completed`: same pattern

### Modified
- `_run_parse`: remove `waiting_for` writes (lines 400-401)
- `_complete`: replace `waiting_for` lookup with chart scan
- `_advance_from_completed`: replace `waiting_for` lookup with chart scan
- Safe-set GC: no longer blocked by cross-boundary references
- Safe-floor GC: `$_waiting_for_min` removal simplifies the floor computation

## Safe-Set GC Unblocking

With `%waiting_for` eliminated, the Completer only accesses chart
positions that are still alive. When safe-set GC frees positions
[i+1..j-1], the Completer at position j looks up `chart[origin]` where
`origin` is the completion's origin. If that origin is in the freed
range, no items exist there — the loop finds nothing and skips. This is
correct because those items' completions have already been processed
and their results propagated to later positions.

## Performance Considerations

**Precomputation cost:** Building `%_waiting_core_ids` is O(total_core_items)
— one pass through the CoreItemIndex. Runs once in ADJUST.

**Per-completion cost:** For each completion, scan `waiting_core_ids{rule}`
(typically 2-10 entries) and for each, look up `chart[origin][core_id]`
(hash lookup). Current `waiting_for` does: look up
`waiting_for{rule}{origin}` (hash lookup) then iterate entries.

The chart-based approach may be slightly slower per completion (multiple
hash lookups vs one array iteration) but eliminates all `waiting_for`
maintenance overhead (the push on every prediction).

**Net effect:** Fewer data structures maintained during parse, enabling
safe-set GC which frees ~41% of chart positions. The memory savings
from GC should far outweigh any per-completion overhead.

## Implementation Order

1. Precompute `%_waiting_core_ids` in ADJUST from CoreItemIndex
2. Rewrite `_complete` to use chart-based waiting item lookup
3. Rewrite `_advance_from_completed` to use chart-based lookup
4. Remove `%waiting_for`, `$_waiting_for_min`, and all write sites
5. Update safe-floor GC computation (remove waiting_for_min)
6. Re-enable safe-set GC (remove `false &&` guard)
7. Test: all existing tests pass
8. Test: safe-set gc_freed > 0 for Boolean-only parse
9. Profile: RSS comparison on 100/500/1000 line inputs

## Risks

- The chart-based lookup might miss items that `waiting_for` would find.
  This can happen if an item was added to `waiting_for` but the chart
  entry was later overwritten by `add()` merging. Mitigation: the
  chart always contains the merged result, which is correct.

- `_advance_from_completed` is called during prediction to handle
  nullable nonterminals. It currently uses `completed_at` (not
  `waiting_for`). This is unaffected by the change.

- Leo optimization items use `waiting_for` to check if exactly one
  waiter exists (for right-recursive chain detection). This check
  needs to be rewritten to use the chart-based lookup.
