# Memory Slices and Alias Classes: Chalk's Approach

**Date:** 2025-12-03
**Issue:** #259 - Chapter 10: Implement Memory Slices and Alias Classes
**Status:** Implemented (Adapted to Chalk's Architecture)

## Executive Summary

Chalk implements the **conceptual goals** of Simple's Chapter 10 memory slices using a **label-based approach** that integrates naturally with Chalk's heapless context architecture. Instead of explicit memory edges in the IR graph, Chalk uses **type namespaces in context labels** to prove non-aliasing.

## Background: Simple's Chapter 10

### Simple's Approach
Simple introduces memory slicing for type-based alias analysis (TBAA):

- **Memory slices**: Separate SSA memory values per struct field type
- **Alias classes**: Integer IDs assigned to each field in each struct
- **Memory threading**: Memory types flow through Load/Store as explicit inputs/outputs
- **Optimization**: Independent alias classes enable store-store elimination and load forwarding

### Key Concept
> "Memory in different alias classes never aliases; memory in the same alias class always aliases."

This enables the compiler to prove that operations on different struct fields cannot interfere, allowing aggressive reordering and elimination.

## Chalk's Heapless Architecture

Chalk uses a fundamentally different memory model:

```perl
# Everything is a context closure
my $ctx = sub ($label) {
    return $value if $label eq 'lexical:$x';
    return $parent_ctx->($label);
};

# Collections ARE contexts with namespaced labels
'lexical:@arr'  → ArrayValue(context with 'index:0', 'index:1', ...)
'lexical:%hash' → HashValue(context with 'key:foo', 'key:bar', ...)
```

**No separate heap layer** - collections are nested contexts, not heap-allocated structures.

See `docs/memory-model.md` for full details.

## Adapting Memory Slices to Chalk

### The Core Insight

**In Simple**: Alias classes partition memory into slices
**In Chalk**: Type namespaces partition context labels into non-aliasing sets

These are **semantically equivalent**:

| Simple | Chalk |
|--------|-------|
| Memory slice for alias_class 1 | Context labels with type namespace `Int` |
| Memory slice for alias_class 2 | Context labels with type namespace `Str` |
| Different alias classes don't alias | Different type namespaces can't collide |

### Implementation Strategy

#### 1. Type-Based Context Labels

Extend context labels to include type information:

```perl
# Phase 5 namespace pattern (from memory-model.md)
'lexical:$x'         # Old: untyped label
'lexical:Int:$x'     # New: typed label for integer variable
'lexical:Str:$x'     # New: typed label for string variable (different namespace!)
'lexical:ArrayRef:$x' # New: typed label for array reference
```

**Implementation**: `Chalk::IR::Context->make_typed_label($namespace, $type, $name)`

```perl
use Chalk::IR::Context;

my $int_label = Chalk::IR::Context->make_typed_label('lexical', 'Int', '$x');
# Returns: 'lexical:Int:$x'

my $str_label = Chalk::IR::Context->make_typed_label('lexical', 'Str', '$x');
# Returns: 'lexical:Str:$x'

# These labels are guaranteed to be different!
$int_label ne $str_label  # TRUE
```

#### 2. Memory Type with Alias Classes

The `Memory` type already supports `alias_class` parameter:

```perl
use Chalk::IR::Type::Memory;

# Memory slice for field type 1
my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);

# Memory slice for field type 2
my $mem2 = Chalk::IR::Type::Memory->new(alias_class => 2);

# Different alias classes meet to TOP (no aliasing)
my $result = $mem1->meet($mem2);
$result->is_top();  # TRUE - they don't alias
```

**Lattice operations**:
- `meet()`: Finds most specific (intersection) - different alias classes → TOP
- `join()`: Finds least specific (union) - different alias classes → TOP

#### 3. Field Operations with Alias Classes

`FieldLoad` and `FieldStore` now track alias classes:

```perl
use Chalk::IR::Node::FieldStore;

# Store to field 'x' (alias_class 1)
my $store = Chalk::IR::Node::FieldStore->new(
    inputs => [$object_id, $field_id, $value_id],
    object_id => $object_id,
    field_id => $field_id,
    value_id => $value_id,
    alias_class => 1,  # Field 'x' assigned alias class 1
);

# compute() returns Memory type
my $mem_type = $store->compute($graph);
$mem_type->alias_class;  # Returns: 1
```

**Key properties**:
- Each field gets a unique `alias_class` value
- Same field across instances uses same `alias_class` (can alias)
- Different fields use different `alias_class` (proven non-aliasing)
- Missing `alias_class` defaults to `undef` (MemTOP - conservative)

## Comparison: Simple vs Chalk

### Memory Model

| Aspect | Simple | Chalk |
|--------|--------|-------|
| Architecture | Heap-based with pointers | Heapless context closures |
| Allocation | `New` node creates heap object | `NewObject` allocates heap_id in Environment |
| Field access | Memory × Pointer × Field → Value | heap_id × field → Value via environment lookup |
| Aliasing | Memory slice per alias class | Type namespace per variable type |
| Memory edges | Explicit in IR graph | Implicit in environment state |

### Alias Analysis

| Aspect | Simple | Chalk |
|--------|--------|-------|
| Mechanism | Alias class integers | Type namespaces in labels |
| Assignment | Per struct field type | Per variable/field type |
| Non-aliasing proof | Different alias class IDs | Different label prefixes |
| Representation | Memory type with alias_class | Context label with type component |

### Optimization Opportunities

**Both enable**:
- ✅ Store-store elimination (same field, consecutive stores)
- ✅ Load-after-store forwarding (load immediately after store to same field)
- ✅ Parallel memory access (different fields can't interfere)
- ✅ Dead memory elimination (unused memory slices)

**Chalk-specific advantages**:
- ✅ Label-based analysis works at compile-time (string comparison)
- ✅ No need for separate memory threading (environment handles it)
- ✅ Simpler IR (no memory edges in graph)

## Implementation Files

### Core Infrastructure

1. **`lib/Chalk/IR/Context.pm`**
   - `make_typed_label($namespace, $type, $name)` - Creates type-namespaced labels
   - Returns labels like `'lexical:Int:$x'`

2. **`lib/Chalk/IR/Type/Memory.pm`**
   - `$alias_class` field for memory slice identification
   - `meet()` and `join()` operations for alias analysis
   - TOP/BOTTOM singletons for lattice

3. **`lib/Chalk/IR/Node/FieldLoad.pm`**
   - `$alias_class` field (optional)
   - `compute($graph)` returns `Memory` type with alias_class

4. **`lib/Chalk/IR/Node/FieldStore.pm`**
   - `$alias_class` field (optional)
   - `compute($graph)` returns `Memory` type with alias_class

### Tests

1. **`t/ir-type-based-aliasing.t`** (6 tests)
   - Type-based label creation
   - Namespace isolation
   - Context storage without aliasing

2. **`t/ir-memory-alias-classes.t`** (13 tests)
   - Memory type lattice operations
   - Alias class meet/join semantics
   - Field-level alias tracking

3. **`t/ir-field-alias-classes.t`** (8 tests)
   - Field operation type computation
   - Alias class propagation
   - Non-aliasing verification

4. **`t/interpreter/cek-object-operations.t`** (8 tests, existing)
   - Backward compatibility with untyped operations
   - Execution semantics unchanged

## Usage Example

### Scenario: Point Struct with Two Fields

```perl
# Pseudo-Perl representing the IR
class Point {
    has Int $.x;  # Assigned alias_class 1
    has Int $.y;  # Assigned alias_class 2
}

my $p = Point.new(x => 10, y => 20);
$p.x = 42;  # Store to alias_class 1
$p.y = 99;  # Store to alias_class 2
say $p.x;   # Load from alias_class 1
```

### IR Construction

```perl
use Chalk::IR::Node::NewObject;
use Chalk::IR::Node::FieldStore;
use Chalk::IR::Node::FieldLoad;

# Allocate Point object
my $new_obj = Chalk::IR::Node::NewObject->new(inputs => []);

# Field constants
my $field_x = Constant('x');
my $field_y = Constant('y');
my $val_10 = Constant(10);
my $val_20 = Constant(20);

# Store to x field (alias_class 1)
my $store_x = Chalk::IR::Node::FieldStore->new(
    inputs => [$new_obj->id, $field_x->id, $val_10->id],
    object_id => $new_obj->id,
    field_id => $field_x->id,
    value_id => $val_10->id,
    alias_class => 1,  # Point.x
);

# Store to y field (alias_class 2)
my $store_y = Chalk::IR::Node::FieldStore->new(
    inputs => [$store_x->id, $field_y->id, $val_20->id],
    object_id => $store_x->id,
    field_id => $field_y->id,
    value_id => $val_20->id,
    alias_class => 2,  # Point.y
);

# Load from x field (alias_class 1)
my $load_x = Chalk::IR::Node::FieldLoad->new(
    inputs => [$store_y->id, $field_x->id],
    object_id => $store_y->id,
    field_id => $field_x->id,
    alias_class => 1,  # Point.x
);
```

### Type Computation

```perl
my $store_x_type = $store_x->compute($graph);
# Returns: Memory(alias_class => 1)

my $store_y_type = $store_y->compute($graph);
# Returns: Memory(alias_class => 2)

# Prove non-aliasing
my $meet = $store_x_type->meet($store_y_type);
$meet->is_top();  # TRUE - different fields don't alias
```

### Optimization Enabled

```perl
# Original IR:
#   store_x: Point.x = 10  (alias_class 1)
#   store_y: Point.y = 20  (alias_class 2)
#   load_x: read Point.x   (alias_class 1)

# Optimization: Load-after-store forwarding
# Since load_x has alias_class 1 and store_x has alias_class 1,
# and store_y has alias_class 2 (doesn't interfere),
# we can forward the value 10 directly to load_x.

# Optimized IR:
#   store_x: Point.x = 10  (alias_class 1)
#   store_y: Point.y = 20  (alias_class 2)
#   load_x: ← eliminated, replaced with Constant(10)
```

## Future Work

### Phase 5: Type Namespace Migration

Migrate all context label generation to use typed labels:

```perl
# Current (Phase 4):
my $ctx = extend_context($ctx, 'lexical:$x', $value);

# Future (Phase 5):
my $label = make_typed_label('lexical', 'Int', '$x');
my $ctx = extend_context($ctx, $label, $value);
```

**Benefits**:
- Compile-time non-aliasing proofs via string comparison
- More aggressive constant propagation
- Type-directed optimization passes

### Alias Class Assignment Algorithm

Develop systematic alias class assignment:

```perl
# Strategy 1: Per-field assignment
#   Point.x → 1
#   Point.y → 2
#   Circle.radius → 3
#   Circle.center → 4

# Strategy 2: Per-type assignment (more conservative)
#   All Int fields → 1
#   All Str fields → 2
#   All ArrayRef fields → 3
```

**Trade-offs**:
- Per-field: More precise, more classes
- Per-type: Coarser, fewer classes, simpler

### Peephole Optimizations

Implement memory-aware peepholes:

1. **Store-Store Elimination**
   ```perl
   # Before:
   FieldStore(obj, 'x', 10, alias_class => 1)
   FieldStore(obj, 'x', 20, alias_class => 1)  # Same alias class!

   # After:
   FieldStore(obj, 'x', 20, alias_class => 1)  # First store eliminated
   ```

2. **Load-After-Store Forwarding**
   ```perl
   # Before:
   store = FieldStore(obj, 'x', 42, alias_class => 1)
   load = FieldLoad(obj, 'x', alias_class => 1)  # Same alias class!

   # After:
   store = FieldStore(obj, 'x', 42, alias_class => 1)
   load → Constant(42)  # Load replaced with constant
   ```

3. **Cross-Field Independence**
   ```perl
   # Before (cannot optimize - must check alias classes):
   FieldStore(obj, 'x', 10, alias_class => 1)
   FieldStore(obj, 'y', 20, alias_class => 2)  # Different alias class
   FieldLoad(obj, 'x', alias_class => 1)

   # After (safe to reorder since different alias classes):
   FieldStore(obj, 'x', 10, alias_class => 1)
   FieldLoad(obj, 'x', alias_class => 1)  # Can move past store to y
   FieldStore(obj, 'y', 20, alias_class => 2)
   ```

## Correctness Guarantees

### Type Safety

**Invariant 1**: Labels with different type components cannot collide

```perl
'lexical:Int:$x' ne 'lexical:Str:$x'  # Always TRUE
```

**Proof**: String prefixes guarantee lexical separation.

### Alias Safety

**Invariant 2**: Different alias classes prove non-aliasing

```perl
my $mem1 = Memory(alias_class => 1);
my $mem2 = Memory(alias_class => 2);

$mem1->meet($mem2)->is_top();  # Always TRUE
```

**Proof**: Type lattice meet operation for different alias classes = TOP.

### Execution Semantics

**Invariant 3**: Adding `alias_class` doesn't change execution behavior

```perl
# Without alias_class
FieldStore(obj, field, value)

# With alias_class
FieldStore(obj, field, value, alias_class => 1)

# execute() method ignores alias_class - same runtime behavior
```

**Proof**: `execute()` method doesn't use `alias_class` field (compile-time only).

## Comparison to Simple's Memory Edges

### Simple's Approach: Explicit Memory Threading

```java
// Simplified Java-like IR
Start start = new Start();
Memory mem0 = start.memory();  // Initial memory state

// Store creates new memory state
Store store1 = new Store(mem0, ptr, field, value, ALIAS_1);
Memory mem1 = store1.memory();  // Updated memory

// Load depends on memory state
Load load = new Load(mem1, ptr, field, ALIAS_1);
Memory mem2 = load.memory();

// Return collects all memory slices
Return ret = new Return(ctrl, value, mem2);
```

**Properties**:
- Memory is explicit SSA value
- Stores/Loads are chained via memory edges
- Different alias classes can be parallel (no edge dependency)

### Chalk's Approach: Implicit Environment State

```perl
# Chalk IR
my $start = Start();

# FieldStore doesn't thread memory explicitly
my $store = FieldStore(
    object => $obj,
    field => 'x',
    value => 42,
    alias_class => 1,  # Type metadata only
);

# Environment tracks heap state implicitly
# execute() mutates environment, not memory edges
$env->set_heap($heap_id, 'x', 42);

# FieldLoad reads from environment
my $load = FieldLoad(
    object => $obj,
    field => 'x',
    alias_class => 1,
);
my $value = $env->lookup_heap($heap_id, 'x');
```

**Properties**:
- Memory is implicit in `Environment.heap_ctxs`
- No explicit memory edges in IR graph
- `alias_class` is type metadata for optimization only
- Execution uses environment state, not memory threading

### Why Chalk's Approach Works

**Key insight**: Chalk's heapless architecture makes memory threading unnecessary.

In Simple:
- Heap is separate from IR
- Memory edges track which heap state to use
- Necessary for correctness

In Chalk:
- No separate heap - heap IS context closures
- Environment tracks all state
- Memory edges would be redundant
- `alias_class` provides optimization metadata without changing execution

## Testing Strategy

### Unit Tests
- ✅ `t/ir-type-based-aliasing.t` - Label-based non-aliasing
- ✅ `t/ir-memory-alias-classes.t` - Memory type lattice
- ✅ `t/ir-field-alias-classes.t` - Field operation types

### Integration Tests
- ✅ `t/interpreter/cek-object-operations.t` - Backward compatibility
- 🔲 Peephole optimization tests (future)
- 🔲 End-to-end struct tests with parser (future)

### Property Tests (Future)
```perl
# Property: Different types never alias
for all type1, type2 where type1 != type2:
    label1 = make_typed_label('lexical', type1, '$x')
    label2 = make_typed_label('lexical', type2, '$x')
    assert label1 != label2

# Property: Same type, same name = same label
for all type, name:
    label1 = make_typed_label('lexical', type, name)
    label2 = make_typed_label('lexical', type, name)
    assert label1 == label2

# Property: Different alias classes never alias
for all ac1, ac2 where ac1 != ac2:
    mem1 = Memory(alias_class => ac1)
    mem2 = Memory(alias_class => ac2)
    assert mem1.meet(mem2).is_top()
```

## Conclusion

Chalk implements the **semantic goals** of Simple's Chapter 10 memory slicing using a **label-based approach** that integrates naturally with the heapless context architecture. Instead of explicit memory edges, Chalk uses:

1. **Type namespaces in context labels** (`lexical:Int:$x` vs `lexical:Str:$x`)
2. **Alias classes in field operations** (same field → same class, different fields → different classes)
3. **Memory type lattice** (different classes meet to TOP, proving non-aliasing)

This achieves the same optimization opportunities (store elimination, load forwarding, parallelization) while maintaining Chalk's architectural simplicity.

**Status**: ✅ Core implementation complete, ready for peephole optimization phase.

## References

### Chalk Documentation
- `docs/memory-model.md` - Heapless context architecture
- Issue #259 - Memory slices and alias classes
- Issue #287 - Chapter 10 parent issue

### Simple/Sea of Nodes
- [Simple Chapter 10](https://github.com/SeaOfNodes/Simple/tree/main/chapter10) - Original memory slice design
- Cliff Click's Sea of Nodes papers

### Related Concepts
- Type-Based Alias Analysis (TBAA)
- SSA form and memory effects
- Alias analysis in compilers
