# Chapter 15: Fixed-Length Arrays - Design

**Issue:** #337
**Date:** 2025-12-18
**Status:** Approved

## Overview

Implement Sea of Nodes Chapter 15: single-dimensional fixed-length arrays with runtime bounds checking, dynamic allocation, and length operator.

## Architecture Decision

**Chosen approach:** Extend existing array nodes with length/type tracking and bounds checking.

Leverages existing heap infrastructure from Perl-style arrays. Add optional `length` parameter for fixed arrays, with fallback to dynamic AV if growable arrays needed later.

## Type Representation

### TypeStruct with Implicit Fields

Arrays represented as TypeStruct with special fields that cannot collide with user-defined fields:

```perl
# "#"  -> length (integer)
# "[]" -> body (element type)

Chalk::IR::Type::Struct->new(
    fields => {
        '#'  => Chalk::IR::Type::Integer->i64(),
        '[]' => Chalk::IR::Type::Any->TOP(),  # Starts wide
    }
)
```

### Element Type Inference

Element types tracked via TypeInference semiring, not annotations:

```perl
# When ArrayStore happens:
# 1. Get current element type from array's type_env
# 2. Meet with stored value's type
# 3. Update type_env with narrower element type

# Example flow:
my @arr;                    # element_type = Any (top)
$arr[0] = 1;               # element_type = meet(Any, Int) = Int
$arr[1] = 2;               # element_type = meet(Int, Int) = Int
$arr[2] = "x";             # element_type = meet(Int, Str) = Any (widens)
```

### Integration Point

- TypeInference's `infer_type()` in ArrayStore rule tracks element types
- Stored in `type_env` under array variable name with element suffix
- e.g., `type_env->{'@arr:element'} = Int`

## IR Node Modifications

### NewArray - Extended

```perl
Chalk::IR::Node::NewArray->new(
    length => $len_node,           # NEW: size expression (required for fixed)
    element_type => $type,         # NEW: starts as Any, narrowed by inference
    memory => $mem_node,           # Memory state input
)
# Returns: [pointer, new_memory_state]
```

### ArrayLength - New Node

```perl
Chalk::IR::Node::ArrayLength->new(
    array => $array_ptr,
)
# Returns: integer length (the "#" field)
# Peephole: if array is NewArray with constant length, fold to constant
```

### ArrayLoad - Bounds Checking

```perl
Chalk::IR::Node::ArrayLoad->new(
    array => $array_ptr,
    index => $index_node,
    memory => $mem_node,
    bounds_check => 1,             # NEW: enable runtime check
)

# On execute():
# 1. Get array length from "#" field
# 2. Check: 0 <= index < length
# 3. If out of bounds -> Panic
# 4. Otherwise load element
```

### ArrayStore - Bounds Checking

```perl
Chalk::IR::Node::ArrayStore->new(
    array => $array_ptr,
    index => $index_node,
    value => $value_node,
    memory => $mem_node,
    bounds_check => 1,             # NEW: enable runtime check
)
# Same bounds checking as ArrayLoad
```

### Panic - New Node

```perl
Chalk::IR::Node::Panic->new(
    message => "Array index out of bounds",
    source_info => $loc,
)
# Terminates execution with error
# Control flow: Never-like (no successor)
```

## Peephole Optimizations

### ArrayLength Constant Folding

```perl
# In ArrayLength::peephole()
if ($array->isa('NewArray') && $array->length->is_constant) {
    return Constant->new(
        value => $array->length->value,
        type => Chalk::IR::Type::Integer->i64()
    );
}
```

### Bounds Check Elimination

```perl
# In ArrayLoad/ArrayStore::peephole()
if ($index->is_constant && $array->length && $array->length->is_constant) {
    my $i = $index->value;
    my $len = $array->length->value;
    if ($i >= 0 && $i < $len) {
        # Safe - remove bounds check
        $self->bounds_check(0);
    } elsif ($i < 0 || $i >= $len) {
        # Always fails - replace with Panic
        return Panic->new(message => "Index $i out of bounds [0..$len)");
    }
}
```

### Dead Array Elimination

Standard dead code elimination applies:
- If NewArray result is never used (no loads/stores reference it)
- And no side effects
- Eliminate the allocation

## Safety Mechanisms

Per SoN Chapter 15, arrays are always safety checked:

**Runtime checks:**
- Out-of-bounds indexing (negative or >= length)
- Invalid array creation (negative lengths)

**Panic conditions:**
```perl
$arr[-1]        # Panic: negative index
$arr[$len]      # Panic: index >= length
my @a : len(-5) # Panic: negative length (if we add length syntax)
```

## Files to Create/Modify

### New Files
- `lib/Chalk/IR/Node/ArrayLength.pm`
- `lib/Chalk/IR/Node/Panic.pm`
- `t/ir/fixed-arrays.t`
- `t/ir/bounds-checking.t`

### Modified Files
- `lib/Chalk/IR/Node/NewArray.pm` - add length, element_type fields
- `lib/Chalk/IR/Node/ArrayLoad.pm` - add bounds_check field
- `lib/Chalk/IR/Node/ArrayStore.pm` - add bounds_check field
- `lib/Chalk/IR/Type/Struct.pm` - support `#` and `[]` field names
- `lib/Chalk/Grammar/Chalk/Rule/ArrayStore.pm` - integrate with TypeInference

## Test Coverage

- Fixed array creation with length
- ArrayLength operator
- Bounds checking (valid indices)
- Bounds checking (invalid indices -> Panic)
- Element type inference through stores
- Peephole optimizations (constant folding, check elimination)
- Edge cases (empty arrays, single element, max index)

## Reference

https://github.com/SeaOfNodes/Simple (Chapter 15)
