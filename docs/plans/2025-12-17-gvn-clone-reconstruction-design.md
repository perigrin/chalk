# GVN Clone-Based Reconstruction Design

## Problem

GVN (Global Value Numbering) optimizer breaks polymorphic node types when reconstructing nodes. After optimization, `Chalk::IR::Node::Add` becomes generic `Chalk::IR::Node`, causing test failures in:
- `t/sea-of-nodes/gvn.t` (Test 8, Test 14)
- `t/integration/app-default-ir-generation.t`

Related issues: #385, #200

## Root Cause

`Chalk::IR::Node->from_hash()` only supports polymorphic reconstruction for `Constant` and `Start` nodes. All other ops fall back to generic `Chalk::IR::Node` because polymorphic constructors expect node objects, not node IDs.

## Solution: Clone-Based Reconstruction

Instead of reconstructing nodes from hash data, clone the original node and update its inputs/attributes.

### 1. Add `clone_with_inputs()` to Chalk::IR::Node

```perl
method clone_with_inputs($new_inputs, $new_attributes = undef, $new_id = undef) {
    my $class = blessed($self);

    return $class->new(
        id              => $new_id // $id,
        op              => $op,
        inputs          => $new_inputs,
        attributes      => $new_attributes // $attributes,
        source_info     => $source_info,
        transform_chain => $transform_chain,
    );
}
```

Key: `blessed($self)` preserves the polymorphic class (Add, Multiply, etc.).

### 2. Update GVN.pm

Replace lines 86-96 in `run_gvn()`:

```perl
# Before (broken):
my $new_node = Chalk::IR::Node->from_hash({...});

# After (preserves polymorphism):
my $new_node = $old_node->clone_with_inputs(\@new_inputs, $new_attributes);
```

### 3. Record Transform (Optional Enhancement)

After cloning, record the GVN optimization:

```perl
if ($had_redirections) {
    $new_node->record_transform('optimization', 'GVN',
        context => "inputs redirected due to CSE"
    );
}
```

## Test Expectations

| Test | Current | After Fix |
|------|---------|-----------|
| Test 8: Different constants not merged | FAIL | PASS |
| Test 14: Polymorphic types preserved | FAIL | PASS |

## Implementation Steps

1. Add `clone_with_inputs()` method to `lib/Chalk/IR/Node.pm`
2. Update `lib/Chalk/IR/Optimizer/GVN.pm` to use clone instead of from_hash
3. Remove TODO markers from gvn.t tests
4. Run full test suite to verify no regressions

## Files Changed

- `lib/Chalk/IR/Node.pm` - Add clone_with_inputs method
- `lib/Chalk/IR/Optimizer/GVN.pm` - Use clone-based reconstruction
- `t/sea-of-nodes/gvn.t` - Remove TODO markers after fix
