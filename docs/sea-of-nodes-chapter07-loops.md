# Sea of Nodes IR: Chapter 7 - Loop Support

## Overview

This document describes the implementation of Loop nodes and loop-carried dependencies in Chalk's Sea of Nodes intermediate representation. The implementation follows the "lazy phi" pattern to handle the circular dependency between loop phi nodes and loop body values.

## Architecture

### Core Components

1. **Loop Node** (`lib/Chalk/IR/Node.pm`)
   - Special Region node for loop headers
   - Two inputs: entry control + backedge control
   - Acts as merge point for loop control flow

2. **Loop Phi Nodes** (`lib/Chalk/IR/Node.pm`)
   - Regular Phi nodes at Loop merge points
   - Three inputs: control (Loop node) + initial value + loop value
   - Represent loop-carried dependencies

3. **Loop Tracking** (`lib/Chalk/IR/Builder.pm`)
   - Automatic variable modification detection
   - Scope snapshotting for comparison
   - Phi generation for modified variables

4. **WhileStatement Integration** (`lib/Chalk/Grammar/Chalk/Rule/WhileStatement.pm`)
   - Semantic action that builds Loop IR
   - Coordinates tracking and phi generation
   - Handles break/continue control flow

5. **Loop Validation** (`lib/Chalk/IR/Validator.pm`)
   - Validates Loop node structure
   - Checks phi placement correctness
   - Detects potential infinite loops

## Implementation Details

### The Lazy Phi Pattern

The circular dependency problem:
- Loop Phi needs the updated value from loop body
- Loop body references use the Phi node
- Can't create Phi without knowing loop value
- Can't process body without Phi existing

Solution (lazy phi):
```perl
# 1. Create Loop node with entry control only
my $loop = $builder->build_loop_node($entry_control);

# 2. Begin tracking variable modifications
$builder->begin_loop_tracking();

# 3. Process loop body (uses placeholder phis if needed)
# ... body statements ...

# 4. Generate phis with both initial and loop values
my $phis = $builder->generate_loop_phi_nodes($loop);

# 5. Wire backedge to complete Loop
push $loop->inputs->@*, $backedge_control;

# 6. End tracking
$builder->end_loop_tracking();
```

### Automatic Variable Tracking

The system automatically detects which variables need phi nodes:

```perl
# Before loop: snapshot scope
$builder->begin_loop_tracking();
my $entry_snapshot = $scope->snapshot_bindings();

# During loop: normal assignment updates scope
$scope->define('i', $updated_value);

# After loop: compare and generate phis
my @modified = $scope->find_modified_variables($entry_snapshot);
for my $var (@modified) {
    my $phi = build_loop_phi_node($loop, $initial, $loop_value);
    $scope->define($var, $phi->id);
}
```

### IR Structure for `while ($i < 10) { $i = $i + 1; }`

```
Start
  │
  ├─► Constant(0) ────────┐ (initial $i)
  │                       │
  └─► Loop ◄──────────────┼─────┐ (backedge)
        │                 │     │
        ├─► Phi_i ────────┤     │
        │     │           │     │
        │     └─► Less ──┐│     │
        │           │    ││     │
        │     Const(10) ─┘│     │
        │                 │     │
        └─► If ◄──────────┘     │
              │                 │
              ├─► IfTrue        │
              │     │           │
              │     └─► Add ────┤ (i + 1)
              │           │     │
              │           └─────┘ (Store updates Phi_i input)
              │
              └─► IfFalse
                    │
                    └─► Region (exit)
                          │
                          └─► Return (Phi_i)
```

### Break and Continue Support

WhileStatement handles break/continue by tracking exit controls:

```perl
my @break_controls;    # Exit loop immediately
my @continue_controls; # Jump to next iteration

for my $stmt ($body_block->{statements}->@*) {
    if ($stmt->{type} eq 'break') {
        push @break_controls, $current_ctrl;
        next;  # Don't advance control
    } elsif ($stmt->{type} eq 'continue') {
        push @continue_controls, $current_ctrl;
        next;  # Don't advance control
    }
    # ... normal statement processing
}

# Backedge = normal end + continue paths
my @backedge = ($current_ctrl, @continue_controls);

# Exit = false branch + break paths
my @exit = ($if_false->id, @break_controls);
```

## API Reference

### Builder Methods

#### `build_loop_node($entry_control = undef)`
Creates a Loop node with entry control. Backedge added later.

**Returns**: Loop Node object

#### `build_loop_phi_node($loop_node, $initial_value, $loop_value = undef)`
Creates a Phi node for loop-carried dependency.

**Parameters**:
- `$loop_node`: Loop control node
- `$initial_value`: Value before loop entry
- `$loop_value`: Updated value from loop body (optional, added later for lazy phi)

**Returns**: Phi Node object

#### `begin_loop_tracking()`
Starts tracking loop-carried dependencies. Snapshots current scope.

#### `end_loop_tracking()`
Stops tracking and cleans up state.

#### `generate_loop_phi_nodes($loop_node)`
Generates phi nodes for all modified variables.

**Parameters**:
- `$loop_node`: Loop node to attach phis to

**Returns**: Hashref mapping variable names to Phi nodes

### Scope Methods

#### `snapshot_bindings()`
Creates immutable copy of current variable bindings.

**Returns**: Hashref of variable name → node ID mappings

#### `find_modified_variables($snapshot)`
Compares current bindings against snapshot.

**Parameters**:
- `$snapshot`: Previous binding state from `snapshot_bindings()`

**Returns**: Array of modified variable names

### Validator Methods

#### `validate_loop_structure($graph)`
Validates Loop nodes in the graph.

**Checks**:
- Loop has 1-2 inputs (entry + optional backedge)
- Errors on >2 inputs (malformed structure)
- Detects loops without exit paths (infinite loops)

**Returns**: Array of error messages

## Examples

### Simple Counting Loop

```perl
my $i = 0;
while ($i < 10) {
    $i = $i + 1;
}
return $i;
```

**IR Structure**:
- Loop node with 2 inputs (entry, backedge)
- Phi_i with 3 inputs (Loop, Constant(0), Add result)
- If node tests condition
- Add node increments counter
- Return uses Phi_i (final value)

See: `examples/sea-of-nodes/chapter07_simple_loop.pl`

### Multiple Variable Loop

```perl
my $i = 0;
my $sum = 0;
while ($i < $n) {
    $sum = $sum + $i;
    $i = $i + 1;
}
return $sum;
```

**IR Structure**:
- Two phi nodes: Phi_i and Phi_sum
- Both phis merge initial values with loop updates
- Only modified variables get phis ($n doesn't)

See: `examples/sea-of-nodes/chapter07_loop_with_phi.pl`

### Nested Loops

```perl
my $i = 0;
while ($i < $n) {
    my $j = 0;
    while ($j < $m) {
        # inner body
        $j = $j + 1;
    }
    $i = $i + 1;
}
```

**IR Structure**:
- Outer Loop with Phi_i
- Inner Loop with Phi_j (nested inside outer IfTrue)
- Scope hierarchy: inner loop can see outer variables
- Each loop has independent phi nodes

See: `examples/sea-of-nodes/chapter07_nested_loops.pl`

## Testing

### Test Coverage

- **chapter07.t**: 10 tests covering Loop node structure and validation
- **loop-phi-tracking.t**: 7 tests for variable tracking system
- **Total**: 17/17 tests passing

### Test Organization

```
t/sea-of-nodes/
├── chapter07.t              # Loop node structure tests
└── loop-phi-tracking.t      # Variable tracking tests

examples/sea-of-nodes/
├── chapter07_simple_loop.pl      # Basic patterns
├── chapter07_loop_with_phi.pl    # Multiple variables
└── chapter07_nested_loops.pl     # Nested structures
```

## Design Decisions

### Why Lazy Phi?

**Alternative**: Create phi nodes before processing body
**Problem**: Don't know loop value until body is processed
**Solution**: Create phi with initial value, add loop value after body

### Why Automatic Detection?

**Alternative**: Require manual phi annotations
**Problem**: Error-prone, tedious, breaks with refactoring
**Solution**: Compare scope snapshots to find modified variables

### Why Not Scope Merging?

**Alternative**: Merge scopes at loop exit
**Problem**: Doesn't capture SSA form, harder to optimize
**Solution**: Explicit phi nodes represent value flow

## Future Enhancements

### Potential Optimizations

1. **Loop Invariant Code Motion**: Move constant computations outside loop
2. **Strength Reduction**: Replace expensive operations with cheaper equivalents
3. **Loop Unrolling**: Duplicate body to reduce iteration overhead
4. **Induction Variable Analysis**: Detect and optimize loop counters

### Missing Features

1. **For Loops**: Currently only while loops supported
2. **Do-While Loops**: Test condition at end instead of start
3. **Loop Fusion**: Combine adjacent loops over same range
4. **Loop Interchange**: Reorder nested loops for better cache locality

## References

- Original Sea of Nodes paper: Cliff Click's PhD thesis
- SSA Book: "SSA-based Compiler Design" (Chapter on Loop Optimization)
- Implementation: WhileStatement.pm, Builder.pm, Validator.pm
- Tests: t/sea-of-nodes/chapter07.t, t/sea-of-nodes/loop-phi-tracking.t
