# Type System Integration - Stage 1 Design

## Overview

Stage 1 of Type System Integration: Full Expression Pipeline. Enables type tracking through all expressions for optimization and eventual XS code generation.

**Related Issues:** #367, #368, #369, #370, #313

## Design Decisions

### Static Typing with Inference

Chalk is statically typed through inference (like Haskell/TypeScript), not dynamically typed:
- Types resolved at compile time
- No explicit type annotations required
- Type errors caught during compilation

### Flow-Sensitive Typing

Variable types depend on most recent assignment at each program point:

```perl
$x = 5;        # $x : Int
$x = 'hello';  # $x : String (reassignment changes type) ✓

$x = "hello";  # $x : String
$x += 1;       # Compile error: += requires numeric ✗
```

### Union Types at Control Flow Merge

When branches assign different types, result is a union:

```perl
if ($cond) {
    $x = 5;      # Int
} else {
    $x = "hi";   # String
}
# $x : Int | String
```

### Eager Cache + Lazy Verification

- **Eager**: Type field on nodes acts as cache, populated during construction
- **Lazy**: `compute_type()` provides authoritative type, validates/overrides cache
- Cache invalidated when nodes transformed; lazy recomputes on access

## Type Storage

```perl
# In Node base class
field $type :param :reader = Chalk::IR::Type::Top->top();

method compute_type() {
    # Subclasses override to compute from operands
    return $type;  # Base: return cached
}
```

## Inference Rules

| Node | Rule |
|------|------|
| Constant | Return stored type (already specific) |
| Add/Multiply/etc | `left.compute_type().widen(right).meet(right.compute_type())` |
| Variable (read) | Type from most recent assignment |
| Assignment | RHS type → update variable's type |
| Phi | Union of incoming branch types |
| Comparison | Always `TypeBool` |
| Ternary | Union of true/false branch types |

## Union Type Representation

```perl
class Chalk::IR::Type::Union {
    field @members :param :reader;  # [TypeInteger, TypeString]

    method contains($type) { ... }
    method narrow($excluded) { ... }  # Returns union minus excluded
}
```

## Type Narrowing

Union types can be narrowed via type guards:

```perl
my $x = get_value();  # $x : Int | String

if (is_int($x)) {
    # $x narrowed to Int
    $x += 1;  # ✓
}
```

Narrowing triggers: `is_int()`, `is_string()`, `defined()`, `ref()`, comparisons

## XS Backend (Deferred)

- Concrete types → direct C operations
- Union types → warning + SV* fallback
- Full XS codegen is Stage 2+ concern

## Implementation Phases

### Phase A: Type Field Infrastructure (~80% complete)
- Add `$type` field to Node base class (not just Constant)
- Default to `Top`

### Phase B: Literal Type Tracking (~90% complete)
- Verify all literal paths in parser/IR Builder set types
- Integer, Float, String, Bool literals

### Phase C: Operation Type Inference (~50% complete)
- Add `compute_type()` to remaining nodes:
  - Subtract, Divide, Negate
  - Comparison nodes (GT, LT, EQ, etc.) → Bool
  - Logical nodes (And, Or, Not)
- Pattern: widen+meet for numeric promotion

### Phase D: Variable Type Flow (Not started)
- Track variable types through assignments in IR Builder
- Implement union type representation
- Phi nodes compute union of incoming types
- SSA form: each assignment version has own type

### Phase E: Type Validation (Not started)
- Validation pass walks graph
- Check operation type compatibility
- Emit errors for type mismatches (e.g., `String += 1`)
- Warnings for implicit coercions

## Success Criteria

1. All expressions have non-Top types after inference
2. Type errors caught at compile time
3. Optimizer can use `compute_type()` for type-aware decisions
4. Foundation ready for XS code generation (Stage 2)

## Files Affected

- `lib/Chalk/IR/Node.pm` - Add $type field
- `lib/Chalk/IR/Node/*.pm` - Add compute_type() where missing
- `lib/Chalk/IR/Type/Union.pm` - New file
- `lib/Chalk/IR/Builder.pm` - Variable type tracking
- `lib/Chalk/IR/Validator.pm` - Type validation pass
