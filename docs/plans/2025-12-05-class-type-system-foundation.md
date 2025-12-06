# Type System Foundation for Nested Class References

**Date:** 2025-12-05
**Issue:** #341 (Chapter 13 Session 1)
**Author:** Design session with perigrin
**Status:** Approved for implementation

## Overview

This design establishes the type system foundation for nested and recursive struct references in Chalk, following the Sea of Nodes Chapter 13 pattern with Chalk-specific naming conventions.

## Goals

1. Support self-referential class types (linked lists, binary trees)
2. Support mutually recursive class types
3. Handle forward references transparently via lazy resolution
4. Distinguish nullable from non-nullable reference fields
5. Provide foundation for IR node implementation (Session 2) and parser integration (Session 3)

## Architecture Decision: Lazy Resolution

We chose the **Lazy Resolution** approach (Sea of Nodes pattern):
- Register placeholder types on first use
- Fill placeholders when definitions are parsed
- Auto-deepen on field access to resolve stale references

**Alternatives considered:**
- Eager resolution (no forward refs) - too restrictive
- Two-pass resolution - requires significant parse restructuring

## Components

### 1. TypeRegistry

**File:** `lib/Chalk/Grammar/Chalk/TypeRegistry.pm`

**Purpose:** Singleton registry managing the class type namespace.

**Storage:** Hash mapping qualified class names (strings) to Class type instances.

**API:**
```perl
# Register a class type (prevents redefinition of complete classes)
register($name, $class_obj)

# Lookup class type (auto-creates placeholder if not found)
lookup($name)

# Check if class is registered
has_class($name)

# Check if class has complete field definitions
is_complete($name)
```

**Lifecycle:**
1. First reference: `lookup("Node")` auto-creates `Class("Node", fields: undef)`
2. Definition parsed: `register("Node", Class("Node", fields: {...}))` replaces placeholder
3. Field access: Auto-deepening fetches complete definition from registry

**Singleton Access:** `TypeRegistry->instance()`

### 2. Class Type

**File:** `lib/Chalk/Grammar/Chalk/Type/Class.pm`

**Purpose:** Represents instances of user-defined classes.

**Fields:**
```perl
field $class_name :param :reader;  # Qualified identifier as string
field $fields :param :reader;       # Hashref {field_name => Type} or undef
```

**Key Methods:**
```perl
method is_complete() {
    return defined $fields;
}

method field_type($field_name) {
    # Auto-deepening: delegate to registry if incomplete
    unless (defined $fields) {
        my $complete = TypeRegistry->instance->lookup($class_name);
        return $complete->field_type($field_name);
    }
    return $fields->{$field_name} // die "No field $field_name";
}

method has_field($field_name) {
    # Similar auto-deepening pattern
}

method is_subtype_of($other) {
    # Nominal typing:
    # Class("X") <: Class("X") (reflexive)
    # Class("X") <: Object <: Ref <: Scalar <: Any
    # Different classes are incompatible
}
```

**Type Lattice Integration:**
- `Class <: Object <: Ref <: Scalar <: Any`
- Nominal subtyping (no structural subtyping in Session 1)

**Forward References:**
- Incomplete: `Class("Node", fields: undef)` - placeholder
- Complete: `Class("Node", fields: {val => Int, next => Maybe(Class("Node"))})`

### 3. Maybe Type

**File:** `lib/Chalk/Grammar/Chalk/Type/Maybe.pm`

**Purpose:** Wrapper type for nullable references (T or undef).

**Fields:**
```perl
field $inner_type :param :reader;  # The wrapped type
```

**Key Methods:**
```perl
method unwrap() {
    return $inner_type;
}

method is_subtype_of($other) {
    # Maybe(T) <: Maybe(U) if T <: U
    # Maybe(T) <: Undef
}
```

**Usage Example:**
```perl
# Nullable reference field
Class("Node", fields: {
    val => Int,
    next => Maybe(Class("Node"))
})
```

**Note:** `Type?` syntax parser support is deferred to Session 3 (#343).

### 4. Auto-Deepening Mechanism

**Purpose:** Resolve stale forward references when accessing fields on incomplete Class types.

**Implementation:** Built into `Class->field_type()` and similar methods (see Class Type section above).

**Pattern:**
1. Check if Class is complete (`defined $fields`)
2. If incomplete, fetch complete definition from TypeRegistry
3. Delegate operation to complete instance
4. **No mutation** - just delegation (following Sea of Nodes pattern)

**This handles circular references:**
```perl
# During parsing:
# 1. See "Node" reference before definition -> create placeholder
# 2. Parse definition, register complete type
# 3. Field access on old placeholder -> auto-deepen to complete type
```

## Type Lattice Integration

**Existing hierarchy:**
```
Any (top)
├── Scalar
│   ├── Str
│   │   └── Num
│   │       └── Int
│   ├── Boolean
│   ├── Undef
│   └── Ref
│       ├── ScalarRef
│       ├── ArrayRef
│       ├── HashRef
│       ├── CodeRef
│       └── Object  ← We extend here
└── List
    ├── Array
    └── Hash
```

**New types:**
```
Object
└── Class (parameterized by class_name and fields)

Maybe (wrapper type, parameterized by inner_type)
```

**Subtyping examples:**
- `Class("Node") <: Object <: Ref <: Scalar <: Any`
- `Maybe(Class("Node")) <: Maybe(Object)` (if Class <: Object)
- `Maybe(T) <: Undef` (can be undef)

## Testing Strategy

**Test File:** `t/types/class-types.t`

**Coverage Areas:**

1. **TypeRegistry:**
   - Register and lookup complete classes
   - Auto-create placeholders for forward references
   - Replace placeholders with complete definitions
   - Prevent redefinition of complete classes
   - Singleton behavior

2. **Class Type:**
   - Create complete Class with fields
   - Create incomplete Class (placeholder)
   - Field type access on complete classes
   - Auto-deepening on incomplete classes
   - `is_complete()` method
   - Subtyping relationships

3. **Maybe Type:**
   - Wrap types with Maybe
   - Unwrap inner types
   - Subtyping relationships

4. **Integration:**
   - Self-referential classes: linked list, binary tree
   - Mutually recursive classes
   - Forward reference resolution via auto-deepening
   - Complex nested structures

**TDD Workflow:**
- Write failing test defining expected behavior
- Implement minimal code to pass test
- Verify test passes
- Refactor while keeping tests green

## Implementation Order

Following TDD, implement in this order:

1. **TypeRegistry skeleton** - test registration/lookup
2. **Class type (complete only)** - test field access without forward refs
3. **Class placeholders** - test incomplete classes
4. **Auto-deepening** - test forward reference resolution
5. **Maybe type** - test nullable wrapping
6. **Integration tests** - test self-referential and mutually recursive classes

Each step builds on previous foundation.

## Out of Scope (Future Sessions)

- **Session 2 (#342):** IR node extensions (NewNode, LoadNode, StoreNode)
- **Session 3 (#343):** Parser integration (`Type?` syntax, class declarations)
- Structural subtyping (only nominal subtyping in Session 1)
- Class methods or inheritance
- Runtime validation

## Success Criteria

1. ✅ Can define self-referential class types programmatically
2. ✅ Can define mutually recursive class types programmatically
3. ✅ Forward declarations resolve correctly via auto-deepening
4. ✅ Nullable vs non-nullable types are distinguished
5. ✅ All type system tests pass at 100%
6. ✅ Foundation ready for IR node implementation (Session 2)

## References

- Issue #341: Chapter 13 Session 1
- Issue #335: Parent issue (Chapter 13: Nested references)
- Sea of Nodes Chapter 13: https://github.com/SeaOfNodes/Simple (reference implementation)
- Existing Chalk type system: `lib/Chalk/Grammar/Chalk/Type/`
