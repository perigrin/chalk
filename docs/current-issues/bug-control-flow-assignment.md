# Bug: Control flow with assignment doesn't propagate context through Region/Phi

**Labels**: `bug`, `P0-blocker`, `interpreter`, `control-flow`, `context-model`

## Summary

Assignments inside `if/else` blocks don't propagate correctly through control flow merge points. The Region/Phi nodes don't properly merge contexts after branches, so variable updates inside branches are not visible after the branch.

## Test Case

```perl
my $result = 0;
if ($x > 0) { $result = 10; }
return $result;  # Returns 0, should return 10 when $x > 0
```

**Expected**: `10` (when `$x > 0`)
**Actual**: `0`

## More Complex Test Case

```perl
my $x = 5;
my $result;
if ($x > 0) { $result = 10; } else { $result = 20; }
return $result;  # Should return 10 or 20 depending on condition
```

## Root Cause Analysis

### IR Structure

For `if ($x > 0) { $result = 10; } else { $result = 20; }`, the IR should be:

```
Start → If($x > 0)
        ├─ IfTrue  → Store($result, 10) → Region
        └─ IfFalse → Store($result, 20) → Region
                                          ↓
                                        Phi($result)
                                          ↓
                                        Load($result)
                                          ↓
                                        Return
```

### Context Model Issue

With Chalk's context-as-closure model:

1. **Each branch** extends context: `extend_context($ctx, "lexical:$result", $value)`
2. **Region node** must merge incoming contexts from both branches
3. **Phi node** must select correct value from correct context based on which branch was taken
4. **Subsequent operations** must see the merged context

**Hypothesis**: Region/Phi nodes don't implement context merging:
- Region's `execute()` may not merge contexts from predecessors
- Phi's `execute()` may not select from correct context
- Context isn't threaded through control flow properly

## Files to Fix

### Primary
- `lib/Chalk/IR/Node/Region.pm` (execute method needs context merging)
- `lib/Chalk/IR/Node/Phi.pm` (execute method needs context-aware value selection)

### Related
- `lib/Chalk/IR/Node/If.pm` (verify control flow splits context correctly)
- `lib/Chalk/IR/Node/Proj.pm` (IfTrue/IfFalse projections)
- `lib/Chalk/IR/Interpreter.pm` (context threading through schedule)

## Implementation Strategy

### Region Node Context Merging

```perl
# lib/Chalk/IR/Node/Region.pm
method execute($context) {
    # Region merges control from multiple predecessors
    # For context model: need to merge contexts too

    my @predecessor_contexts = ...;  # Get contexts from each incoming edge

    # Merge strategy: Union of all bindings, with phi nodes resolving conflicts
    # For now: just pass through - Phi nodes will handle value selection

    return undef;  # Region doesn't produce a value
}
```

### Phi Node Context-Aware Selection

```perl
# lib/Chalk/IR/Node/Phi.pm
method execute($context) {
    my $region_id = $self->inputs->[0];  # Control input from Region

    # Determine which branch was taken (need control flow tracking)
    my $active_branch_index = ...;

    # Select value from corresponding phi input
    my $value_id = $self->inputs->[$active_branch_index + 1];
    my $value = $context->("node:$value_id");

    return $value;
}
```

## Test Cases to Add

```perl
# t/sea-of-nodes/interpreter-differential.t
test_against_perl('my $x = 5; my $r = 0; if ($x > 0) { $r = 10; } return $r;',
    'If with true condition, assign in branch');

test_against_perl('my $x = -5; my $r = 0; if ($x > 0) { $r = 10; } return $r;',
    'If with false condition, no assignment');

test_against_perl('my $x = 5; my $r; if ($x > 0) { $r = 10; } else { $r = 20; } return $r;',
    'If-else with true condition');

test_against_perl('my $x = -5; my $r; if ($x > 0) { $r = 10; } else { $r = 20; } return $r;',
    'If-else with false condition');
```

## Success Criteria

- [ ] Assignment inside if branch visible after branch when condition true
- [ ] Assignment inside else branch visible after branch when condition false
- [ ] Region merges contexts from all predecessors
- [ ] Phi selects correct value from correct context
- [ ] All differential tests pass

## Related Issues

- Related to: Variable reassignment bug (must be fixed first)
- Blocks: Control flow with early returns
- Blocks: Loop with variable updates

## Priority

**P0 - BLOCKER**: Control flow is fundamental to any real program.

## References

- `docs/ROADMAP_SELF_HOSTING.md` (Phase 1.2)
- `t/sea-of-nodes/interpreter-differential.t` (lines 224-240: TODO tests)
- `t/sea-of-nodes/interpreter.t` (basic Region/Phi tests exist but limited)
