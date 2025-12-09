# Chalk Grammar Type System

This document describes the **language-specific Grammar type system** for the **Chalk language** - a restricted Perl subset. This is part of the Chalk compiler's multi-frontend architecture where each source language has its own Grammar type system.

## Language-Specific Types

**Important:** These types are specific to the Chalk language implementation (`Chalk::Grammar::Chalk::Type::*`). Future language frontends would have their own type hierarchies:
- `Chalk::Grammar::Perl::Type::*` - Full Perl types (DualVar, Glob, etc.)
- `Chalk::Grammar::Raku::Type::*` - Raku types (Int, Rat, Junction, etc.)

All language-specific Grammar types map to the same universal IR types (`Chalk::IR::Type::*`) for language-agnostic optimization. See [docs/chalk-ir-type-mapping.md](chalk-ir-type-mapping.md) for details on how Grammar and IR type systems interact.

## Overview

Chalk's type system is based on a formal characterization of Perl 5's types, combining two tests for type membership:

1. **Syntactic Preservation**: Can a value survive conversion to the type and back without losing information?
2. **Semantic Fulfillment**: Does the value satisfy all operational contracts for that type?

Both conditions must hold for true type membership. For complete formal treatment, see [Understanding Perl's Type System](https://gist.github.com/perigrin/c4780a7511ba1421e49a4a8b385aaa3d).

## Type Hierarchy

Chalk implements the following type lattice:

```
Any (⊤ - top type, all values)
├── Scalar (single values)
│   ├── Undef (undefined value)
│   ├── Bool (true/false)
│   ├── Str (strings)
│   │   └── Num (numeric values)
│   │       └── Int (integers)
│   ├── DualVar (errno-like values with independent string/numeric forms)
│   └── Ref (references)
│       ├── ScalarRef
│       ├── ArrayRef
│       ├── HashRef
│       ├── CodeRef
│       ├── GlobRef
│       └── Object
├── List (sequences - not yet fully implemented)
│   ├── Array
│   └── Hash
├── Code (subroutines)
├── Glob (symbol table entries)
├── Regex (compiled patterns)
└── None (⊥ - bottom type, no values)
```

### Critical Subtype Relationships

**Int <: Num <: Str <: Scalar**

This is Perl's fundamental subtyping chain. Every integer is also a number, every number is also a string (via stringification), and all are scalars.

**Why this matters for Chalk:**
- Type inference during parsing follows this hierarchy
- Meet operations (∧) select the more specific type: `Int ∧ Num = Int`
- Join operations (∨) select the less specific type: `Int ∨ Num = Num`

## Implementation Files

### Core Type System
- `lib/Chalk/Grammar/Chalk/TypeLattice.pm` - Lattice operations (meet, join, subtyping)
- `lib/Chalk/Grammar/Chalk/Type.pm` - Base type class
- `lib/Chalk/Grammar/Chalk/Type/*.pm` - Individual type implementations

### Semiring Integration
- `lib/Chalk/Semiring/TypeInference.pm` - Tropical semiring for type inference
- `lib/Chalk/Semiring/TypeInferenceElement.pm` - Element class with meet/join

### Parser Integration
- `lib/Chalk/Parser.pm` - Earley parser with semiring hooks
- `lib/Chalk/Grammar/Token.pm` - Token types (Int, Float, Operator)

### Tests
- `t/semiring/type-lattice-semiring.t` - Lattice law tests
- `t/semiring/type-inference.t` - Integration tests with parsing
- `t/semiring/earley-type-integration.t` - Earley-specific type propagation tests

## References

- [Understanding Perl's Type System (Gist)](https://gist.github.com/perigrin/c4780a7511ba1421e49a4a8b385aaa3d) - Complete formal and practical treatment
- Issue #350 - Parent issue for lattice-based type inference
- Issue #352 - TypeInference semiring implementation
- Issue #353 - Earley integration
