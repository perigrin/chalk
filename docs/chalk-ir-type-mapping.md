# Grammar ↔ IR Type System Mapping

This document explains how the Chalk compiler's type systems interact: **language-specific Grammar type systems** (like `Chalk::Grammar::Chalk::Type`) used for parsing and semantic analysis, and the **universal IR type system** (`Chalk::IR::Type`) used for optimization and constant folding.

## Architecture: Language Frontends → Universal IR

The Chalk compiler uses a **multi-frontend architecture** where each source language has its own Grammar type system that maps to a shared IR:

```
Language-Specific Grammar Types       Language-Agnostic IR Types
────────────────────────────────      ──────────────────────────
Chalk::Grammar::Chalk::Type::*  ─┐
Chalk::Grammar::Perl::Type::*   ─┼─>  Chalk::IR::Type::*
Chalk::Grammar::Raku::Type::*   ─┘
```

**Grammar types are per-language implementations:**
- `Chalk::Grammar::Chalk::Type::*` - Types for the Chalk language (restricted Perl subset)
- `Chalk::Grammar::Perl::Type::*` - Would have full Perl types (DualVar, Glob, etc.) - future
- `Chalk::Grammar::Raku::Type::*` - Would have Raku types (Int, Rat, Junction, etc.) - future

Each language frontend brings its own type semantics and validation rules. All map to the same IR types for language-agnostic optimization.

**This document focuses on:** `Chalk::Grammar::Chalk::Type` ↔ `Chalk::IR::Type` mapping for the Chalk language implementation.

## Quick Reference

### When to Use Each System

**Grammar Types (`Chalk::Grammar::Chalk::Type::*`)**
- ✅ Parsing and semantic analysis
- ✅ Type validation during compilation
- ✅ Builtin function type signatures
- ✅ Class field type declarations
- ✅ Variable type tracking in source code
- ✅ Lattice of **types** (Int, Num, Str, etc.)

**IR Types (`Chalk::IR::Type::*`)**
- ✅ IR optimization passes
- ✅ Constant folding and propagation
- ✅ `compute()` method implementations
- ✅ Sea of Nodes analysis
- ✅ Lattice of **constants** (3, 3.14, "hello") + Top + Bottom

### The Bridge: `Chalk::IR::TypeInference`

`TypeInference` connects the two systems by:
1. Using `TypeLattice` (Grammar system) to infer types from IR operations
2. Returning `Chalk::Grammar::Chalk::Type::*` objects for IR nodes
3. Enabling Grammar-level type validation on IR graphs

```perl
# lib/Chalk/IR/TypeInference.pm:10
field $type_lattice :param :reader;  # Grammar-specific type system
```

## Type System Comparison

### Conceptual Difference

| Aspect | Grammar Types (Chalk) | IR Types (Universal) |
|--------|----------------------|----------------------|
| **Scope** | Language-specific (Chalk language) | Language-agnostic (all frontends) |
| **Purpose** | Classify Chalk values by behavior | Track constant values for optimization |
| **Lattice Model** | Lattice of **types** | Lattice of **constants** |
| **Top Element** | `Any` (all values match) | `Top` (unknown/unanalyzed) |
| **Bottom Element** | `None` (no values match) | `Bottom` (error state, e.g., div-by-zero) |
| **Examples** | Int, Num, Str, ArrayRef | Integer(42), Float(3.14), Top, Bottom |
| **Hierarchy** | Int <: Num <: Str <: Scalar <: Any | IntTop > Int(3) > IntBot; different types don't relate |

### Lattice Operations

Both systems implement `meet()` and `join()` but with different semantics:

**Grammar Types:**
```perl
# Meet = greatest lower bound (intersection)
Int->meet(Num)    # → Int (most specific common type)
Int->meet(Str)    # → Int (Int is subtype of Str)
Array->meet(Hash) # → None (incompatible types)

# Join = least upper bound (union)
Int->join(Num)    # → Num (least general common supertype)
Int->join(Str)    # → Str (Str contains both)
Array->join(Hash) # → List (common supertype)
```

**IR Types:**
```perl
# Meet = intersect constant information
Integer(5)->meet(Integer(5))   # → Integer(5) (same constant)
Integer(5)->meet(Integer(3))   # → IntTop (different constants = unknown)
Integer(5)->meet(Top)          # → Integer(5) (Top is identity)

# Join = merge constant information
Integer(5)->join(IntBot)       # → Integer(5) (IntBot is identity)
Integer(5)->join(Integer(5))   # → Integer(5) (same constant)
Integer(5)->join(Integer(3))   # → IntTop (different constants = unknown)
```

## Type Mapping Table

### Scalar Types

| Grammar Type | IR Type | Notes |
|--------------|---------|-------|
| `Type::Int` | `Type::Integer` | Integers with Int <: Num <: Str subtyping |
| `Type::Num` | `Type::Float` | Numeric values (includes floats) |
| `Type::Str` | `Type::Top`* | No dedicated IR string type; Top represents unknown |
| `Type::Boolean` | `Type::Bool` | True/false values |
| `Type::Undef` | `Type::Bottom`* | Conceptually similar but different purpose |
| `Type::Scalar` | `Type::Top`* | Generic scalar → unknown in IR |
| `Type::Any` | `Type::Top` | Top of both lattices |

\* These mappings are semantic approximations, not direct correspondences.

### Structured Types

| Grammar Type | IR Type | Notes |
|--------------|---------|-------|
| `Type::ArrayRef` | No equivalent | Grammar-level type only |
| `Type::HashRef` | No equivalent | Grammar-level type only |
| `Type::CodeRef` | No equivalent | Grammar-level type only |
| `Type::ScalarRef` | No equivalent | Grammar-level type only |
| `Type::Ref` | No equivalent | Grammar-level type only |
| `Type::Object` | No equivalent | Grammar-level type only; class tracked separately |
| `Type::Class` | No equivalent | Grammar-level type only |
| `Type::Maybe` | No equivalent | Grammar-level type wrapper |

### Special Types

| Grammar Type | IR Type | Notes |
|--------------|---------|-------|
| `Type::None` | `Type::Bottom` | Bottom of lattices, but different meanings |
| `Type::Any` | `Type::Top` | Top of lattices |
| `Type::Coercion` | No equivalent | Grammar-level transformation type |
| `Type::Exception` | No equivalent | Grammar-level error type |

### IR-Specific Types

| IR Type | Grammar Equivalent | Notes |
|---------|-------------------|-------|
| `Type::Ctrl` | No equivalent | Control flow in Sea of Nodes |
| `Type::Memory` | No equivalent | Memory state in Sea of Nodes |
| `Type::MemoryPointer` | No equivalent | Memory addressing |
| `Type::Tuple` | No equivalent | Multiple value returns |

## Usage Examples from Codebase

### Grammar Types in Action

**Type Lattice Operations** (`lib/Chalk/Grammar/Chalk/TypeLattice.pm:86-105`)
```perl
method validate_operation($op, $left_type, $right_type) {
    # Arithmetic operations require numeric types
    if ($op =~ qr/^(Add|Subtract|Multiply|Divide)$/) {
        return $self->_check_numeric_operation($left_type, $right_type);
    }
    # ...
}

method _check_numeric_operation($left_type, $right_type) {
    my $num_type = Chalk::Grammar::Chalk::Type::Num->new();

    my $left_ok = $left_type->is_subtype_of($num_type) ||
                  $num_type->is_compatible_with($left_type);
    # ...
}
```

**Type Inference from Operations** (`lib/Chalk/Grammar/Chalk/TypeLattice.pm:44-61`)
```perl
method infer_type_from_operation($op, $node = undef) {
    # Arithmetic operations return Num
    return Chalk::Grammar::Chalk::Type::Num->new()
        if $op =~ qr/^(Add|Subtract|Multiply|Divide|Negate)$/;

    # Numeric comparison operations return Boolean
    return Chalk::Grammar::Chalk::Type::Boolean->new()
        if $op =~ qr/^(GT|LT|EQ|NE|GE|LE)$/;

    # String operations return Str
    return Chalk::Grammar::Chalk::Type::Str->new() if $op eq 'Concat';
    # ...
}
```

### IR Types in Action

**Integer Type with Constant Lattice** (`lib/Chalk/IR/Type/Integer.pm:33-56`)
```perl
method meet($other) {
    # IntBot absorbs everything within integer domain
    return __PACKAGE__->BOTTOM() if $self->is_bottom;
    return __PACKAGE__->BOTTOM() if $other isa __PACKAGE__ && $other->is_bottom;

    # IntTop is identity for meet within integer domain
    return $other if $self->is_top && $other isa __PACKAGE__;
    return $self if $other isa __PACKAGE__ && $other->is_top;

    # Two constants: same value = that constant, different = IntTop
    if ($self->is_constant && $other isa __PACKAGE__ && $other->is_constant) {
        return $self if $value == $other->value;
        return __PACKAGE__->TOP();  # Different constants = unknown
    }
    # ...
}
```

**Type Widening for Mixed Arithmetic** (`lib/Chalk/IR/Type/Integer.pm:84-98`)
```perl
method widen($other) {
    # If other is a Float type, widen this Integer to Float
    if ($other->isa('Chalk::IR::Type::Float')) {
        use Chalk::IR::Type::Float;
        return Chalk::IR::Type::Float->BOTTOM() if $self->is_bottom;
        return Chalk::IR::Type::Float->TOP() if $self->is_top;
        return Chalk::IR::Type::Float->constant($value + 0.0) if $self->is_constant;
    }
    return $self;
}
```

### The Bridge: TypeInference

**Connecting Grammar Types to IR Nodes** (`lib/Chalk/IR/TypeInference.pm:16-46`)
```perl
method infer_type($node, $depth = 0) {
    return undef unless defined($node);
    my $op = $node->op;

    # Delegate to type lattice for operation-specific inference
    # Returns Chalk::Grammar::Chalk::Type::* objects
    my $type = $type_lattice->infer_type_from_operation($op, $node);
    return $type if defined($type);

    # Special cases that need context/graph analysis
    if ($op eq 'VariableRead') {
        return $self->_infer_type_from_variable_read($node, $depth);
    }
    # ...
}
```

## The Two Lattices Explained

### Grammar Type Lattice: "Lattice of Types"

This is a **subtyping lattice** where types form a hierarchy based on Perl's implicit conversions:

```
                    Any (⊤)
                     |
        ┌───────────┴───────────┐
     Scalar                   List
        |                       |
    ┌───┴───┐               ┌───┴───┐
  Undef    Ref            Array    Hash
           |
      ┌────┴────┐
  ScalarRef   Object

  Str
   |
  Num
   |
  Int
```

**Key properties:**
- `meet(Int, Num)` = Int (most specific)
- `join(Int, Num)` = Num (least general)
- Reflects Perl's implicit conversion rules
- Used for **type checking** ("can this operation accept this type?")

### IR Type Lattice: "Lattice of Constants"

This is a **constant value lattice** where we track specific values or ranges:

```
For integers:
    IntTop (unknown integer)
      |
    ┌─┴─┐
    | ... all possible integer constants ... |
    |  -1  |  0  |  1  |  2  |  3  | ...
    └─┬─┘
      |
   IntBot (error/impossible)

Similarly for FloatTop/FloatBot, and global Top/Bottom
```

**Key properties:**
- `meet(Integer(5), Integer(5))` = Integer(5)
- `meet(Integer(5), Integer(3))` = IntTop (unknown)
- `meet(Integer(5), Top)` = Integer(5)
- Used for **constant folding** ("what's the actual value?")

## Common Patterns

### Pattern 1: Type Validation Using Grammar Types

```perl
use Chalk::Grammar::Chalk::TypeLattice;
use Chalk::IR::TypeInference;

my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
my $inference = Chalk::IR::TypeInference->new(
    type_lattice => $lattice,
    graph => $ir_graph,
);

# Infer Grammar type from IR node
my $node_type = $inference->infer_type($ir_node);

# Validate operation compatibility
my $validation = $lattice->validate_operation('Add', $left_type, $right_type);
die $validation->{error} unless $validation->{valid};
```

### Pattern 2: Constant Folding Using IR Types

```perl
use Chalk::IR::Type::Integer;

# Optimize: if we know both operands are constant integers
my $left_ir_type = Chalk::IR::Type::Integer->constant(5);
my $right_ir_type = Chalk::IR::Type::Integer->constant(3);

# We can fold at compile time
my $result = Chalk::IR::Type::Integer->constant(8);
```

### Pattern 3: Mixed Analysis

```perl
# Start with Grammar type inference
my $grammar_type = $type_lattice->infer_type_from_operation('Add', $node);

# For optimization, check if IR has constant info
if ($node->has_constant_value) {
    my $ir_type = Chalk::IR::Type::Integer->constant($node->constant_value);
    # Use IR type for constant folding
}
```

## No Direct Conversion (Yet)

Currently, **there is no systematic Grammar → IR type conversion**.

The two systems coexist but serve different purposes:
- **Grammar types** validate operations and track source-level types
- **IR types** enable optimization through constant tracking

**Future work** (see #332, Ticket #6) may add:
```perl
method to_ir_type($grammar_type) {
    return Type::Integer->TOP() if $grammar_type isa Grammar::Type::Int;
    return Type::Float->TOP() if $grammar_type isa Grammar::Type::Num;
    return Type::Bool->TOP() if $grammar_type isa Grammar::Type::Boolean;
    # ...
}
```

This would enable using Grammar type information to initialize IR type state for better optimization.

## Why Two Systems?

**Multi-frontend architecture enables language-specific frontends with shared optimization:**

The separation allows the Chalk compiler to:
- **Support multiple source languages** (Chalk, Perl, Raku, etc.) each with their own type systems
- **Share optimization infrastructure** across all language frontends via universal IR types
- **Preserve language semantics** in the frontend while optimizing generically in the backend

**Grammar types (language-specific)** excel at:
- Catching type errors early using language-specific rules
- Validating builtin function signatures per-language
- Tracking source-level type declarations
- Following language-specific subtyping semantics (e.g., Chalk's Int <: Num <: Str)
- Enabling language-specific optimizations (e.g., Perl's context-sensitive operations)

**IR types (language-agnostic)** excel at:
- Constant folding (`2 + 3` → `5`) regardless of source language
- Constant propagation across the IR graph
- Dead code elimination (if condition always true/false)
- Range analysis for bounds checking
- Language-independent peephole optimizations

**They complement each other:**
```perl
# Chalk Grammar type says "this is an Int in Chalk's type system"
my $x = 42;  # Grammar: Chalk::Grammar::Chalk::Type::Int

# Universal IR type says "this is specifically the constant value 42"
# IR: Chalk::IR::Type::Integer->constant(42)

# Language-agnostic optimization: constant fold
my $y = $x + 8;  # IR: Integer->constant(50)
# But Grammar type: still Chalk::Type::Int (type-level, not value-level)
```

This architecture means:
- A future `Chalk::Grammar::Raku::Type` frontend would have completely different types (Int, Rat, Junction)
- But would map to the same `Chalk::IR::Type::*` for optimization
- Allowing code reuse across language implementations

## Implementation Files Reference

### Grammar Type System (Chalk Language)

**Core:**
- `lib/Chalk/Grammar/Chalk/Type.pm` - Base class, lattice operations for Chalk types
- `lib/Chalk/Grammar/Chalk/Type/*.pm` - Individual type implementations (22 Chalk-specific types)
- `lib/Chalk/Grammar/Chalk/TypeLattice.pm` - Type inference and validation for Chalk
- `lib/Chalk/Grammar/Chalk/TypeRegistry.pm` - Class and field type tracking for Chalk

Note: Future language frontends (Perl, Raku) would have their own `Chalk::Grammar::<Lang>::Type::*` hierarchies.

**Tests:**
- `t/semiring/type-lattice-semiring.t` - Lattice law verification
- `t/semiring/type-inference.t` - Integration tests

### IR Type System

**Core:**
- `lib/Chalk/IR/Type.pm` - Base class, lattice operations
- `lib/Chalk/IR/Type/*.pm` - Individual type implementations (9 types)
- `lib/Chalk/IR/TypeInference.pm` - Bridge to Grammar system

**No dedicated tests yet** - IR types tested implicitly through optimization tests.

### Bridging Infrastructure

- `lib/Chalk/IR/TypeInference.pm` - Main bridge
- `lib/Chalk/IR/ValidationContext.pm` - Uses TypeInference for validation
- `lib/Chalk/Builtins.pm` - Uses Grammar types for function signatures

## Further Reading

- [docs/chalk-grammar-types.md](chalk-grammar-types.md) - Chalk's Grammar type system overview
- [Understanding Perl's Type System](https://gist.github.com/perigrin/c4780a7511ba1421e49a4a8b385aaa3d) - Formal foundation
- [docs/plans/2025-12-09-type-system-integration-breakdown.md](plans/2025-12-09-type-system-integration-breakdown.md) - Future integration work

## Related Issues

- #332 - Type System Integration (parent issue)
- #365 - This documentation (Ticket #1)
- #343 - Class registration (complete)
- #341 - Class/Maybe types (complete)
