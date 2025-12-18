# Chapter 14: Narrow Primitive Types - Design

**Issue:** #336
**Date:** 2025-12-18
**Status:** Approved

## Overview

Implement Sea of Nodes Chapter 14: sub-word integer types (i8, i16, i32, u8, u16, u32) and narrow float (f32), with truncation, extension, and overflow handling.

## Architecture Decision

**Chosen approach:** Parameterized Integer type with `bits` and `signed` fields.

Single `IR::Type::Integer` class handles all integer widths. Simpler than separate subtype classes, matches SoN reference implementation.

## Type System Changes

### Parameterized Integer

```perl
# IR::Type::Integer extended fields:
field $bits   :param :reader = 64;     # 1, 8, 16, 32, 64
field $signed :param :reader = 1;      # 1=signed, 0=unsigned
field $min    :reader;                 # Computed from bits/signed
field $max    :reader;                 # Computed from bits/signed
```

### Convenience Constructors

```perl
Chalk::IR::Type::Integer->i8()    # bits=>8, signed=>1
Chalk::IR::Type::Integer->i16()   # bits=>16, signed=>1
Chalk::IR::Type::Integer->i32()   # bits=>32, signed=>1
Chalk::IR::Type::Integer->u8()    # bits=>8, signed=>0
Chalk::IR::Type::Integer->u16()   # bits=>16, signed=>0
Chalk::IR::Type::Integer->u32()   # bits=>32, signed=>0
Chalk::IR::Type::Integer->bool()  # alias for u1
```

### Float32

```perl
# IR::Type::Float extended:
field $bits :param :reader = 64;  # 32 or 64
Chalk::IR::Type::Float->f32()     # bits=>32
```

### Range Tracking

- `meet()` computes intersection of value ranges
- `join()` computes union of value ranges
- Overflow detection: `(x ^ (x + y)) < 0` for signed types

## New IR Nodes

### Truncation/Extension

```perl
# Truncate: narrow from wider to narrower (e.g., i64 -> i8)
Chalk::IR::Node::Truncate->new(
    operand => $wide_node,
    target_type => Chalk::IR::Type::Integer->i8()
)

# SignExtend: widen signed (preserves sign bit)
Chalk::IR::Node::SignExtend->new(
    operand => $narrow_node,
    target_type => Chalk::IR::Type::Integer->i64()
)

# ZeroExtend: widen unsigned (pads with zeros)
Chalk::IR::Node::ZeroExtend->new(
    operand => $narrow_node,
    target_type => Chalk::IR::Type::Integer->i64()
)
```

### Bitwise Operations

```perl
# BitAnd: lhs & rhs (NOT short-circuit)
Chalk::IR::Node::BitAnd->new(left => $a, right => $b)

# BitOr: lhs | rhs
Chalk::IR::Node::BitOr->new(left => $a, right => $b)

# BitXor: lhs ^ rhs
Chalk::IR::Node::BitXor->new(left => $a, right => $b)

# BitNot: ~operand
Chalk::IR::Node::BitNot->new(operand => $a)
```

## Computation Model

Per SoN Chapter 14:
- All arithmetic performed in 64-bit
- Truncate on assignment to narrower variable/field
- Extend on load from narrower variable/field

## Peephole Optimizations

### Constant Folding (Truncate)

```perl
if ($operand->is_constant) {
    my $val = $operand->value;
    my $truncated = $val & $target_type->mask();
    # Sign-extend if signed and high bit set
    if ($target_type->signed && ($truncated & $target_type->sign_bit)) {
        $truncated = $truncated | ~$target_type->mask();
    }
    return Constant->new(value => $truncated, type => $target_type);
}
```

### Bitwise Identities

```perl
# BitAnd
x & -1  -> x         # identity
x & 0   -> 0         # annihilator
x & x   -> x         # idempotent

# BitOr
x | 0   -> x         # identity
x | -1  -> -1        # annihilator
x | x   -> x         # idempotent

# BitXor
x ^ 0   -> x         # identity
x ^ x   -> 0         # self-inverse
```

### Overflow Detection

For ranged integer types in Add/Multiply:
- Signed: `(x ^ (x + y)) < 0` when signs differ unexpectedly
- Unsigned: `result < operand` indicates overflow
- If overflow detected, widen result type to IntTop

## Files to Create/Modify

### New Files
- `lib/Chalk/IR/Node/Truncate.pm`
- `lib/Chalk/IR/Node/SignExtend.pm`
- `lib/Chalk/IR/Node/ZeroExtend.pm`
- `lib/Chalk/IR/Node/BitAnd.pm`
- `lib/Chalk/IR/Node/BitOr.pm`
- `lib/Chalk/IR/Node/BitXor.pm`
- `lib/Chalk/IR/Node/BitNot.pm`
- `t/ir/narrow-types.t`
- `t/ir/bitwise-ops.t`

### Modified Files
- `lib/Chalk/IR/Type/Integer.pm` - add bits/signed/min/max fields
- `lib/Chalk/IR/Type/Float.pm` - add bits field
- `lib/Chalk/IR/Node/Add.pm` - overflow detection
- `lib/Chalk/IR/Node/Multiply.pm` - overflow detection

## Test Coverage

- Type construction with all widths (i8, i16, i32, u8, u16, u32, f32)
- Truncation semantics (value masking, sign extension)
- Extension semantics (sign vs zero extend)
- Bitwise operation correctness
- Peephole optimization verification
- Overflow detection edge cases

## Reference

https://github.com/SeaOfNodes/Simple (Chapter 14)
