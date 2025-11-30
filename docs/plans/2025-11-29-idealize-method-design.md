# idealize() Method Design

## Overview

Add `idealize()` methods to IR nodes for algebraic simplification, matching the Sea of Nodes Simple reference (chapter04).

## Architecture

### Method Signature

Each node class implements:
```perl
method idealize() {
    # Return replacement node if optimization applies
    # Return nothing (bare return) if no optimization
    return;
}
```

### Integration with peephole()

The `peephole()` method orchestrates optimizations in order:
1. **Constant folding** via `compute()` - if result is constant, replace with Constant node
2. **Algebraic simplification** via `idealize()` - if returns a node, use it
3. **No change** - return `$self`

```perl
method peephole($graph) {
    my $type = $self->compute();
    if ($type->is_constant) {
        return Chalk::IR::Node::Constant->new(
            value => $type->value,
            type  => 'Integer',
        );
    }

    if (my $idealized = $self->idealize()) {
        return $idealized;
    }

    return $self;
}
```

## Node-Specific Optimizations

### Add
| Rule | Transformation |
|------|----------------|
| Identity (right) | `x + 0 → x` |
| Identity (left) | `0 + x → x` |
| Doubling | `x + x → x * 2` |

### Multiply
| Rule | Transformation |
|------|----------------|
| Identity (right) | `x * 1 → x` |
| Identity (left) | `1 * x → x` |
| Zero (right) | `x * 0 → 0` |
| Zero (left) | `0 * x → 0` |

### Divide
| Rule | Transformation |
|------|----------------|
| Identity | `x / 1 → x` |

### Subtract
No optimizations - returns nothing.

### Negate
No optimizations - returns nothing.

## Files to Modify

1. `lib/Chalk/IR/Node/Base.pm` - Add default `idealize()` method
2. `lib/Chalk/IR/Node/Add.pm` - Add idealize() with identity/doubling rules
3. `lib/Chalk/IR/Node/Multiply.pm` - Add idealize() with identity/zero rules
4. `lib/Chalk/IR/Node/Divide.pm` - Add idealize() with identity rule
5. `lib/Chalk/IR/Node/Subtract.pm` - Add stub idealize()
6. `lib/Chalk/IR/Node/Negate.pm` - Add stub idealize()

## Testing Strategy

Create `t/sea-of-nodes/idealize.t` with tests for each optimization rule:
- Test that each rule triggers correctly
- Test that rules don't trigger incorrectly (non-constant operands)
- Test chained optimizations (idealize returns node that can be further optimized)
