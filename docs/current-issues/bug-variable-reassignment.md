# Bug: Variable reassignment in context model doesn't update value

**Labels**: `bug`, `P0-blocker`, `interpreter`, `context-model`

## Summary

Variable reassignment does not update the variable value when using the context-as-closure memory model. The second assignment creates proper context shadowing, but lookups return the old value instead of the new one.

## Test Case

```perl
my $x = 5;
$x = 10;
return $x;  # Returns 5, should return 10
```

**Expected**: `10`
**Actual**: `5`

## Root Cause Analysis

Chalk uses a pure context-as-closure memory model (no Store/Load IR nodes). Variable assignment works via:

```perl
# In Builder:
$context = Chalk::IR::Context->extend_context($context, "lexical:$x", $value_node);
```

**Hypothesis**: Context extension creates proper shadowing, but either:
1. The Builder stores a stale context reference in the IR graph, OR
2. The Interpreter doesn't thread the updated context correctly between nodes, OR
3. Variable lookup (build_load_node) searches in wrong context

## Files to Investigate

### Builder
- `lib/Chalk/IR/Builder.pm` (lines 201-214: `build_store_node`)
- `lib/Chalk/IR/Builder.pm` (lines 218-240: `build_load_node`)

### Interpreter
- `lib/Chalk/IR/Interpreter.pm` (lines 23-54: context threading)
- `lib/Chalk/IR/Node/VariableRead.pm` (lines 23-30: `execute`)

### Semantic Actions
- `lib/Chalk/Grammar/Chalk/Rule/Assignment.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Variable.pm`

## Debugging Approach

1. Add debug logging to `Builder->build_store_node()` to trace context state
2. Log context extensions: what label, what value, context chain depth
3. In `build_load_node()`, log what context is being searched
4. Check if VariableRead node's `execute()` gets the updated context
5. Verify interpreter threads context correctly: each node's result stored in context, next node gets extended context

## Test Cases to Add

```perl
# t/sea-of-nodes/interpreter-differential.t
test_against_perl('my $x = 5; $x = 10; return $x;', 'Simple reassignment');
test_against_perl('my $x = 5; $x = $x + 10; return $x;', 'Reassignment with expression');
test_against_perl('my $x = 5; my $y = 10; $x = $y; return $x;', 'Reassignment from another variable');
```

## Success Criteria

- [ ] Test case returns 10, not 5
- [ ] Context lookup finds most recent binding for a variable
- [ ] Differential tests for reassignment pass
- [ ] Multiple reassignments work: `$x = 5; $x = 10; $x = 15; return $x;` returns 15

## Related Issues

- Blocks implementation of increment/decrement operators (++/--)
- Blocks control flow with assignment in branches

## Priority

**P0 - BLOCKER**: Nothing with mutable state can execute until this is fixed.

## References

- `docs/ROADMAP_SELF_HOSTING.md` (Phase 1.1)
- `docs/INTERPRETER_SEMANTICS.md` (lines 96-110)
- `docs/memory-model.md` (context-as-closure architecture)
- Test file: `t/ir-builder-store.t` (tests store at Builder level, passes)
- Test file: `t/ir-builder-load.t` (tests load at Builder level, passes)
