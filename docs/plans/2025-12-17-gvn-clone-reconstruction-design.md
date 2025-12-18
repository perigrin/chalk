# GVN Clone-Based Reconstruction Design

## Problem

GVN (Global Value Numbering) optimizer breaks polymorphic node types when reconstructing nodes. After optimization, `Chalk::IR::Node::Add` becomes generic `Chalk::IR::Node`, causing test failures in:
- `t/sea-of-nodes/gvn.t` (Test 8, Test 11, Test 14)
- `t/integration/app-default-ir-generation.t`

Related issues: #385, #200

## Root Cause

`Chalk::IR::Node->from_hash()` only supports polymorphic reconstruction for `Constant` and `Start` nodes. All other ops fall back to generic `Chalk::IR::Node` because polymorphic constructors expect node objects, not node IDs.

Additionally, polymorphic node classes (Add, Multiply, etc.) are NOT subclasses of Chalk::IR::Node - they have their own constructors that require node objects for operands.

## Solution: Clone-Based Reconstruction with Topological Sort

Instead of reconstructing nodes from hash data, clone the original node and update its inputs using a node_map for lookup.

### Key Challenges Solved

1. **Polymorphic constructors need node objects, not IDs**: Polymorphic nodes like Add store actual node references (`$left`, `$right`), not just IDs.

2. **Node ID mismatch**: Polymorphic nodes use `refaddr($self)` as their ID, which changes on clone. GVN needs to track old->new mappings.

3. **Processing order**: Input nodes must be processed before nodes that use them. Implemented topological sort.

### 1. Add `clone_with_inputs()` to Node Classes

Base Node.pm (for nodes with explicit IDs):
```perl
method clone_with_inputs($new_inputs, $new_attributes = undef, $node_map = undef) {
    my $class = blessed($self);
    return $class->new(
        id              => $id,
        op              => $op,
        inputs          => $new_inputs,
        attributes      => $new_attributes // $attributes,
        source_info     => $source_info,
        transform_chain => $transform_chain,
    );
}
```

Polymorphic nodes (Add, Multiply) look up operands from node_map:
```perl
method clone_with_inputs($new_inputs, $new_attributes = undef, $node_map = undef) {
    my $new_left = $node_map->{$new_inputs->[0]};
    my $new_right = $node_map->{$new_inputs->[1]};
    return Chalk::IR::Node::Add->new(
        left        => $new_left,
        right       => $new_right,
        source_info => $source_info,
    );
}
```

### 2. Update GVN.pm

1. Use topological sort (Kahn's algorithm) instead of string-sorted IDs
2. Track old_id -> new_node mapping
3. Pass node_map to clone_with_inputs

```perl
my @node_ids = $class->_topological_sort($graph);
my %old_to_new_node;

for my $node_id (@node_ids) {
    # ... process node ...
    if ($old_node->can('clone_with_inputs')) {
        $new_node = $old_node->clone_with_inputs(\@new_inputs, $new_attributes, \%old_to_new_node);
    } else {
        # Fallback to generic Node
    }
    $old_to_new_node{$node_id} = $new_node;
}
```

### 3. Topological Sort

Ensures input nodes are processed before nodes that use them:
```perl
sub _topological_sort($class, $graph) {
    # Kahn's algorithm - process nodes with in_degree=0 first
    # When a node is processed, decrement in_degree of its dependents
}
```

## Test Results

| Test | Before | After |
|------|--------|-------|
| Test 8: Different constants not merged | FAIL (TODO) | PASS |
| Test 11: Non-commutative order respected | FAIL (TODO) | PASS |
| Test 14: Polymorphic types preserved | FAIL (TODO) | PASS |

## Files Changed

- `lib/Chalk/IR/Node.pm` - Add clone_with_inputs method
- `lib/Chalk/IR/Node/Add.pm` - Add clone_with_inputs for polymorphic clone
- `lib/Chalk/IR/Node/Multiply.pm` - Add clone_with_inputs for polymorphic clone
- `lib/Chalk/IR/Node/Constant.pm` - Add clone_with_inputs for polymorphic clone
- `lib/Chalk/IR/Optimizer/GVN.pm` - Use clone-based reconstruction with topological sort
- `t/sea-of-nodes/gvn.t` - Remove TODO markers after fix

## Future Work

For full polymorphic type preservation, add `clone_with_inputs` to all polymorphic node classes. Currently implemented for: Add, Multiply, Constant. Other nodes fall back to generic Chalk::IR::Node (loses polymorphism but maintains correctness).
