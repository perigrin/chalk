# Documentation Clarification: Immutability

During competitive code review, Reviewer #3 challenged the "immutability" claims in PR #164.
This document provides clarification.

## What We Have: Snapshot-Based Time-Travel Debugging

The Environment class provides snapshot-based time-travel debugging capabilities:
- `snapshot()` captures complete execution state
- `restore_from_snapshot()` restores to previous state
- Enables debugging without replay
- Provides immutable checkpoints during execution

## What We Don't Have: Pure Functional Immutability

The Environment class is intentionally mutable during execution:
- Methods like `set_node()`, `set_variable()`, `set_heap()` mutate state in place
- Internal counter `$next_heap_id++` mutates during allocation
- This is intentional for performance and simplicity

## The Distinction

**Snapshot-based immutability** means:
- The environment itself is mutable
- Snapshots provide immutable checkpoints
- You can restore to any previous checkpoint
- This enables time-travel debugging

**Pure functional immutability** would mean:
- Every operation returns a new environment
- Original environment is never modified
- This is theoretically pure but impractical for performance

## Why This is the Right Tradeoff

1. **Performance**: Mutation is faster than creating new environments on every operation
2. **Simplicity**: Mutable operations are easier to understand and use
3. **Debugging**: Snapshots provide the benefits of immutability where it matters
4. **Practical**: Most production systems use mutable state with checkpointing

## The Context Abstraction

The `Chalk::IR::Context` abstraction IS purely functional:
- `extend_context()` returns a new context
- Original context is never modified
- This is true closure-based functional programming

However, the Environment that uses these contexts provides both patterns:
- **Mutating methods** (e.g., `set_node`) for efficient execution
- **Extending methods** (e.g., `extend_node`) for functional style when needed
- **Snapshot/restore** for debugging

## Conclusion

The architecture provides **snapshot-based immutability** for debugging while using **mutation for efficient execution**. This is the right engineering tradeoff for a production interpreter. The original PR description should have been clearer about this distinction.
