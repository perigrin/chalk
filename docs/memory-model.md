# Chalk Memory Model: Heapless Context-as-Closure Architecture

**Version:** 3.0 (Implemented)
**Date:** 2025-11-03
**Status:** Implemented (Phases 1-4 Complete)

## Executive Summary

Chalk implements a **heapless** unified memory model where **everything is a context**. There is no separate heap layer - arrays, hashes, and references are all represented as contexts with namespaced labels. This design achieves:

1. **Pure context model**: No heap, no memory states - only context-as-closure
2. **Collections as contexts**: Arrays/hashes ARE contexts with `index:N` and `key:K` namespaces
3. **References as indirection**: References store `(context, label)` pairs for clean aliasing
4. **Immutable + rebind semantics**: Functional purity with SSA-style variable rebinding
5. **100% self-hosting**: Compiles all of `lib/` successfully

## Background

Chalk is a self-hosting Perl compiler using:

- Modern `feature class` syntax exclusively
- Earley parser with composite semiring
- Sea of Nodes IR for optimization
- Type inference based on Perl's operational semantics

The heapless context model serves both:

- **Build-time**: IR construction during semantic actions
- **Runtime**: Threaded interpreter validating IR correctness

## The Core Insight

**Everything is a context. Collections ARE contexts.**

At any point in execution, ALL computational state - variables, arrays, hashes, and references - is represented as closures mapping labels to values:

```perl
my $ctx = sub ($label) {
    return $value_for_label if $label eq 'some:label';
    return $parent_ctx->($label);  # Delegate to parent
};
```

**Key innovation:** Arrays and hashes are not stored "in a heap" and addressed by context - they ARE contexts themselves:

```perl
# Array [1, 2, 3] is represented as:
$array_ctx = sub ($label) {
    return 1 if $label eq 'index:0';
    return 2 if $label eq 'index:1';
    return 3 if $label eq 'index:2';
    return undef;  # No parent for array contexts
};

# Variable @arr points to this array context:
$context = extend_ctx($context, 'lexical:@arr', $array_ctx);
```

## Core Implementation

### Context-as-Closure (`lib/Chalk/IR/Context.pm`)

```perl
class Chalk::IR::Context {
    # Base context - returns undef for any label
    sub empty_context($class) {
        return sub ($label) { return undef };
    }

    # Extend context with new binding
    sub extend_context($class, $parent, $label, $value) {
        return sub ($lookup_label) {
            return $value if $lookup_label eq $label;
            return $parent->($lookup_label);
        };
    }

    # Namespace helpers
    sub make_index_label($class, $index) { "index:$index" }
    sub make_key_label($class, $key) { "key:$key" }
}
```

### Label Namespaces

Labels use prefixes to distinguish different kinds of values:

```perl
'lexical:$x'      # Variable binding
'lexical:@arr'    # Array variable (points to array context)
'lexical:%hash'   # Hash variable (points to hash context)
'index:0'         # Array element at index 0
'index:1'         # Array element at index 1
'key:foo'         # Hash element with key 'foo'
'key:bar'         # Hash element with key 'bar'
```

**Critical distinction:**
- `lexical:@arr` → Points to an array context
- `index:N` → Labels WITHIN that array context

### Collections as Contexts (Phase 3)

Arrays and hashes are contexts with namespaced labels:

```perl
class Chalk::IR::Node::ArrayValue {
    field $array_context :reader;  # The array IS a context

    method context() { $array_context }
}

class Chalk::IR::Node::HashValue {
    field $hash_context :reader;   # The hash IS a context

    method context() { $hash_context }
}
```

**Array operations:**

```perl
# Create array [1, 2, 3]
$arr_ctx = $empty_ctx;
$arr_ctx = extend_ctx($arr_ctx, 'index:0', Constant(1));
$arr_ctx = extend_ctx($arr_ctx, 'index:1', Constant(2));
$arr_ctx = extend_ctx($arr_ctx, 'index:2', Constant(3));

$array_value = ArrayValue($arr_ctx);

# Bind to variable
$context = extend_ctx($context, 'lexical:@arr', $array_value);

# Access element: $arr[1]
$array = $context->('lexical:@arr');     # Get ArrayValue
$elem = $array->context->('index:1');    # Look up in array's context
# Returns: Constant(2)

# Mutate element: $arr[1] = 99 (immutable + rebind)
$old_arr_ctx = $array->context;
$new_arr_ctx = extend_ctx($old_arr_ctx, 'index:1', Constant(99));
$new_array = ArrayValue($new_arr_ctx);
$context = extend_ctx($context, 'lexical:@arr', $new_array);
```

**Hash operations** work identically with `key:K` labels instead of `index:N`.

### References with Label Indirection (Phase 4)

References store `(context, label)` pairs - direct links without heap indirection:

```perl
class Chalk::IR::Node::Reference {
    field $target_context :reader;  # Which context to look in
    field $target_label :reader;    # Which label to look up
}
```

**Creating references:**

```perl
# Scalar reference: \$x
$ref = Reference(
    target_context => $context,
    target_label => 'lexical:$x'
);

# Array element reference: \$arr[1]
$array = $context->('lexical:@arr');
$ref = Reference(
    target_context => $array->context,
    target_label => 'index:1'
);
```

**Dereferencing:**

```perl
class Chalk::IR::Node::ScalarDeref {
    method eval($ref) {
        # Follow the (context, label) indirection
        return $ref->target_context->($ref->target_label);
    }
}
```

**Mutation through references:**

```perl
# $$ref = 99
$old_value = $ref->target_context->($ref->target_label);
$new_ctx = extend_ctx(
    $ref->target_context,
    $ref->target_label,
    Constant(99)
);

# If reference points into an array, update the array:
if ($ref->target_label =~ /^index:/) {
    $new_array = ArrayValue($new_ctx);
    $context = extend_ctx($context, 'lexical:@arr', $new_array);
}
```

**This enables:**
- ✅ Scalar references (`\$x`)
- ✅ Element references (`\$arr[1]`, `\$hash{key}`)
- ✅ Reference aliasing (multiple refs to same element)
- ✅ Mutation through references
- ✅ Multi-level references (`\\\$x`)

## Complete Example: Array with References

```perl
# Source:
my @arr = (1, 2, 3);
my $ref = \$arr[1];
$$ref = 99;
say $arr[1];  # 99

# Implementation:

# Step 1: Create array context
$arr_ctx = empty_context();
$arr_ctx = extend_ctx($arr_ctx, 'index:0', Constant(1));
$arr_ctx = extend_ctx($arr_ctx, 'index:1', Constant(2));
$arr_ctx = extend_ctx($arr_ctx, 'index:2', Constant(3));

# Step 2: Wrap in ArrayValue and bind to variable
$array_val = ArrayValue($arr_ctx);
$context = extend_ctx($empty_context(), 'lexical:@arr', $array_val);

# Step 3: Create reference to $arr[1]
$ref = Reference(
    target_context => $array_val->context,
    target_label => 'index:1'
);
$context = extend_ctx($context, 'lexical:$ref', $ref);

# Step 4: Dereference and mutate
$old_value = $ref->target_context->($ref->target_label);  # 2
$new_arr_ctx = extend_ctx($arr_ctx, 'index:1', Constant(99));
$new_array = ArrayValue($new_arr_ctx);
$context = extend_ctx($context, 'lexical:@arr', $new_array);

# Step 5: Access element
$array = $context->('lexical:@arr');
$value = $array->context->('index:1');  # 99
```

## Why Heapless?

**Traditional approach (with heap):**
```perl
# Context points to heap IDs
$context->('var:@arr') = 'heap:1'
$heap->('heap:1') = [1, 2, 3]

# Two lookups for array access:
$array_id = $context->('var:@arr');     # Context lookup
$array = $heap->($array_id);            # Heap lookup
$elem = $array->[1];
```

**Heapless approach:**
```perl
# Context points directly to array context
$context->('lexical:@arr') = ArrayValue($arr_ctx)

# Single lookup chain:
$array = $context->('lexical:@arr');    # Get ArrayValue
$elem = $array->context->('index:1');   # Look up in array context
```

**Benefits:**
1. **Simpler**: One abstraction for everything
2. **Faster**: Fewer indirections
3. **Cleaner aliasing**: References are `(context, label)` pairs
4. **Unified semantics**: Variables, arrays, hashes all use same mechanism

## Immutable + Rebind Semantics

All operations create new contexts; variables rebind to new values:

```perl
# Mutation is really extension + rebinding
$arr[0] = 99;

# Becomes:
$old_array = $context->('lexical:@arr');
$new_arr_ctx = extend_ctx($old_array->context, 'index:0', Constant(99));
$new_array = ArrayValue($new_arr_ctx);
$context = extend_ctx($context, 'lexical:@arr', $new_array);
```

**Properties:**
- ✅ Immutable data structures (functional purity)
- ✅ SSA-style variable rebinding
- ✅ Time-travel debugging possible (keep old contexts)
- ✅ No aliasing confusion (old context unchanged)

## Implementation Status

### ✅ Phase 1: Context Infrastructure (Complete)

- `Chalk::IR::Context` with `empty_context()` and `extend_context()`
- Context threading through interpreter
- Builder migrated from Scope to Context
- Tests: `t/ir-context-basic.t`, `t/ir-builder-{load,store}.t`

### ✅ Phase 2: Builder Migration (Complete)

- `lexical:` namespace for variables
- Context stores IR nodes directly (not node IDs)
- All operations thread context correctly
- 100% self-hosting achieved (125/125 lib files parse)

### ✅ Phase 3: Collections as Contexts (Complete)

**Files:**
- `lib/Chalk/IR/Node/ArrayValue.pm` - Array wraps context
- `lib/Chalk/IR/Node/HashValue.pm` - Hash wraps context
- `lib/Chalk/IR/Node/ArrayGet.pm` - Element access via context lookup
- `lib/Chalk/IR/Node/ArraySet.pm` - Element mutation via context extension
- `lib/Chalk/IR/Node/HashGet.pm` - Hash element access
- `lib/Chalk/IR/Node/HashSet.pm` - Hash element mutation

**Tests:**
- `t/sea-of-nodes/collections-as-contexts.t` (3 tests)
- `t/sea-of-nodes/array-support.t`

**Semantics:**
- Arrays ARE contexts with `index:N` bindings
- Hashes ARE contexts with `key:K` bindings
- Element access: `array->context->('index:1')`
- Element mutation: Creates new array context

### ✅ Phase 4: References with Label Indirection (Complete)

**Files:**
- `lib/Chalk/IR/Node/Reference.pm` - Stores `(context, label)` pair
- `lib/Chalk/IR/Node/ScalarDeref.pm` - Dereferences via context lookup
- `lib/Chalk/IR/Node/VariableRead.pm` - Helper for variable access

**Tests:**
- `t/sea-of-nodes/references.t` (4 tests)

**Semantics:**
- Scalar refs: `\$x` → `Reference($context, 'lexical:$x')`
- Element refs: `\$arr[1]` → `Reference($array_ctx, 'index:1')`
- Dereferencing: `$$ref` → `$ref->context->($ref->label)`
- Mutation: Extends context and rebinds variable

## Phase 5: Memory Slices and Alias Classes (Complete)

**Status:** ✅ Implemented (Issue #259, #310)
**Date:** 2025-12-03

### Overview

Chalk implements type-based alias analysis (TBAA) using **alias classes** to prove that memory operations on different fields cannot interfere with each other. This enables aggressive memory optimizations while maintaining correctness.

### Alias Classes

Each field in a struct is assigned a unique `alias_class` integer:

```perl
# Point struct with two fields
class Point {
    has Int $.x;  # alias_class 1
    has Int $.y;  # alias_class 2
}
```

**Key Properties:**
- Same field across instances → same alias_class (can alias)
- Different fields → different alias_class (proven non-aliasing)
- Missing alias_class → `undef` (conservative, may alias)

### Memory Type

The `Memory` type carries alias class information through the type system:

```perl
use Chalk::IR::Type::Memory;

my $mem1 = Chalk::IR::Type::Memory->new(alias_class => 1);
my $mem2 = Chalk::IR::Type::Memory->new(alias_class => 2);

# Different alias classes meet to TOP (no aliasing)
my $result = $mem1->meet($mem2);
$result->is_top();  # TRUE - they don't alias
```

### Field Operations with Alias Classes

FieldStore and FieldLoad now track alias classes:

```perl
# Store to field 'x' (alias_class 1)
my $store = Chalk::IR::Node::FieldStore->new(
    inputs => [$mem_id, $object_id, $field_id, $value_id],
    mem_id => $mem_id,           # Memory dependency (NEW)
    object_id => $object_id,
    field_id => $field_id,
    value_id => $value_id,
    alias_class => 1,            # Field 'x' alias class
);
```

### Type-Based Non-Aliasing

Alias classes enable compile-time proofs of non-interference:

```perl
# These operations are proven independent:
FieldStore(obj, 'x', 10, alias_class => 1)  # Point.x
FieldStore(obj, 'y', 20, alias_class => 2)  # Point.y
FieldLoad(obj, 'x', alias_class => 1)       # Can't see y's store

# Compiler can reorder these safely - different alias classes!
```

## Phase 6: Memory Edges and Peephole Optimizations (Complete)

**Status:** ✅ Implemented (Issue #262, #311)
**Date:** 2025-12-03

### Overview

Memory edges make memory dependencies explicit in the IR graph, enabling peephole optimizations from Simple's Chapter 10. This addition **does not conflict** with Chalk's heapless architecture.

### Memory Edges Architecture

Following the Phi node pattern, FieldStore and FieldLoad have `mem_id`:

```perl
class Chalk::IR::Node::FieldStore {
    field $mem_id :param :reader = undef;  # Previous memory state
    field $object_id :param :reader;
    field $field_id :param :reader;
    field $value_id :param :reader;
    field $alias_class :param :reader = undef;

    # inputs: [$mem_id, $object_id, $field_id, $value_id]
    #          ^^^^^^^^
    #          Memory edge is BOTH a field AND in inputs!
}
```

**Why this works:**
- **Field** (`$mem_id`) - Easy access in peephole methods
- **In inputs** - Graph dependency tracking (use-def, DCE)
- **Same pattern as Phi** - Proven design in our codebase

### Heapless + Memory Edges

Memory edges **complement** the heapless architecture, they don't conflict:

| Aspect | Heapless Architecture | Memory Edges |
|--------|----------------------|--------------|
| **Purpose** | Execution model | IR dependencies |
| **Level** | Runtime | Compile-time |
| **What** | No separate heap data structure | Explicit dependency graph |
| **Why** | Simpler execution semantics | Enable optimizations |

**Key insight:** Memory edges track **compile-time dependencies** in the IR graph. The heapless model describes **runtime execution** (Environment-based). These are orthogonal concerns.

### Memory Peephole Optimizations

Three optimizations leverage memory edges and alias classes:

#### 1. Store-to-Store Elimination

When two stores write to the same field with no intervening read:

```perl
# Before optimization:
store1: obj.x = 10  (alias_class 1)
store2: obj.x = 20  (alias_class 1, mem_id => store1)

# After peephole:
store2: obj.x = 20  (mem_id => store1->mem_id)
# store1 is dead and can be eliminated by DCE
```

**Implementation:**
```perl
method peephole($graph) {
    my $prev_mem = $graph->get_node($mem_id);

    if ($prev_mem->isa('FieldStore') &&
        $prev_mem->alias_class == $alias_class &&
        scalar($graph->get_uses($prev_mem->id)->@*) == 1) {
        # Bypass intermediate store
        return FieldStore->new(..., mem_id => $prev_mem->mem_id);
    }
}
```

#### 2. Load-after-Store Forwarding

When a load reads from a just-written location:

```perl
# Before optimization:
store: obj.x = 42  (alias_class 1)
load:  y = obj.x   (alias_class 1, mem_id => store)

# After peephole:
load → Constant(42)  # Forward the stored value
```

**Implementation:**
```perl
method peephole($graph) {
    my $prev_mem = $graph->get_node($mem_id);

    if ($prev_mem->isa('FieldStore') &&
        $prev_mem->alias_class == $alias_class) {
        # Forward stored value
        return $graph->get_node($prev_mem->value_id);
    }
}
```

#### 3. Store-after-Load Elimination

When storing a value that was just loaded:

```perl
# Before optimization:
load:  y = obj.x      (alias_class 1)
store: obj.x = y      (alias_class 1, mem_id => load, value => load)

# After peephole:
store → load  # Redundant store eliminated
```

**Implementation:**
```perl
method peephole($graph) {
    my $prev_mem = $graph->get_node($mem_id);

    if ($prev_mem->isa('FieldLoad') &&
        $prev_mem->alias_class == $alias_class &&
        $value_id == $prev_mem->id) {
        # Store is redundant
        return $prev_mem;
    }
}
```

### Optimization Correctness

These optimizations are safe because:

1. **Alias classes prove non-interference:** Different fields can't alias
2. **Memory edges track dependencies:** We know execution order
3. **Use-def chains verify safety:** Check if intermediate results are used elsewhere
4. **Heapless execution unchanged:** Optimizations are compile-time transformations

### Performance Impact

Memory peepholes enable:
- ✅ Dead store elimination (store never read)
- ✅ Redundant load elimination (value already in register)
- ✅ Memory access reduction (fewer reads/writes)
- ✅ Better instruction scheduling (proven independent operations)

## Future Work

### Phase 7: ECA Type Namespaces (Next)

Use type-specific lexical labels to prove non-aliasing:

```perl
# Instead of: 'lexical:$x'
# Use:        'lexical:Int:$x'

# Different types can't alias:
'lexical:Int:$x'      # Integer value
'lexical:Str:$x'      # Different variable (type namespace)
'lexical:ArrayRef:$x' # Different variable (type namespace)
```

**Benefits:**
- Prove non-aliasing via namespace separation
- Enable more aggressive optimizations
- Type-directed memory layout decisions

### Phase 6: Optimization Passes

- **Escape analysis**: Identify contexts that don't escape
- **Constant propagation**: Inline constant label lookups
- **Dead context elimination**: Remove unused context extensions
- **Context compaction**: Flatten deep closure chains

### Phase 7: Advanced Features

- **Tie support**: Method dispatch on context lookups
- **Autovivification**: Lazy context creation for nested structures
- **Weak references**: GC support for circular structures

## Performance Considerations

### Self-Hosting Optimization

When Chalk compiles itself, constant label lookups inline completely:

```perl
# Source:
my $value = $ctx->('lexical:$x');

# After Chalk inlines (if label is constant):
my $value = ('lexical:$x' eq 'lexical:$x') ? 42 : $parent_ctx->('lexical:$x');

# After constant folding:
my $value = 42;
```

This works because:
- Closure inlining is standard optimization
- String comparisons with constants fold away
- Deep closure chains optimize to direct access

### Context Allocation

**Concern:** Creating new closures for every operation?

**Reality:**
- Modern Perl closure creation is fast
- Immutable contexts enable structural sharing
- Context chains are typically shallow (3-5 levels)
- Self-hosting optimization eliminates most allocations

**Measurement needed:**
- Benchmark closure allocation overhead
- Profile context chain depth in real code
- Compare vs. mutable hash performance

### Memory Usage

Functional contexts use more memory than mutable hashes:
- More allocations
- More GC pressure
- But: immutability enables sharing
- And: correctness > raw speed for bootstrap

**Future optimizations:**
- Persistent data structures (structural sharing)
- Periodic context compaction
- Weak references for old contexts

## Testing Strategy

### Unit Tests

```perl
# Test context operations
{
    my $ctx1 = extend_ctx($empty_ctx, 'x', 42);
    is($ctx1->('x'), 42, 'lookup works');

    my $ctx2 = extend_ctx($ctx1, 'y', 100);
    is($ctx2->('x'), 42, 'parent accessible');
    is($ctx2->('y'), 100, 'new binding accessible');
}

# Test collections as contexts
{
    my $arr_ctx = $empty_ctx;
    $arr_ctx = extend_ctx($arr_ctx, 'index:0', 1);
    $arr_ctx = extend_ctx($arr_ctx, 'index:1', 2);

    my $array = ArrayValue($arr_ctx);
    is($array->context->('index:0'), 1, 'array element 0');
    is($array->context->('index:1'), 2, 'array element 1');
}

# Test references
{
    my $ctx = extend_ctx($empty_ctx, 'lexical:$x', 42);
    my $ref = Reference($ctx, 'lexical:$x');

    is($ref->target_context->($ref->target_label), 42, 'deref works');
}
```

### Integration Tests

```perl
# Test self-hosting
{
    my @pm_files = find_lib_files();
    for my $file (@pm_files) {
        my $result = parse_with_chalk($file);
        ok($result, "$file parses with Chalk");
    }
}
```

**Current status:** 125/125 files parse (100%)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      Context (Closure)                      │
│                                                             │
│  'lexical:$x'    → 42                                      │
│  'lexical:@arr'  → ArrayValue ──→ Array Context            │
│  'lexical:%hash' → HashValue ──→ Hash Context              │
│  'lexical:$ref'  → Reference(ctx, label)                   │
│                                                             │
│  Array Context (nested closure):                            │
│    'index:0' → 1                                           │
│    'index:1' → 2                                           │
│    'index:2' → 3                                           │
│                                                             │
│  Hash Context (nested closure):                             │
│    'key:foo' → "bar"                                       │
│    'key:baz' → "qux"                                       │
└─────────────────────────────────────────────────────────────┘
```

**Key insight:** No separate heap layer. Collections ARE contexts nested within the main context.

## Comparison to Original Design

**Original memory-model.md:**
- Context points to heap IDs
- Heap stores actual structures
- Two-layer architecture

**Implemented heapless model:**
- Context points directly to collection contexts
- No separate heap
- Single-layer architecture

**Why the change:**
- Simpler implementation
- Fewer indirections
- Cleaner reference semantics
- Same optimization opportunities

## References

### Internal Documents
- Chalk Grammar (BNF files)
- Type System Formalization (`docs/perl-types-practical.md`)
- Composite Semiring Design
- Sea of Nodes Tutorial

### External References
- Cliff Click: "Sea of Nodes" optimization papers
- LLVM documentation on SSA form
- "LAMBDA: The Ultimate Imperative" (Steele & Sussman, 1976)
- John Shutt: Kernel language design (fexprs and environments)
- NXCL: Scopes-as-functions implementation

### Related Projects
- PyPy/RPython: Restricted Python for self-hosting
- Truffle/Graal: Self-optimizing AST interpreters
- NXCL: Pure functional scope representation

## Glossary

**Context:** A closure that maps labels to values, representing all computational state

**Label:** A string identifier for context lookups (e.g., `'lexical:$x'`, `'index:0'`)

**Context Extension:** Creating a new closure that adds bindings while preserving parent

**Context Threading:** Passing context through operations, each extending it

**Heapless:** No separate heap layer; collections ARE contexts themselves

**Collections-as-Contexts:** Arrays/hashes implemented as nested contexts with namespaced labels

**Reference:** A `(context, label)` pair enabling aliasing and mutation

**Immutable + Rebind:** Functional purity with SSA-style variable rebinding

**Alias Class:** Integer identifier for a field type, enabling type-based alias analysis (TBAA)

**Memory Edge:** Explicit IR dependency linking a memory operation to its predecessor

**Memory Slice:** Partitioning of memory into non-aliasing regions based on alias classes

**Peephole Optimization:** Local IR transformation that eliminates redundant operations

---

**Document Status:** Reflects actual implementation (Phases 1-6 complete, 100% self-hosting achieved). This heapless architecture with memory slices and edges is simpler and more elegant than the original two-layer design while enabling advanced memory optimizations.
