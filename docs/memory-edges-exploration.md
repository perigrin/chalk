# Memory Edges: Design Space Exploration

**Date:** 2025-12-03
**Context:** Issue #262 - Implementing memory peephole optimizations
**Question:** Should Chalk add explicit memory edges to support peephole optimizations?

## Current State

### What We Have
- **Alias classes**: Fields are tagged with `alias_class` integers
- **Type-based aliasing**: Different alias classes prove non-aliasing
- **No memory edges**: `FieldStore/FieldLoad` inputs don't include memory dependencies

### Current FieldStore Inputs
```perl
my $store = Chalk::IR::Node::FieldStore->new(
    inputs => [$object_id, $field_id, $value_id],
    object_id => $object_id,
    field_id => $field_id,
    value_id => $value_id,
    alias_class => 1,
);
```

**Inputs represent:**
1. `$object_id` - which object to store into
2. `$field_id` - which field name
3. `$value_id` - what value to store

**NOT included:** Previous memory state

## Simple's Approach

### StoreNode Inputs
```java
public StoreNode(String name, int alias, Node memSlice, Node memPtr, Node value)
```

**Inputs represent:**
1. `memSlice` - previous memory state for this alias class
2. `memPtr` - pointer to object
3. `value` - value to store

### How Peepholes Work
```java
// Store-to-Store elimination
if( mem() instanceof StoreNode st &&  // Check if previous memory is a store
    ptr()==st.ptr() &&                // Same object?
    ptr()._type instanceof TypeMemPtr &&
    st.checkNoUseBeyond(this) ) {     // No other uses of intermediate store?
    setDef(1,st.mem());               // Bypass the intermediate store
    return this;
}
```

**Key capability:** Can directly inspect previous memory state via `mem()`.

## The Problem

For Chalk to implement these peepholes, we need to answer: **How does a FieldStore find the previous FieldStore to the same field?**

### Option 1: Add Memory Edges (Simple's Way)

**Change inputs to:**
```perl
my $store2 = Chalk::IR::Node::FieldStore->new(
    inputs => [$store1->id, $object_id, $field_id, $value_id],
    # NEW: ^-- previous memory state for this alias class
    mem_id => $store1->id,      # NEW field
    object_id => $object_id,
    field_id => $field_id,
    value_id => $value_id,
    alias_class => 1,
);
```

**Peephole implementation:**
```perl
method idealize($graph) {
    # Get previous memory state
    my $prev_mem = $graph->get_node($mem_id);
    return unless $prev_mem;

    # Is it a FieldStore to the same field?
    if ($prev_mem->isa('Chalk::IR::Node::FieldStore') &&
        $prev_mem->object_id == $object_id &&
        $prev_mem->alias_class == $alias_class &&
        scalar($graph->get_uses($prev_mem->id)->@*) == 1) {
        # Bypass the intermediate store
        return Chalk::IR::Node::FieldStore->new(
            inputs => [$prev_mem->mem_id, $object_id, $field_id, $value_id],
            mem_id => $prev_mem->mem_id,
            object_id => $object_id,
            field_id => $field_id,
            value_id => $value_id,
            alias_class => $alias_class,
        );
    }
    return;
}
```

**Pros:**
- Direct translation of Simple's proven design
- Clear, efficient peephole implementation
- Explicit dependency tracking in IR
- Matches Sea of Nodes literature

**Cons:**
- Goes against Chalk's "implicit memory" philosophy
- Adds complexity to IR construction
- May feel redundant with Environment-based execution model
- Requires threading memory through all field operations

### Option 2: Search for Previous Store (No Memory Edges)

**Keep current inputs, search backward:**
```perl
method idealize($graph) {
    # Find all FieldStores that could be predecessors
    # How? Walk the graph backward from this node's object_id?
    # Problem: Multiple paths, unclear which store is "immediately before"

    # Sketch:
    # 1. Get all nodes in the graph
    # 2. Find FieldStores with same object_id and alias_class
    # 3. Check if any dominates this one in execution order?
    # 4. Check if no other stores/loads between them?

    # This is MUCH more complex and potentially expensive
}
```

**Pros:**
- Keeps current IR structure
- Maintains "implicit memory" model

**Cons:**
- Complex and potentially expensive search
- May not be efficient for large graphs
- Unclear how to determine "immediately previous" store
- May miss optimization opportunities
- Doesn't scale well

### Option 3: Hybrid - Memory Edges Only for Peepholes

**Add memory edges during peephole optimization pass:**
```perl
# During IR construction: no memory edges (current state)
my $store = Chalk::IR::Node::FieldStore->new(
    inputs => [$object_id, $field_id, $value_id],
    ...
);

# Before peephole optimization: add memory edges
sub add_memory_edges($graph) {
    # Build memory dependency chains by analyzing data flow
    # This is like a pre-pass that reconstructs memory edges
}
```

**Pros:**
- IR construction stays simple
- Peepholes get the edges they need
- Separates concerns

**Cons:**
- Complexity in two places instead of one
- Extra pass required
- Memory edge reconstruction might be expensive
- Still need to solve "which store comes before" problem

### Option 4: Different Optimization Strategy

**Accept that Chalk's model is fundamentally different:**
- These specific peepholes (Store-Store, Load-after-Store) might not be as important in Chalk
- Environment-based execution might make these optimizations less critical
- Focus on other optimization opportunities that fit Chalk's model better

**Pros:**
- Embraces Chalk's unique architecture
- No IR changes needed
- Simpler implementation

**Cons:**
- Miss proven optimizations from Simple
- May leave performance on the table
- Deviates from Sea of Nodes research

## Questions for Discussion

1. **Philosophical:** Is "implicit memory in Environment" a core principle we want to preserve, or was it more about simplifying initial implementation?

2. **Practical:** Would adding memory edges make Chalk's IR significantly more complex to work with? Or is it just a few extra fields?

3. **Performance:** Are these memory peepholes critical for performance, or are they "nice to have"?

4. **Consistency:** If we add memory edges for FieldStore/FieldLoad, should other stateful operations (like future I/O nodes) also have them?

5. **Testing:** How would we test memory edge correctness if we add them?

## Recommendation

After studying Chalk's architecture more deeply (especially Phi nodes), I now see: **Option 1 (Add Memory Edges) fits naturally into our existing design**.

### Key Insight: Phi Nodes Already Do This

```perl
class Chalk::IR::Node::Phi {
    field $region_id :param :reader;  # Field for easy access

    # inputs array: [$region_id, $value1, $value2, ...]
    #                 ^^^^^^^^^^
    #                 Region is BOTH a field AND in inputs!
}
```

This pattern makes sense:
- **Field** (`$region_id`) - For semantic clarity and easy access in methods
- **In inputs** - For graph dependency tracking (use-def chains, DCE, etc.)

### Proposed Design for Memory Edges

```perl
class Chalk::IR::Node::FieldStore {
    field $mem_id     :param :reader;  # NEW: Previous memory state
    field $object_id  :param :reader;
    field $field_id   :param :reader;
    field $value_id   :param :reader;
    field $alias_class :param :reader = undef;

    # inputs: [$mem_id, $object_id, $field_id, $value_id]
    #          ^^^^^^^^
    #          Memory edge is BOTH a field AND in inputs!
}
```

This enables peepholes:
```perl
method idealize($graph) {
    my $prev_mem = $graph->get_node($mem_id);
    return unless $prev_mem;

    # Direct O(1) lookup of previous memory state
    if ($prev_mem->isa('Chalk::IR::Node::FieldStore') &&
        $prev_mem->object_id == $object_id &&
        $prev_mem->alias_class == $alias_class &&
        scalar($graph->get_uses($prev_mem->id)->@*) == 1) {
        # Store-to-Store elimination!
    }
}
```

### Why This Doesn't Conflict with Heapless Architecture

The memory-model.md doc is clear: our heapless architecture means:
- **No separate heap data structure** - collections ARE contexts
- **Execution uses Environment** - not explicit memory threading

**Memory edges in IR ≠ heap in execution**

Memory edges just make **dependencies explicit in the IR graph**, which:
- Enables peephole optimizations
- Supports DCE (dead stores can be eliminated)
- Matches Sea of Nodes principles
- Doesn't change how `execute()` works (still uses Environment)

### Comparison to Current Architecture

**What stays the same:**
- Heapless execution model (Environment-based)
- Collections as contexts
- No separate heap data structure
- Alias classes for non-aliasing proofs

**What changes:**
- FieldStore/FieldLoad gain `mem_id` field and input
- Stores chain through memory dependencies
- Peepholes can inspect previous memory operations

This is consistent with how Chalk already handles control flow (Region/Phi nodes).

### Next Steps if Approved

1. Add `$mem_id` field to FieldStore/FieldLoad
2. Update tests to chain stores through memory edges
3. Implement `peephole()` methods with Store-Store, Load-after-Store optimizations
4. Verify all tests still pass with new memory edge architecture
