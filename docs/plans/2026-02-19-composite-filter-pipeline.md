# Composite Semiring: Progressive Filter Pipeline

**SUPERSEDED** by `2026-02-19-semiring-architecture-correction.md`. The
"die at add() time" approach below was replaced by the survivor-list design
with hash-consed identity comparison to handle cases where disambiguation
requires context not yet available at first-meet time.

## History

On January 10, 2026 (conversation 7fefc48f), we designed a sequential filtering
architecture for `Composite.add()`. The key decisions:

1. Semirings are a **progressive filter pipeline**: Boolean -> Precedence ->
   TypeInference -> Structural -> SemanticAction
2. Each semiring filters independently — no "leader" pattern
3. Short-circuit on first rejection — if any semiring rejects, we're done
4. Return the surviving tuple — no need to process remaining semirings
5. Die with diagnostic on ambiguity (no semiring rejected either side)

## The `selects_alternative` Problem

`selects_alternative` was created to solve a coordination problem in the old
"leader" pattern, where Precedence at index 0 made decisions that all other
semirings were forced to follow.

In a progressive filter pipeline, `selects_alternative` is unnecessary:

- If a semiring's `add()` picks one side (rejecting the other), the Composite
  returns the surviving tuple immediately. No further semirings see the comparison.
- There is no coordination problem because there is no independent merging —
  the first filter to reject ends the discussion.

**`selects_alternative` should be eliminated.** Each semiring only needs `add()`.

## Correct Composite.add() Design

```perl
method add($left, $right) {
    for my ($i, $semiring) (indexed $semirings->@*) {
        my $li = $left->[$i];
        my $ri = $right->[$i];

        # If either side is zero, survivor wins
        return $left  if $semiring->is_zero($ri);
        return $right if $semiring->is_zero($li);

        # Let this semiring compare
        my $result = $semiring->add($li, $ri);

        # If add picked a side (rejected the other), return that tuple
        return $left  if refaddr($result) == refaddr($li);
        return $right if refaddr($result) == refaddr($ri);

        # Genuinely merged — continue to next semiring
    }
    # All semirings passed without rejecting either side — true ambiguity
    die "Ambiguity survived all semirings: no filter rejected either alternative";
}
```

Key properties:
- First filter to reject a side ends the discussion
- Returns the whole tuple, not just the component
- Later semirings never see the rejected alternative
- No `selects_alternative` needed
- **Ambiguity is fatal**: if no semiring rejects either side, die with diagnostic
  (the pipeline's job is to produce ONE unambiguous parse)

## What This Means for Individual Semirings

### TypeInference
- `selects_alternative` removed entirely
- `add()` simplifies: just pick left when both valid, or use tree-walk for
  `ambiguous_unary` check (which may move to Precedence anyway)
- `ambiguous_unary` may not even need to be in `add()` if `on_complete` already
  rejects it (returns undef)

### Precedence
- `selects_alternative` removed entirely
- `add()` already picks a side (returns `$left` or `$right`) — this naturally
  works with the Composite's refaddr check

### Structural
- `selects_alternative` removed entirely
- `add()` picks a side based on structural tag comparison

## Relationship to TypeInference Redesign

This is a prerequisite for the extend-based TypeInference redesign
(see `2026-02-19-typeinference-extend-redesign.md`). The flat tag merge
(`_tags()`) in `add()` and `selects_alternative()` must be eliminated as part
of that work. With the progressive filter pipeline, `add()` becomes trivial
and doesn't need `_tags()` at all.
