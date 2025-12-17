# Grammar ↔ IR Type System Mapping

This document describes the relationship between Chalk's two type systems and when to use each.

## Overview

Chalk has two separate type systems serving different purposes:

| System | Namespace | Purpose |
|--------|-----------|---------|
| **Grammar Types** | `Chalk::Grammar::Chalk::Type::*` | Language-level types (Perl semantics) |
| **IR Types** | `Chalk::IR::Type::*` | Optimization-level types (constant folding, codegen) |

## Key Differences

### Grammar Types: "Lattice of Types"

Grammar types model Perl's type semantics with subtyping relationships:

```
                     Any
                      │
         ┌───────────┼───────────┐
         │           │           │
      Scalar       Array       Hash       Code
         │           │           │          │
    ┌────┼────┐   ArrayRef   HashRef    CodeRef
    │    │    │
   Str  Ref  Undef
    │
   Num
    │
   Int
```

**Subtyping chain:** `Int <: Num <: Str <: Scalar <: Any`

- **Purpose:** Type checking, validation, coercion rules
- **Lattice operations:** `meet()` (intersection), `join()` (union)
- **Values:** Types themselves, not specific values
- **Use cases:** Parsing, semantic analysis, builtin signatures

### IR Types: "Lattice of Constants"

IR types model value precision for optimization:

```
        TypeTop (global unknown)
              │
    ┌─────────┼─────────┐
    │         │         │
 Integer    Float     Bool    Memory   Ctrl
    │         │         │
  IntTop   FloatTop  BoolTop
    │         │         │
 constant  constant  TRUE/FALSE
    │         │         │
  IntBot   FloatBot  (none)
              │
        TypeBottom (global error)
```

**Each type has three layers:**
- `TOP` - Unknown value of that type
- `constant(val)` - Known specific value
- `BOTTOM` - Error/unreachable

- **Purpose:** Constant folding, algebraic simplification, code generation
- **Lattice operations:** `meet()`, `join()`, `widen()` (numeric promotion)
- **Values:** Track actual values when known
- **Use cases:** Peephole optimization, XS code generation

## Type Mapping Table

| Grammar Type | IR Type | Notes |
|-------------|---------|-------|
| `Int` | `Integer` | Direct mapping |
| `Num` | `Float` | Perl's "floating point" |
| `Str` | *(none)* | No IR string type yet |
| `Boolean` | `Bool` | Direct mapping |
| `Array` | *(none)* | Future: TypeArray |
| `Hash` | *(none)* | Future: TypeHash |
| `Object` | *(none)* | Future: struct types |
| `Undef` | *(none)* | Maps to constants with undef value |
| `Any` | `Top` | Unknown type |
| `None` | `Bottom` | Error/unreachable |
| *(control flow)* | `Ctrl` | IR-only: control edges |
| *(memory)* | `Memory` | IR-only: memory state |
| *(tuples)* | `Tuple` | IR-only: multi-returns |

## When to Use Each System

### Use Grammar Types When:

1. **Parsing and semantic analysis**
   ```perl
   # TypeLattice infers types from operations
   my $type = $type_lattice->infer_type_from_operation('Add', $node);
   # Returns Chalk::Grammar::Chalk::Type::Num
   ```

2. **Validating operations**
   ```perl
   my $result = $type_lattice->validate_operation('Add', $left_type, $right_type);
   # Returns { valid => 1 } or { valid => 0, error => "..." }
   ```

3. **Type registry and class definitions**
   ```perl
   $registry->register_class('Point', {
       x => Chalk::Grammar::Chalk::Type::Num->new(),
       y => Chalk::Grammar::Chalk::Type::Num->new(),
   });
   ```

4. **Builtin function signatures**
   ```perl
   # From Chalk::Builtins
   push => { params => [Type::Array, Type::Any], returns => Type::Int }
   ```

### Use IR Types When:

1. **Constant folding in peephole optimization**
   ```perl
   method compute() {
       my $left_type = $left->compute();
       if ($left_type->is_constant && $right_type->is_constant) {
           return Chalk::IR::Type::Integer->constant(
               $left_type->value + $right_type->value
           );
       }
       return Chalk::IR::Type::Integer->TOP();
   }
   ```

2. **Type inference for optimization**
   ```perl
   method compute_type() {
       my $left_type = $left->compute_type();
       my $right_type = $right->compute_type();
       # Use widen+meet for numeric promotion
       my $widened_left = $left_type->widen($right_type);
       my $widened_right = $right_type->widen($left_type);
       return $widened_left->meet($widened_right);
   }
   ```

3. **XS code generation**
   ```perl
   # IR type determines C type
   # Integer → int64_t, SvIV()
   # Float → double, SvNV()
   # Bool → bool, SvTRUE()
   ```

## How TypeInference Bridges the Systems

`Chalk::IR::TypeInference` connects the two systems:

```perl
class Chalk::IR::TypeInference {
    field $type_lattice :param :reader;  # Grammar TypeLattice

    method infer_type($node) {
        # Delegates to Grammar TypeLattice for operation inference
        return $type_lattice->infer_type_from_operation($op, $node);
        # Returns Chalk::Grammar::Chalk::Type::* objects
    }
}
```

The bridge pattern:
1. IR nodes have `compute()` returning IR types (for optimization)
2. IR nodes have `compute_type()` returning IR types (for type inference)
3. TypeLattice provides Grammar types (for semantic analysis)
4. Future: Converter will map Grammar → IR for codegen

## Future Work: Grammar → IR Conversion

Issue #369 will implement explicit conversion:

```perl
# Proposed API
method to_ir_type($grammar_type) {
    return Chalk::IR::Type::Integer->TOP()
        if $grammar_type isa Chalk::Grammar::Chalk::Type::Int;
    return Chalk::IR::Type::Float->TOP()
        if $grammar_type isa Chalk::Grammar::Chalk::Type::Num;
    # ...
}
```

This enables:
- IR generation with proper types from Grammar analysis
- Better constant folding with type information
- Type-directed XS code generation

## Examples from Codebase

### Grammar TypeLattice inferring from operations

```perl
# lib/Chalk/Grammar/Chalk/TypeLattice.pm:42-44
return Chalk::Grammar::Chalk::Type::Num->new()
    if $op =~ qr/^(Add|Subtract|Multiply|Divide|Negate)$/;
```

### IR Type constant folding

```perl
# lib/Chalk/IR/Node/Add.pm compute()
if ($left_type->is_constant && $right_type->is_constant) {
    return Chalk::IR::Type::Integer->constant(
        $left_type->value + $right_type->value
    );
}
```

### IR Type numeric promotion

```perl
# lib/Chalk/IR/Node/Add.pm compute_type()
my $widened_left = $left_type->widen($right_type);
my $widened_right = $right_type->widen($left_type);
return $widened_left->meet($widened_right);
```

## Related Documentation

- `docs/plans/2025-12-16-stage0-type-system-integration-design.md` - XS codegen design
- `docs/plans/2025-12-09-type-system-integration-breakdown.md` - Implementation plan
- Type lattice design: https://gist.github.com/perigrin/c4780a7511ba1421e49a4a8b385aaa3d

## Related Issues

- #332 - Type System Integration (parent)
- #366 - Field Initializer Type Narrowing
- #367 - Literal Expression Type Tracking
- #368 - Type Validation During Compilation
- #369 - Grammar-to-IR Type Conversion
- #370 - Operation Type Preservation
- #408 - This documentation
