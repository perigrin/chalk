# Safe-Set Chart GC Design (Aycock Chapter 6)

## Problem

The epoch-based GC fires at statement boundaries via SemanticAction
callback, achieving gc_freed=435 for 100 lines (40% RSS reduction). But
it only works with the full 5-ary semiring — Boolean-only parses get
zero GC because there's no SemanticAction to detect statement boundaries.

More fundamentally, the epoch GC is grammar-coupled (knows about
StatementItem) and coarse (fires per statement, not per expression).

## Solution: Aycock Safe-Set Detection

Aycock's dissertation (Chapter 6) defines "safe Earley sets" — positions
where the parse is locally unambiguous. At each safe set, all interior
positions (between the previous safe set and this one) can be freed.

For Perl grammars, Aycock measured:
- 31% of sets with final items were safe
- Mean window size: 7.5 characters (safe sets every ~8 chars)
- Mean set retention: 59% (41% of sets freed)
- Mean item retention: 70%

This is grammar-agnostic — works for Boolean-only, the BNF pipeline,
any semiring. No callback needed.

## Safe Set Properties

An Earley set S_i is **safe** if:

**Property 1:** S_i contains at least one final item (completed item where
dot is at end of rule).

**Property 2:** For every final item [A → α•, p] in S_i, no other item
[B → αX_n • β, q] exists in S_i where X_n is the last symbol of α.
In other words: each completed rule's last symbol has no competing
items still waiting for that symbol. No ambiguity about what was just
recognized.

**Property 3:** No final item [A → •, p] exists (no empty/nullable rule
completions). These indicate the empty string was just "recognized,"
which is inherently ambiguous with surrounding context.

**Property 4:** A total ordering exists on the final items via derivation.
Given final items I1 = [A → α•, p] and I2 = [B → X1...Xn•, q], I1 < I2
iff A derives to a prefix containing Xn. This precludes cyclic grammars
(A →* A). Our grammar is not cyclic, so this property holds trivially.

## Algorithm

After each position's agenda is fully processed:

```
if is_safe(S_i):
    free_window(last_safe + 1, i - 1)
    last_safe = i
```

Where `is_safe(S_i)` checks Properties 1-3 (Property 4 holds by
construction for non-cyclic grammars).

## is_safe Implementation

```perl
method _is_safe_set($chart, $pos) {
    my @final_items;
    my %final_last_symbols;  # last symbol of each final item's RHS

    for my $oh ($chart->[$pos]->@*) {
        next unless defined $oh;
        for my $entry (values $oh->%*) {
            my ($item, $alt_idx) = $entry->@*;
            if ($self->_is_complete($item, $alt_idx)) {
                # Property 3: reject nullable completions (dot=0 means empty rule)
                return false if $item->{dot} == 0;

                push @final_items, $item;
                # Track the last symbol before the dot
                my $rhs = $item->{rule}->expressions()->[$alt_idx];
                if ($rhs->@*) {
                    my $last_sym = $rhs->[-1];
                    $final_last_symbols{$last_sym->value()} = 1;
                }
            }
        }
    }

    # Property 1: must have at least one final item
    return false unless @final_items;

    # Property 2: no non-final item is waiting for a final item's last symbol
    for my $oh ($chart->[$pos]->@*) {
        next unless defined $oh;
        for my $entry (values $oh->%*) {
            my ($item, $alt_idx) = $entry->@*;
            next if $self->_is_complete($item, $alt_idx);
            my $sym = $self->_symbol_after_dot($item, $alt_idx);
            if (exists $final_last_symbols{$sym->value()}) {
                return false;  # Ambiguity: competing item for same symbol
            }
        }
    }

    return true;
}
```

## Window Freeing

When position j is safe and the previous safe set was at position i:
- Free all chart data at positions i+1 through j-1
- Update oldest_live_pos
- Increment gc_stats{positions_freed}

Position i (the previous safe set) stays alive — it has the completed
items that started the window. Position j (current safe set) stays alive
— it's the new trailing edge.

```perl
method _free_safe_window($chart, $from, $to) {
    for my $p ($from .. $to) {
        if ($chart->[$p]->@*) {
            $chart->[$p] = [];
            delete $_scan_cache{$p};
            $_gc_stats{positions_freed}++;
        }
    }
}
```

## Integration with Existing GC

The safe-set GC replaces or supplements the existing safe-floor GC.
The check runs after each position's agenda drains and after the
existing GC section:

```perl
# After existing GC block:
if ($self->_is_safe_set(\@chart, $pos)) {
    if ($last_safe_pos >= 0 && $pos > $last_safe_pos + 1) {
        $self->_free_safe_window(\@chart, $last_safe_pos + 1, $pos - 1);
    }
    $last_safe_pos = $pos;
}
```

The epoch GC (on_epoch_commit) can coexist — it handles value nulling
for the semiring layer, while safe-set handles structural freeing.

## Relationship to Epoch GC

| Aspect | Epoch GC | Safe-Set GC |
|--------|----------|-------------|
| Trigger | SemanticAction callback | Chart structure |
| Granularity | Statement boundaries | ~every 8 chars |
| Semiring needed | Full 5-ary | None (grammar-agnostic) |
| What's freed | Values (null + compact) | Entire positions |
| Positions freed | Interior of statement | Interior of safe window |
| Works for Boolean | No | Yes |

They're complementary: safe-set frees chart structure, epoch frees
semantic values at positions that safe-set can't reach (because the
position has both safe and unsafe items).

## Expected Impact

Based on Aycock's Perl measurements:
- ~41% of sets freed (mean set retention 59%)
- Mean window size 7.5 chars → frequent freeing
- For XS.pm (278KB): would retain ~164KB worth of chart positions
  instead of all 278KB
- Combined with per-position memory (~1MB/KB currently), RSS reduction
  from ~5.5GB to ~3.3GB — may be enough to avoid OOM

The 41% reduction is structural. Combined with epoch GC's value nulling
for the remaining 59% retained positions, effective memory savings
could be significantly higher.

## Implementation Order

1. Add `$last_safe_pos` tracking variable in `_run_parse`
2. Implement `_is_safe_set` method (Properties 1-3)
3. Implement `_free_safe_window` method
4. Wire into main parse loop after existing GC section
5. Test: gc_freed > 0 for Boolean-only parse
6. Profile: compare RSS before/after on 100/500/1000 line inputs
7. Verify: parse results identical with and without safe-set GC

## Cost Analysis

`_is_safe_set` runs at every position. It iterates all items at that
position twice (once for final items, once for competing items). With
~200 core IDs per position and sparse origin maps, this is O(items_at_pos)
per position — typically 10-50 items. Negligible compared to the
Completer's O(items²) work.

## References

- Aycock, J.D. "Practical Earley Parsing" PhD Dissertation, 2001.
  Chapter 6: "Early Action in an Earley Parser", pp. 92-103.
- Aho, A.V. and Ullman, J.D. Theorem 2 (referenced by Aycock for
  space savings justification).
