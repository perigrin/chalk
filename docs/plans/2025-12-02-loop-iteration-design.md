# Loop Iteration Implementation Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement actual loop iteration in the CEKDataflow interpreter so that Sea of Nodes IR with loops can be executed, not just structurally validated.

**Architecture:** Adapt the Simple compiler's GraphEvaluator approach for our dataflow scheduling model. Track active control path in Loop nodes, use path index for Phi value selection, and re-queue loop body nodes on backedge traversal.

**Tech Stack:** Perl 5.42, Perl OO with `class` keyword, Test2::V0

**Related Issues:** #273, blocks #247 (iteration limits), blocks #270 (break/continue)

**Reference:** [Simple GraphEvaluator.java](https://github.com/SeaOfNodes/Simple/blob/main/chapter08/src/main/java/com/seaofnodes/simple/GraphEvaluator.java)

---

## Background

The current CEKDataflow interpreter is single-pass: each node executes exactly once. The `%computed` map marks nodes as done, and they're never re-executed. For loops to work, we need to:

1. Detect when the Loop's backedge becomes active (condition true, continue iterating)
2. Re-execute the Loop node and all dependent nodes
3. Select correct Phi values based on iteration (entry vs backedge)
4. Terminate when exit condition is met (condition false)

## Design from Simple Compiler

The Simple compiler's `GraphEvaluator` uses:

```java
if (region instanceof LoopNode && region.in(1) != prev) {
    if (loops--<=0) return new Result(ResultType.TIMEOUT, 0);
    latchLoopPhis(region, prev);
}
```

Key insights:
- **Control flow traversal** tracks which path led to each region
- **Loop detection** recognizes backedge by checking predecessor != entry
- **Phi value selection** uses predecessor index to select phi input
- **Atomic phi update** computes all loop phis before caching (breaks circular deps)
- **Iteration limit** prevents infinite loops

## Adaptation for CEKDataflow

Our interpreter uses dataflow scheduling rather than control traversal. We adapt as follows:

### 1. Loop Node Tracks Active Path

The Loop node stores which input (entry=0 or backedge=1) was active:

```perl
# In Loop.pm
field $active_input_index :reader = 0;  # 0=entry, 1=backedge

method execute($context) {
    for my $i (0..$#inputs) {
        my $ctrl_result = $context->("node:$inputs[$i]");
        if ($ctrl_result) {
            $active_input_index = $i;
            return $i;
        }
    }
    die "Loop node has no active input path";
}
```

### 2. Phi Nodes Use Loop's Path Index

For Loop-attached Phi nodes, use Loop's `active_input_index` directly:

```perl
# In Phi.pm execute()
if ($region_node->op eq 'Loop') {
    my $idx = $region_node->active_input_index;
    my $value_index = $idx + 1;  # inputs[0] is region_id
    return $context->("node:$inputs[$value_index]");
}
```

### 3. CEKDataflow Loop Iteration Logic

After executing a Loop node, check if backedge is active:

```perl
if ($node->op eq 'Loop' && $value > 0) {  # backedge active
    # Check iteration limit
    $loop_iterations{$node_id}++;
    if ($loop_iterations{$node_id} > $max_iterations) {
        die "Loop exceeded iteration limit";
    }

    # Reset loop body nodes for re-execution
    $self->reset_loop_body($node_id, \%computed, \%waiting);
}
```

### 4. Loop Body Reset

Reset computed state for loop-dependent nodes:

```perl
method reset_loop_body($loop_id, $computed, $waiting) {
    my @body_nodes = $self->find_loop_body_nodes($loop_id);

    for my $node_id (@body_nodes) {
        delete $computed->{$node_id};
        # Re-add to waiting with dependencies
        $waiting->{$node_id} = { ... };
    }
}

method find_loop_body_nodes($loop_id) {
    # Find Phi nodes attached to this Loop
    # Find all nodes that depend on those Phis
    # Return list of node IDs in loop body
}
```

## Execution Flow

```
=== Iteration 0 (Entry) ===
Start (active) → Loop (active_input=0, returns 0)
                   ↓
               Phi (selects input[1] = initial value)
                   ↓
               LT (i < 10) → If → Proj(true=active) → backedge

=== Iteration 1+ (Backedge) ===
Loop detects backedge active → reset_loop_body() → re-queue
Loop (active_input=1, returns 1)
   ↓
Phi (selects input[2] = loop value)
   ↓
LT → If → Proj(true or false based on condition)

=== Exit ===
If → Proj(false=active) → Return
```

## Test Cases

### Simple Counter Loop
```perl
# while ($i < 10) { $i = $i + 1; } return $i;
# Expected: 10
```

### Accumulator Loop
```perl
# $sum = 0; $i = 0;
# while ($i < 5) { $sum = $sum + $i; $i = $i + 1; }
# return $sum;
# Expected: 0+1+2+3+4 = 10
```

### Nested Loops
```perl
# while ($i < 3) { $j = 0; while ($j < 2) { count++; $j++; } $i++; }
# Expected: inner executes 2x per outer iteration = 6 total
```

## Files to Modify

1. `lib/Chalk/IR/Node/Loop.pm` - Add `active_input_index` tracking
2. `lib/Chalk/IR/Node/Phi.pm` - Use Loop's path index for value selection
3. `lib/Chalk/Interpreter/CEKDataflow.pm` - Loop iteration detection and body reset
4. `t/interpreter/cek-loop-execution.t` - New test file for loop execution

## Implementation Order

1. Add `active_input_index` to Loop.pm (TDD)
2. Update Phi.pm to use Loop's path index (TDD)
3. Add loop body detection to CEKDataflow (TDD)
4. Add loop iteration and reset logic to CEKDataflow (TDD)
5. Add iteration limit support (TDD)
6. Add comprehensive integration tests

## Success Criteria

- [ ] Simple counter loop executes correctly
- [ ] Accumulator loop with multiple variables works
- [ ] Nested loops execute inner before outer continues
- [ ] Iteration limit prevents infinite loops
- [ ] Existing chapter07.t structural tests still pass
- [ ] All interpreter tests pass
