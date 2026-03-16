# Epoch-Based Chart GC Design

## Problem

The Earley parser's chart never frees positions. `Program → StatementList*`
keeps origin 0 alive for the entire parse, so the safe-set GC (Aycock
Chapter 6) finds nothing safe to free. Memory grows linearly at ~1MB per
KB of input: 500 lines → 500MB, 2000 lines → 2GB, 5800 lines → OOM.

The profiling data:

| Lines | Bytes | Time | RSS | GC freed |
|-------|-------|------|-----|----------|
| 100 | 5KB | 5s | 114MB | 0 |
| 500 | 24KB | 48s | 493MB | 0 |
| 1000 | 52KB | 187s | 1.05GB | 0 |
| 2000 | 99KB | 567s | 1.99GB | 0 |

## Solution: Epoch Sweeping at Statement Boundaries

Statement completions are natural GC epochs. When a Statement completes,
everything internal to it (expressions, operators, method calls) is dead.
The semantic values have been folded into the StatementList via multiply.
Only the completed Statement's result value survives.

### Three-Layer Architecture

**Semiring layer (SemanticAction):** Signals epoch boundaries via callback.
When on_complete detects a Statement-level completion, it calls the
epoch commit callback with the sweep range [origin..end).

**Earley layer (_run_parse):** Receives the callback, queues sweep ranges,
executes sweeps after each position's agenda is fully processed.

**Chart sweep (two-phase):**
1. Null values for epoch-internal items (origin >= epoch start)
2. Compact positions where all items have null values

## Epoch Detection

Two rules cooperate:
- **Statement** completion: signals the reclaimable range [origin..end)
- **StatementList** completion: confirms accumulated value subsumes prior
  statements (belt-and-suspenders for a GC system where bugs = segfaults)

SemanticAction detects these by checking the completed rule name from the
Context's rule annotation.

## Callback API

on_complete gains an optional trailing parameter:

```perl
$semiring->on_complete($item, $alt_idx, $pos, $on_epoch_commit)
```

- `$on_epoch_commit` is `undef` when epoch GC is disabled
- SemanticAction calls `$on_epoch_commit->($origin, $pos)` on Statement
  completion
- FilterComposite passes the parameter through to each component
- Boolean, Precedence, TypeInference, Structural ignore it

## Sweep Implementation

```
_sweep_epoch($origin, $end, $chart):

  Phase 1: Null values for epoch-internal items
    for pos in [origin..end):
      for each core_id slot in chart[pos]:
        for each origin_key in chart[pos][core_id]:
          if origin_key >= epoch_origin:
            chart[pos][core_id]{origin_key}[0]{value} = undef

  Phase 2: Compact fully-dead positions
    for pos in [origin..end):
      if ALL items at pos have undef values:
        chart[pos] = []
        delete scan_cache{pos}
        gc_stats{positions_freed}++
```

## Sweep Timing

Sweeps execute after each position's agenda is fully drained, before
moving to the next position. This ensures no in-flight item references
a value being nulled. The queue pattern:

```perl
my @pending_sweeps;
my $on_epoch_commit = sub ($origin, $end) {
    push @pending_sweeps, [$origin, $end];
};

# ... after agenda processing for position $pos:
for my $sweep (@pending_sweeps) {
    $self->_sweep_epoch($sweep->[0], $sweep->[1], \@chart);
}
@pending_sweeps = ();
```

## Completer Change

One-line change: skip items with nulled values.

```perl
next if !defined($completed_value) || $semiring->is_zero($completed_value);
```

## Safety Invariants

1. **No sweep during active agenda.** Sweep runs after agenda drain.
2. **Indexes remain valid.** `waiting_for` and `completed_at` reference
   items by (core_id, origin) tuples. The item structure stays in the
   chart after value nulling. Completer finds items but skips those
   without values.
3. **Late merges on swept items are no-ops.** `add()` on undef values
   is skipped — prevents resurrecting freed values.

## Expected Impact

With ~2000 statements in 5800 lines, peak chart holds one statement's
worth of positions (~20-100 bytes) instead of all 278KB positions.

Projected memory: ~2500x reduction in live chart data. RSS should stay
under 200MB instead of 5.5GB OOM.

## Implementation Order

1. Add `$on_epoch_commit` parameter to on_complete chain
2. SemanticAction detects Statement completion, fires callback
3. Earley `_run_parse` queues and executes sweeps
4. Add `!defined` guard in Completer
5. Profiling verification: GC freed > 0, RSS stays bounded
6. XS codegen: the callback and sweep compile to native C
