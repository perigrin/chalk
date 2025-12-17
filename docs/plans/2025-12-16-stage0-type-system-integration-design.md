# Stage 0: Type System Integration Design

**Date:** 2025-12-16
**Status:** Approved
**Theme:** Type System Integration (Stage 0)

## Overview

This document describes the type system integration strategy for Stage 0 (Perl→XS Compiler). The goal is type-safe XS code generation that leverages C-native types internally and only uses Perl types (SV*, etc.) at integration boundaries.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Primary Goal | Type-safe XS code generation | Generate specialized C API calls (SvIV, NV, SvPV) based on inferred types |
| Uninitialized Fields | Infer from usage patterns | Bidirectional inference - types flow from initializers AND usage sites |
| Type Conflicts | Widen to common supertype | Use lattice join() - permissive like Perl, still enables optimization |
| Development Approach | Interleaved iteration | Build codegen and types together, each iteration informs the next |
| XS Type Strategy | C-native internally, Perl at boundaries | Maximize native C performance, convert only at Perl integration points |

## Three-Tier Type Hierarchy

```
Tier 1: Grammar Types (Perl semantics)
    Chalk::Grammar::Chalk::Type::*
    Int, Num, Str, Bool, Array, Hash, Object
           ↓ (during IR generation)

Tier 2: IR Types (optimization)
    Chalk::IR::Type::*
    TypeInteger, TypeFloat, TypeMemory, etc.
           ↓ (during XS codegen)

Tier 3: Machine Types (code generation)
    C-native: int64_t, double, char*, struct*
    Perl API: SV*, AV*, HV* (boundary only)
```

## Type Lowering Rules

| IR Type | Internal (C-native) | Perl Boundary |
|---------|---------------------|---------------|
| TypeInteger | `int64_t` | `SvIV(sv)` / `newSViv(val)` |
| TypeFloat | `double` | `SvNV(sv)` / `newSVnv(val)` |
| TypeString | `char*` + len | `SvPV(sv, len)` / `newSVpvn()` |
| TypeArray | `struct chalk_array*` | `AV*` at boundary |
| TypeHash | `struct chalk_hash*` | `HV*` at boundary |
| TypeObject | `struct ClassName*` | SV* blessed ref |

### Boundary Detection

- **Function entry:** Convert SV* args → C-native
- **Function exit:** Convert C-native → SV* return
- **Field access from Perl:** Accessor XSUBs handle conversion
- **Internal method calls:** Stay in C-native

### Example Generated XS

```c
// Method: $point->distance($other)
double Point_distance(Point* self, Point* other) {
    // Pure C computation - no Perl types internally
    double dx = self->x - other->x;
    double dy = self->y - other->y;
    return sqrt(dx*dx + dy*dy);
}

// XSUB wrapper (Perl boundary)
XS(XS_Point_distance) {
    Point* self = (Point*)SvIV(SvRV(ST(0)));  // SV* → C
    Point* other = (Point*)SvIV(SvRV(ST(1)));
    double result = Point_distance(self, other);
    RETVAL = newSVnv(result);  // C → SV*
}
```

## Module Organization

```
Chalk::Semiring::TypeInference        # Generic semiring mechanics (meet/join/propagate)
        ↓ uses
Chalk::Grammar::Chalk::TypeInference  # Chalk-specific inference rules (NEW)
Chalk::Grammar::Chalk::TypeLattice    # Chalk type hierarchy (exists)
Chalk::Grammar::Chalk::Type::*        # Concrete types (exists)
```

The Chalk-specific inference logic lives in `Chalk::Grammar::Chalk::TypeInference`:
- Implements Chalk/Perl-specific inference rules
- Collects constraints from usage patterns
- Uses `TypeLattice` for meet/join operations
- Invoked by grammar rules during parsing

## Bidirectional Type Inference

### Forward Flow (initializer → variable)
```perl
field $count = 0;     # → $count : Int
```

### Backward Flow (usage → variable)
```perl
$count + 1            # → $count must be numeric
$count . "str"        # → $count must be stringifiable
```

### Algorithm

1. **Collect constraints:** Walk IR, record type requirements at each use site
2. **Unify constraints:** Use type lattice `meet()` to find most specific type
3. **Widen on conflict:** If meet produces Bottom, use `join()` for common supertype
4. **Propagate:** Fixed-point iteration until types stabilize

### Example

```perl
class Example {
    field $data;           # No initializer
    method process() {
        $data + 1;         # Constraint: $data ≥ Num
        $data * 2;         # Constraint: $data ≥ Num
    }
    method display() {
        print $data;       # Constraint: $data ≥ Str (stringify)
    }
}
# Result: meet(Num, Num, Str) = Num (Str is supertype of Num)
# $data inferred as Num, uses Perl's numification for print
```

## Implementation Order

### Phase A: IR Type Infrastructure (#300, #336)
1. Add `type` field to base IR Node class
2. Implement type lattice with Perl-oriented types
3. Inference rules: arithmetic → Int/Num, string ops → Str
4. Chapter 14 narrow types: enable i32/i16/i8 for optimization

### Phase B: Sea of Nodes Completion (#289, #290, #337)
1. Chapter 15 Arrays: typed array access, bounds info
2. Chapter 16 Constructors: object layout with typed fields
3. Chapter 18 Functions: typed parameters and returns

### Phase C: XS Machine Interface (#303)
1. Define `Chalk::CodeGen::XS::Machine` implementing Chapter 19 interface
2. Register allocation strategy (use C locals, not Perl stack)
3. Type-to-C mapping table

### Phase D: XS Code Emission (#304-306)
1. Struct layout: C structs for class fields
2. Boundary code: XSUB wrappers with SV↔C conversion
3. Method bodies: pure C using native types
4. Constructor XSUBs: allocate struct, wrap in SV

## Dependency Graph

```
#300 (types) ──┬──→ #336 (narrow) ──→ #337 (arrays)
               │
               └──→ #289 (constructors) ──→ #290 (functions)
                                                   │
                                                   ↓
                              #291 (Chapter 19) ──→ #303-306 (XS backend)
```

## Related Issues

### Type System (Theme 1)
- #332 - Type System Integration (parent)
- #300 - Type Inference: Infrastructure & Scalar Types
- #336 - Chapter 14: Narrow primitive types
- #366-370 - Field type narrowing, literal tracking, validation, etc.
- #378 - TypeLattice.type_from_name() missing reference types
- #379 - ReferenceConstructor missing infer_type()
- #404 - Type merging in IterPeeps optimizer
- #406 - Move type inference rules to Rule classes

### Sea of Nodes (Theme 2)
- #289 - Chapter 16: Constructors
- #290 - Chapter 18: Functions
- #337 - Chapter 15: Arrays

### XS Backend (Theme 3)
- #291 - Chapter 19: Instruction selection
- #303-306 - XS backend implementation
- #127 - Perl Code Generator

## Success Criteria

1. IR nodes carry type annotations through the pipeline
2. Type inference correctly infers from both initializers and usage
3. XS codegen produces C-native code internally
4. Perl boundary code correctly converts SV↔C types
5. Generated XS compiles and passes tests
6. Performance: typed code faster than generic SV* handling
