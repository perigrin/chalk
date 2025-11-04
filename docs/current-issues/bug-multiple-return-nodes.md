# Bug: Parser creates multiple Return nodes for if/else with returns

**Labels**: `bug`, `P0-blocker`, `parser`, `IR-generation`, `control-flow`

## Summary

When parsing `if/else` statements with `return` in both branches, the parser/semantic actions create multiple Return nodes that aren't properly linked to control flow via `__CONTROL_PLACEHOLDER__`. This causes the interpreter to fail with "Malformed IR graph" error.

## Test Case

```perl
if (1) { return 42; } else { return -42; }
```

**Error**:
```
Malformed IR graph: found multiple Return nodes but none have __CONTROL_PLACEHOLDER__ control input.
This indicates incorrect IR construction - each Return must be properly linked to control flow.
```

## Current Behavior

Parser creates multiple Return nodes during intermediate parse states:
1. One Return for if-branch: `return 42;`
2. One Return for else-branch: `return -42;`
3. Both lack proper `__CONTROL_PLACEHOLDER__` marking

The interpreter's `find_return()` method (Interpreter.pm:61-115) detects this as malformed IR and dies.

## Root Cause Analysis

**Hypothesis 1**: Grammar semantic actions create Return nodes for each branch independently without proper control flow linking.

**Hypothesis 2**: The composite semiring creates multiple parse interpretations, each with a Return node, and graph pruning doesn't eliminate the extras.

**Hypothesis 3**: Return node creation in `Builder->build_return_node()` doesn't properly set control input when inside conditional branches.

## IR Structure Expected

For `if ($cond) { return 42; } else { return -42; }`:

```
Start → If($cond)
        ├─ IfTrue  → Constant(42)  → Return(42)  [control: IfTrue]
        └─ IfFalse → Constant(-42) → Return(-42) [control: IfFalse]
```

**Key**: Only ONE Return should be selected as "winning" based on which branch executed, OR both Returns must be properly marked with control flow.

## Files to Investigate

### IR Builder
- `lib/Chalk/IR/Builder.pm` (lines 111-135: `build_return_node`)
  - Check control flow parameter handling
  - Verify `__CONTROL_PLACEHOLDER__` is set correctly

### Semantic Actions
- Grammar actions for `if/else` statements
- Check how Return nodes are created in branches
- Verify control flow is threaded correctly

### Parser/Semiring
- `lib/Chalk/Semiring/Semantic.pm` - semantic action evaluation
- Check if multiple parse interpretations create duplicate Returns
- Verify graph pruning removes unreachable nodes

### Interpreter
- `lib/Chalk/IR/Interpreter.pm` (lines 61-115: `find_return`)
  - Currently dies on multiple Returns
  - May need to handle multiple Returns if that's valid IR

## Debugging Approach

1. **Log Return node creation**: Add debug output to `build_return_node()` showing:
   - When Return nodes are created
   - What control input they receive
   - Stack trace of where they're created from

2. **Check graph after parsing**: Before pruning, dump all nodes and check:
   - How many Return nodes exist
   - What their control inputs are
   - Which are reachable from Start

3. **Verify pruning**: After `$graph->prune_to_reachable($winning_node_id)`:
   - Should only keep one Return (the winning one)
   - Check if pruning is even running

4. **Check semantic actions**: For `ReturnStatement` grammar rule:
   - Does it properly thread control flow?
   - Does it mark Return with `__CONTROL_PLACEHOLDER__`?

## Potential Fixes

### Option 1: Fix Return Node Creation
Ensure `build_return_node()` always receives proper control input when inside branches:

```perl
method build_return_node($value_node, $control = undef) {
    # Use provided control, current_control, or placeholder
    my $ctrl = $control // $current_control // '__CONTROL_PLACEHOLDER__';

    # For branches, ensure control is the branch projection (IfTrue/IfFalse)
    # not just the If node
    ...
}
```

### Option 2: Fix Graph Pruning
Ensure parser prunes to single winning Return:

```perl
# In differential test execution (line 50-59)
if ($parse_result->can('context')) {
    my $ctx = $parse_result->context;
    if ($ctx->can('focus')) {
        my $winning_node = $ctx->focus;
        $graph->prune_to_reachable($winning_node->id);  # Should keep only one Return
    }
}
```

### Option 3: Make Multiple Returns Valid
If multiple Returns are semantically valid (e.g., early returns), update interpreter to handle them:

```perl
method find_return() {
    # If multiple Returns, select based on control flow that executed
    # This requires tracking which branch was taken
}
```

## Test Cases to Add

```perl
# After fix, these should work:
test_against_perl('if (1) { return 42; } else { return -42; }',
    'If-else with returns, true branch');

test_against_perl('if (0) { return 42; } else { return -42; }',
    'If-else with returns, false branch');

test_against_perl('my $x = 5; if ($x > 0) { return 42; } return -42;',
    'Early return in if, fallthrough to return');
```

## Success Criteria

- [ ] Parser/semantic actions create properly linked Return nodes
- [ ] Graph has at most one Return node after pruning
- [ ] OR multiple Return nodes are valid and interpreter handles them
- [ ] Validator passes (no "malformed IR" error)
- [ ] All test cases pass with correct return values

## Workarounds (Current)

Users can work around this by using assignment instead of early returns:

```perl
# Instead of:
if ($x > 0) { return 42; } else { return -42; }

# Use:
my $result;
if ($x > 0) { $result = 42; } else { $result = -42; }
return $result;
```

But this workaround is blocked by the control flow assignment bug!

## Priority

**P0 - BLOCKER**: Early returns are common pattern, needed for real programs.

## References

- `docs/ROADMAP_SELF_HOSTING.md` (Phase 1.3)
- `docs/INTERPRETER_SEMANTICS.md` (lines 132-154: control flow with multiple returns)
- `t/sea-of-nodes/interpreter-differential.t` (lines 231-239: SKIP'd tests)
- `lib/Chalk/IR/Interpreter.pm` (lines 108-114: error message for multiple Returns)
