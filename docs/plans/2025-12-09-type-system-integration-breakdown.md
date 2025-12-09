# Type System Integration: Issue #332 Breakdown

**Date:** 2025-12-09
**Issue:** #332 - Implement Perl/Chalk Type System Integration
**Strategy:** Feature vertical slices with single-session tickets

## Overview

Issue #332 aims to integrate the Perl/Chalk type system (`Chalk::Grammar::Chalk::Type`) more deeply into the compiler. The Explore agent analysis revealed that **~80% of infrastructure already exists** - the main work is wiring existing components together and implementing type narrowing/tracking.

This document breaks #332 into **6 single-session tickets** using a feature vertical slice approach. Each ticket delivers one complete, testable feature increment.

## Key Findings from Codebase Analysis

### Already Implemented ✅
- Complete Grammar type hierarchy with lattice operations
- TypeRegistry with forward reference support (from #343)
- TypeInference infrastructure bridging Grammar and IR types
- TypeLattice with operation-based type inference
- Builtin function type signatures
- Parser integration for class registration
- Semiring integration for type inference during parsing

### Missing ❌
- Type narrowing from field initializers (`field $count = 0` → Int)
- Literal expression type tracking (`my $x = 42` → Int)
- Operation type preservation (`Int + Int` → Int)
- Comprehensive type validation during compilation
- Grammar → IR type conversion for optimization

## Ticket Breakdown

### Ticket #1: Document Grammar ↔ IR Type System Mapping

**Purpose:** Foundation documentation
**Complexity:** Low

**What it delivers:**
Clear documentation of how `Chalk::Grammar::Chalk::Type` maps to `Chalk::IR::Type`, when to use each system, and how they interact.

**Scope:**
- Create `docs/type-systems.md` documenting:
  - Explicit mapping table (Grammar::Type::Int → IR::Type::Integer, etc.)
  - When to use Grammar types (parsing, validation, semantic analysis)
  - When to use IR types (optimization, constant folding)
  - How TypeInference bridges the two systems
- Add code examples showing both systems in action
- Document existing evidence from codebase (TypeLattice, ValidationContext usage)

**Done criteria:**
- Documentation file exists and is committed
- Includes concrete examples from existing codebase
- Maps all existing Grammar types to IR equivalents (or explains why no mapping exists)
- Explains the "lattice of constants" approach in IR vs "lattice of types" in Grammar

**Why this goes first:** Every other ticket references this mapping. Having it documented prevents confusion and ensures consistency across implementation tickets.

**Dependencies:** None

---

### Ticket #2: Field Initializer Type Narrowing

**Purpose:** Phase 2 implementation
**Complexity:** Medium

**What it delivers:**
Class field types are narrowed from `Any` to specific types based on their initializer values. After this ticket, `field $count = 0;` will have type `Int` in the TypeRegistry.

**Scope:**
- Extend `Chalk::IR::TypeInference` with `narrow_field_types($graph)` method
- Walk IR graph to find FieldStore nodes during class initialization
- Infer type from stored value using existing `infer_type()` infrastructure
- Update TypeRegistry field types (narrow from Any to specific type)
- Handle common cases:
  - Integer literals: `42` → Int
  - Float literals: `3.14` → Num
  - String literals: `"hello"` → Str
  - Array constructors: `[]` → ArrayRef
  - Hash constructors: `{}` → HashRef

**Test coverage:**
- `t/types/field-type-narrowing.t` - Test all literal types in field initializers
- Verify TypeRegistry contains narrowed types after parsing
- Test that uninitialized fields remain `Any`
- Test that multiple classes don't interfere with each other

**Done criteria:**
- All tests pass (100%)
- TypeRegistry reflects actual field types from initializers
- Existing class-registration tests still pass
- Documentation in code explains narrowing algorithm

**Dependencies:** Ticket #1 (type system mapping doc)

**Key files to modify:**
- `lib/Chalk/IR/TypeInference.pm` - Add narrowing method
- `lib/Chalk/Grammar/Chalk/TypeRegistry.pm` - May need `narrow_field_type()` method
- `lib/Chalk/Grammar/Chalk/Type/Class.pm` - May need field type updating

---

### Ticket #3: Literal Expression Type Tracking

**Purpose:** Phase 2 implementation
**Complexity:** Medium

**What it delivers:**
Literal values in expressions get proper Grammar types attached. After this ticket, `my $x = 42` creates a variable with type `Int`, not `Any`.

**Scope:**
- Extend `TypeLattice->infer_type_from_operation()` to handle all literal types
- Update Constant IR node creation to include Grammar type metadata
- Ensure TypeInference can extract types from literals in any context (not just field initializers)
- Handle: Int literals, Float literals, String literals, bareword strings, qw// lists

**Test coverage:**
- `t/types/literal-type-inference.t` - Test literals in various contexts
- Variable declarations with literal initializers
- Function arguments
- Array/hash elements
- Return values

**Done criteria:**
- All tests pass (100%)
- Literals have correct Grammar types in all contexts
- Type information flows through assignments and operations
- No regression in existing type inference tests

**Dependencies:** Ticket #2 (reuses same narrowing mechanisms)

**Key files to modify:**
- `lib/Chalk/Grammar/Chalk/TypeLattice.pm` - Extend `infer_type_from_operation()`
- `lib/Chalk/IR/Node/Constant.pm` - May need Grammar type field
- Potentially parser rules that create Constant nodes

---

### Ticket #4: Operation Type Preservation

**Purpose:** Phase 2 implementation
**Complexity:** Medium-High

**What it delivers:**
Operations preserve and transform types according to Perl semantics. After this ticket, `my $sum = $int1 + $int2` produces type `Int`, and `my $result = $int + $float` produces type `Num`.

**Scope:**
- Extend `TypeLattice->infer_type_from_operation()` to use input types, not just operation name
- Implement Perl type coercion rules:
  - Int + Int → Int
  - Int + Num → Num
  - Int + Str → Num (numeric context)
  - Str . Str → Str (concatenation)
- Handle comparison operators (return Boolean)
- Handle string operators (return Str)
- Handle logical operators (return Boolean)
- Update existing operation type inference to be context-aware

**Test coverage:**
- `t/types/operation-type-preservation.t` - Test type transformations
- Arithmetic operations with mixed types
- String concatenation and manipulation
- Comparison and logical operations
- Verify types flow through complex expressions

**Done criteria:**
- All tests pass (100%)
- Operations produce correct result types based on inputs
- Type lattice operations (meet/join) work correctly for operation results
- No regression in existing arithmetic tests (especially `t/grammar/float-arithmetic.t`)

**Dependencies:** Ticket #3 (needs literal types to test operation type preservation)

**Key files to modify:**
- `lib/Chalk/Grammar/Chalk/TypeLattice.pm` - Context-aware type inference
- May need to update operation IR nodes to track types

**Complexity note:** Requires understanding Perl's type coercion semantics and implementing transformation rules correctly.

---

### Ticket #5: Type Validation During Compilation

**Purpose:** Phase 3 implementation
**Complexity:** Medium

**What it delivers:**
Compiler validates operations against type lattice and rejects invalid type combinations with helpful error messages. After this ticket, trying to use array operations on integers produces compile-time errors.

**Scope:**
- Extend `ValidationContext->validate_type_operation()` to check all operations
- Use TypeLattice to determine operation compatibility
- Generate `CompilationError` with helpful hints for type mismatches
- Validate builtin function calls against signatures from `Chalk::Builtins`
- Handle edge cases where Any type requires runtime checks (can't validate at compile time)

**Test coverage:**
- `t/types/type-validation.t` - Test compilation errors for invalid operations
- Array operations on scalars (should fail)
- Hash operations on arrays (should fail)
- Builtin functions with wrong argument types (should fail)
- Valid operations still work (regression testing)

**Done criteria:**
- All tests pass (100%)
- Invalid operations caught at compile time
- Error messages include helpful hints and expected vs actual types
- Valid code still compiles without warnings
- Existing validation tests still pass

**Dependencies:** Ticket #4 (needs operation type preservation to validate correctly)

**Key files to modify:**
- `lib/Chalk/IR/ValidationContext.pm` - Extend validation
- May need to update error message formatting

---

### Ticket #6: Grammar-to-IR Type Conversion for Optimization

**Purpose:** Phase 4 implementation
**Complexity:** Medium

**What it delivers:**
Grammar types are converted to IR types during IR generation, enabling better constant folding and optimization. After this ticket, knowing a variable is `Int` allows using `IR::Type::Integer` for optimization passes.

**Scope:**
- Implement `TypeConverter->to_ir_type($grammar_type)` conversion method (or add to TypeInference)
- Update IR node creation to use IR types derived from Grammar types
- Ensure constant folding leverages Grammar type information
- Replace ad-hoc type checks in rules (like ArithmeticOp) with systematic conversion

**Test coverage:**
- `t/types/grammar-to-ir-conversion.t` - Test type conversions
- Verify correct IR types generated from Grammar types
- Test that constant folding works better with type information
- Verify optimization passes use converted types

**Done criteria:**
- All tests pass (100%)
- Grammar types convert to appropriate IR types
- IR optimization passes leverage type information
- No regression in existing optimization tests
- Code is cleaner (removes ad-hoc type checking)

**Dependencies:** Ticket #5 (needs validated types to convert)

**Key files to modify:**
- `lib/Chalk/IR/TypeInference.pm` or new `lib/Chalk/IR/TypeConverter.pm`
- Rules that create IR nodes (may need to pass Grammar type info)
- Optimization passes that can leverage type info

---

## Implementation Order

The tickets must be implemented in order due to dependencies:

```
Ticket #1 (Documentation)
    ↓
Ticket #2 (Field Narrowing)
    ↓
Ticket #3 (Literal Types)
    ↓
Ticket #4 (Operation Preservation)
    ↓
Ticket #5 (Type Validation)
    ↓
Ticket #6 (Grammar→IR Conversion)
```

## Success Criteria

After completing all 6 tickets:

1. **Field types are accurate:** `field $count = 0` has type Int in TypeRegistry
2. **Literals are typed:** `my $x = 42` creates Int variable
3. **Operations preserve types:** `Int + Int` → Int, `Int + Num` → Num
4. **Invalid operations fail:** Array operations on scalars caught at compile time
5. **Optimizations work better:** Constant folding leverages type information
6. **All tests pass:** 100% pass rate maintained throughout

## Out of Scope

These remain for future work (not part of the 6 tickets):

- Runtime type validation/enforcement
- Type-based optimizations beyond constant folding
- Type inference for user-defined functions
- Full type checking (this is partial type checking for obvious errors)
- Type annotations in source code (explicit type declarations)

## Related Issues

- #343 - Chapter 13 Session 3 (class registration - already complete)
- #341 - Chapter 13 Session 1 (Class/Maybe types - already complete)
- #342 - Chapter 13 Session 2 (FieldLoad/FieldStore nodes - already complete)
- #331 - SemanticValidation semiring refactor
- #327 - Float type support

## References

- Type lattice design: https://gist.github.com/perigrin/c4780a7511ba1421e49a4a8b385aaa3d
- Current usage: `lib/Chalk/Builtins.pm`, `lib/Chalk/IR/TypeInference.pm`
- Existing type system docs: `docs/type-system.md`
