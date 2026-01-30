# Prototype: Unified EvalContext Comonad Architecture

## Overview

This prototype validates the architecture where Parser creates EvalContext and passes it to semirings, which then build context trees through multiply() operations.

## Implementation

### Branch
- `prototype-unified-comonad` (based on `sequential-filtering-clean`)

### Changes Made

1. **BooleanElement** (`lib/Chalk/Semiring/Boolean.pm`):
   - Added `field $context :param :reader = undef` to store EvalContext
   - Updated `multiply()` to build new contexts from left+right contexts
   - Updated `on_scan()` to create contexts for scanned terminals
   - Added debug instrumentation with `DEBUG_CONTEXT` environment variable

2. **Parser** (`lib/Chalk/Parser.pm`):
   - Added `use Chalk::EvalContext`
   - Modified `init_element_from_rule()` calls to create and pass EvalContext
   - Context creation happens in two places:
     - Initial prediction (line ~271)
     - Nonterminal prediction (line ~807)

3. **Boolean Semiring** (`lib/Chalk/Semiring/Boolean.pm`):
   - Updated `init_element_from_rule()` to accept optional `$ctx` parameter
   - If context provided, creates new element with it; otherwise uses cached mul_id

### Test File
- `/home/perigrin/dev/chalk/t/prototype/boolean-comonad.t`
- Tests basic parsing, context storage, and context tree building

## Results

### What Worked

1. **Context Creation and Storage**: Parser successfully creates EvalContext and passes to Boolean semiring ✅
2. **Context Propagation**: Elements store and carry contexts through parsing ✅
3. **Context Tree Building**: `multiply()` successfully combines left+right contexts into parent context with children ✅
4. **Backward Compatibility**: Old code paths still work when context is not provided ✅

### Key Findings

#### Terminal-Only Rules Don't Trigger multiply()
- Grammar: `S -> 'a' 'b' 'c'`
- Parsing: Scans terminals directly, advancing dot position on same item
- Result: multiply() never called, no context tree built

#### Nonterminal Rules Trigger multiply()
- Grammar: `S -> A B`, `A -> 'a'`, `B -> 'b'`
- Parsing: Completes A, then multiplies (S waiting) * (A completed)
- Result: multiply() called, context tree built with 2 children

#### multiply() Call Flow
```
1. Parser.complete() detects completed item (e.g., A -> 'a'•)
2. Finds waiting items (e.g., S -> A• B at position 0)
3. Combines: waiting_element * completed_element (line 668 in Parser.pm)
4. Boolean.multiply() builds new context from left+right
5. Returns new element with combined context
```

### Test Output
```
[BOOLEAN.multiply] CALLED
[BOOLEAN.multiply] left_ctx=YES right_ctx=YES
[BOOLEAN.multiply] Building context with 2 children

Result context: EvalContext[rule=S, type=none, pos=0..2]
Children count: 2
  Child 0: EvalContext[rule=S, type=none, pos=0..1]
  Child 1: EvalContext[rule=B, type=none, pos=1..2]
```

## What's Easier

1. **Unified Creation Point**: Parser creates all contexts in one place (init_element_from_rule calls)
2. **Explicit Data Flow**: Clear flow from Parser → semiring → element → multiply() → new element
3. **Comonad Operations**: Context tree structure naturally supports extract/extend/duplicate
4. **No Magic**: No hidden state or delayed context creation

## What's Harder

1. **Performance Impact**: Creating new elements in multiply() instead of using cached identities
   - Current: Returns cached `mul_id` (shared reference)
   - Prototype: Creates new `BooleanElement` on every multiply()
   - Impact: More memory allocations, no sharing of identity elements

2. **Backward Compatibility**: Need to handle both context and non-context code paths
   - `init_element_from_rule()` takes optional 5th parameter
   - `on_scan()` checks if element has context before creating new one
   - multiply() checks if either context is defined

3. **Terminal Handling**: Scanned terminals need special handling
   - on_scan() must create contexts for terminals
   - Terminal contexts have empty children array
   - Position tracking must be updated correctly

4. **Identity Element Semantics**: Cached identities no longer work with contexts
   - add_id and mul_id are shared across all parses
   - Can't store parse-specific context in shared identity
   - Must create new elements for each parse operation

## What's Needed to Extend to Other Semirings

1. **Update all Element classes**:
   - Add `field $context :param :reader = undef`
   - Update multiply() to build context trees
   - Update add() if needed (for alternatives)

2. **Update on_scan() implementations**:
   - Create contexts for scanned terminals
   - Handle position updates correctly

3. **Update init_element_from_rule() signatures**:
   - Add optional `$ctx` parameter to all semirings
   - Create elements with context when provided

4. **Handle identity elements**:
   - Either: Always create new elements (performance cost)
   - Or: Use context-less identities and build contexts lazily
   - Or: Create factory methods for identity+context

5. **Composite semiring**:
   - Pass context to all wrapped semirings
   - Coordinate context building across multiple semirings
   - Decide which semiring "owns" the context

6. **Add() operation**:
   - Decide semantics: Should add() merge contexts or choose one?
   - For alternatives: Keep both contexts or prefer one?
   - May need different behavior per semiring

## Performance Considerations

### Memory
- Creates new element for every multiply() operation
- No sharing of identity elements
- Context objects accumulate in tree structure
- Potential issue for large parses

### CPU
- More object allocations in multiply()
- More constructor calls
- More garbage collection pressure
- Trade-off: Explicitness vs performance

### Optimization Opportunities
1. **Object pooling**: Reuse element/context objects
2. **Lazy context building**: Only create when needed
3. **Structural sharing**: Share immutable parts of context tree
4. **Identity optimization**: Special-case identity elements

## Recommendations

### For Production Use
1. **Benchmark first**: Measure performance impact on real Chalk code
2. **Profile memory**: Check if context trees cause issues
3. **Consider hybrid**: Context only for semantic semirings, not Boolean
4. **Optimize hot paths**: Special-case common operations

### For Further Prototyping
1. **Test with Semantic semiring**: More complex than Boolean
2. **Test with Composite**: Coordination across semirings
3. **Test large parses**: See if performance degrades
4. **Test alternatives**: How should add() handle contexts?

## Conclusion

The unified comonad architecture is **viable** and **works correctly** for the Boolean semiring. The main trade-offs are:

**Pros**:
- Clearer data flow
- Explicit context management
- Natural comonad structure
- No hidden magic

**Cons**:
- Performance cost (more allocations)
- Backward compatibility complexity
- Identity element semantics change
- All semirings must be updated

**Verdict**: The architecture works, but needs performance evaluation before production use. Consider:
1. Implementing for Semantic semiring (where context is most valuable)
2. Keeping Boolean semiring as-is (performance critical)
3. Measuring real-world impact on Chalk compilation times

## Files Modified

- `/home/perigrin/dev/chalk/lib/Chalk/Semiring/Boolean.pm`
- `/home/perigrin/dev/chalk/lib/Chalk/Parser.pm`
- `/home/perigrin/dev/chalk/t/prototype/boolean-comonad.t` (new test)

## How to Test

```bash
# Run test without debug output
perl -Ilib t/prototype/boolean-comonad.t

# Run with debug output to see context building
DEBUG_CONTEXT=1 perl -Ilib t/prototype/boolean-comonad.t
```

All tests pass (10/10).
