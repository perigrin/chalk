# Current Critical Issues

This directory contains detailed specifications for the 3 critical bugs blocking interpreter execution for self-hosting.

## Priority 0 (BLOCKER) Issues

### 1. Variable Reassignment Bug
**File**: [`bug-variable-reassignment.md`](./bug-variable-reassignment.md)

Context-based variable reassignment doesn't work. Second assignment doesn't update the value.

```perl
my $x = 5;
$x = 10;
return $x;  # Returns 5, should return 10
```

**Impact**: Blocks all stateful programs, increment/decrement operators.

---

### 2. Control Flow Assignment Bug
**File**: [`bug-control-flow-assignment.md`](./bug-control-flow-assignment.md)

Assignments inside if/else blocks don't propagate through Region/Phi merge points.

```perl
my $result = 0;
if ($x > 0) { $result = 10; }
return $result;  # Returns 0, should return 10
```

**Impact**: Blocks conditional logic with side effects, loops with updates.

---

### 3. Multiple Return Nodes Bug
**File**: [`bug-multiple-return-nodes.md`](./bug-multiple-return-nodes.md)

Parser creates multiple Return nodes for if/else with early returns.

```perl
if (1) { return 42; } else { return -42; }
# Error: Malformed IR graph (multiple Return nodes)
```

**Impact**: Blocks early returns, common control flow patterns.

---

## Creating GitHub Issues

To create these as GitHub issues, you can either:

1. **Via GitHub Web UI**: Copy the content from each markdown file
2. **Via GitHub CLI** (if available):
   ```bash
   gh issue create --title "..." --body-file docs/current-issues/bug-variable-reassignment.md
   ```
3. **Via API**: Use the GitHub REST API to create issues programmatically

## References

- [`docs/ROADMAP_SELF_HOSTING.md`](../ROADMAP_SELF_HOSTING.md) - Full roadmap with all phases
- [`docs/INTERPRETER_SEMANTICS.md`](../INTERPRETER_SEMANTICS.md) - Known semantic issues
- [`docs/INTERPRETER_COVERAGE.md`](../INTERPRETER_COVERAGE.md) - Test coverage status

## Status

All three bugs must be fixed to achieve minimal self-hosting (execute linear programs with control flow).

**Estimated timeline**: 3-4 weeks for all three bugs.
