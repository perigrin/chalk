# Sequential Filtering Architecture for Composite Semiring

**Date:** 2026-01-10
**Status:** Approved
**Related Issue:** #562 - Multi-line `use overload` parsing failure

## Problem Statement

The current `Composite.add()` implementation uses a "leader" pattern where the first semiring (index 0) makes decisions that all other semirings must follow. This prevents proper sequential filtering and causes issues like:

- SemanticValidation correctly rejects invalid parse alternatives, but its decision is ignored
- Multi-line `use overload` statements parse with 0 mappings instead of collecting the ExpressionList
- Grammar ambiguities cannot be properly resolved by validation semirings

### Current Broken Behavior

```perl
# Lines 13-80 of Composite.pm
# First semiring (Precedence) is the "leader"
my $prec_result = $prec_self->add($prec_other);
if ($use_self && !$both_valid) {
    return $self;  # Force ALL semirings to use self
}
```

When Precedence chooses an alternative, ALL other semirings are forced to use that choice, even if they would have rejected it.

## Design Goals

1. **Equal semiring participation** - No semiring is "leader", all filter independently
2. **Short-circuit on invalid** - Return immediately when any semiring returns `add_id`
3. **Preserve reference equality** - Return original element when all semirings agree
4. **Fail on ambiguity** - Die with diagnostic when semirings disagree
5. **Progressive filtering** - Semirings ordered from least to most restrictive

## Semiring Order

The new order is **Boolean → Precedence → TypeInference → SemanticValidation**:

| Semiring | Purpose | Why This Order |
|----------|---------|----------------|
| Boolean | Basic token validity | Most fundamental - is this even a valid parse? |
| Precedence | Operator precedence rules | Structural validity - do operator precedences make sense? |
| TypeInference | Type unification | Type-level validity - do types unify correctly? |
| SemanticValidation | Grammar-specific rules | Most restrictive - context-dependent semantic rules |

This is progressively more restrictive, allowing earlier semirings to prune invalid alternatives before expensive later checks.

## Implementation Design

### Core Algorithm

```perl
method add( $other, $swap = undef ) {
    # SEQUENTIAL FILTERING: Each semiring filters independently
    # Short-circuit immediately if any semiring returns add_id

    my @self_elements = $elements->@*;
    my @other_elements = $other->elements->@*;
    my @result_elements;

    # Iterate through each semiring in order
    for my $i (0..$#$elements) {
        my $self_elem = $self_elements[$i];
        my $other_elem = $other_elements[$i];

        # Let this semiring filter the alternatives
        my $result = $self_elem->add($other_elem);

        # Short-circuit: if this semiring says "invalid", we're done
        if ($parent_semiring && defined($parent_semiring->child_add_ids->[$i])) {
            if ($result->equals($parent_semiring->child_add_ids->[$i])) {
                return $parent_semiring->add_id;  # Invalid - abort immediately
            }
        }

        push @result_elements, $result;
    }

    # All semirings processed successfully - determine consensus
    my $first_result = $result_elements[0];
    my $all_agree = all { refaddr($_) == refaddr($first_result) } @result_elements;

    if ($all_agree) {
        # All semirings returned the same reference
        if (refaddr($first_result) == refaddr($self_elements[0])) {
            return $self;  # All chose their self elements
        } elsif (refaddr($first_result) == refaddr($other_elements[0])) {
            return $other;  # All chose their other elements
        }
    }

    # No consensus - build diagnostic and fail
    my @diagnostics;
    for my $i (0..$#result_elements) {
        my $chose = refaddr($result_elements[$i]) == refaddr($self_elements[$i]) ? 'self' :
                   refaddr($result_elements[$i]) == refaddr($other_elements[$i]) ? 'other' : 'new';
        my $semiring_name = ref($semirings->[$i]) =~ s/^Chalk::Semiring:://r;
        push @diagnostics, "$semiring_name chose $chose";
    }

    die "Ambiguous parse in Composite.add():\n  " . join("\n  ", @diagnostics) . "\n";
}
```

### Key Behaviors

1. **Short-circuit on invalid**: As soon as any semiring returns `add_id`, we immediately return the composite's `add_id` without processing remaining semirings.

2. **Consensus detection**: Use `builtin::all` to check if all semirings returned the same reference. If so, map back to the original `$self` or `$other` CompositeElement.

3. **Ambiguity handling**: If semirings disagree (mixed results), die with a diagnostic showing which semiring chose what. This is always an error - ambiguity indicates incomplete grammar/validation rules.

4. **Reference equality**: When all semirings agree, return the original `$self` or `$other` to preserve reference equality for downstream optimizations.

## Expected Behavior Changes

### UseStatement Example

Given `use overload '""' => 'value', 'eq' => '_string_eq';`:

**Old behavior (leader pattern):**
- Parse 1: `use overload ExpressionList` with 2 mappings
- Parse 2: `use overload` (bare) with 0 mappings
- Precedence chooses Parse 2 (or Parse 1 based on precedence rules)
- ALL semirings forced to use that choice
- SemanticValidation's rejection of bare form is ignored
- Result: 0 mappings ❌

**New behavior (sequential filtering):**
- Parse 1: `use overload ExpressionList` with 2 mappings
  - Boolean: valid
  - Precedence: valid
  - TypeInference: valid
  - SemanticValidation: **valid** (5 RHS elements)

- Parse 2: `use overload` (bare) with 0 mappings
  - Boolean: valid
  - Precedence: valid
  - TypeInference: valid
  - SemanticValidation: **invalid** (rejects 3 RHS elements)
  - **Returns add_id, pruned from consideration**

- Composite.add(Parse1, Parse2):
  - SemanticValidation filters out Parse2
  - Only Parse1 remains
  - Result: 2 mappings ✅

## Test Impact

### Tests that will break (require updates):

1. **t/semiring/product-coordination.t:199**
   - Currently: `ok $result == $parse1, 'Composite.add() chooses precedence-valid parse'`
   - Assumes Precedence is "leader"
   - Fix: Update to test that sequential filtering works correctly

2. **t/semiring/chalk-syntax.t:33-39**
   - Comment assumes Precedence first due to "leader" pattern
   - Fix: Update comment to explain progressive filtering order

### Tests that should still pass:

- `t/semiring/composite.t` - Short-circuit logic unchanged
- `t/semiring/ast.t` - AST generation unchanged
- Most other semiring tests - behavior is more correct, not less

### Tests that will now pass:

- `t/grammar/class-with-overload.t` - Multi-line `use overload` will work correctly

## Migration Notes

1. **Semiring order change**: ChalkSyntax will need to reorder semirings to Boolean → Precedence → TypeInference → SemanticValidation

2. **Error messages**: Ambiguity errors will now be caught and reported. This may expose latent grammar ambiguities that were previously masked by the leader pattern.

3. **Performance**: Short-circuiting may improve performance by avoiding expensive later semiring checks on invalid parses.

## Future Improvements

1. **Error messages**: The ambiguity error message should eventually include source location and parsed text for better end-user experience.

2. **Diagnostic mode**: Consider adding optional detailed diagnostics about why each semiring chose what it did (for grammar debugging).

3. **Optimization**: Consider caching `child_add_ids` refaddr values to avoid repeated `equals()` calls.

## References

- Issue #562: Multi-line `use overload` parsing failure
- lib/Chalk/Semiring/Composite.pm (current implementation)
- lib/Chalk/Semiring/ChalkSyntax.pm (semiring order)
- t/grammar/class-with-overload.t (failing test)
