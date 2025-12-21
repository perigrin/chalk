# Stage 0 Blockers Work Plan

## Overview

Five issues block Stage 0 (Perl→XS Compiler) milestone completion. This document defines the execution order and scope for each.

## Issues

| Issue | Title | Effort |
|-------|-------|--------|
| #397 | CallEnd IR node projections | 1 session |
| #396 | Call IR node execute() | 1 session |
| #398 | ArrayVar/HashVar in Variable rule | 1 session |
| #402 | ExpressionList proper list/array IR | 1-2 sessions |
| #7 | Array/Hash semantic actions | 2-3 sessions |

**Total: 6-8 sessions**

## Dependency Graph

```
#397 CallEnd projections
    ↓
#396 Call execute()

#398 ArrayVar/HashVar ──┐
                        ├──→ #7 Array/Hash semantic actions
#402 ExpressionList ────┘
```

## Execution Order

### Step 1: #397 CallEnd Projections

**File:** `lib/Chalk/IR/Node/CallEnd.pm`

**Tasks:**
- Implement `ctrl_proj()` → Return Proj node for control flow continuation
- Implement `mem_proj()` → Return Proj node for memory state after call
- Implement `ret_proj()` → Return Proj node for return value

**Success criteria:** All three methods return valid Proj nodes; existing tests pass.

---

### Step 2: #396 Call execute()

**File:** `lib/Chalk/IR/Node/Call.pm`

**Tasks:**
- Implement `execute($context)` for function dispatch
- Set up call frame and transfer control to callee
- Integrate with CallEnd projections from Step 1

**Success criteria:** Function calls dispatch correctly; chapter18 tests remain green.

---

### Step 3: #398 ArrayVar/HashVar

**File:** `lib/Chalk/Grammar/Chalk/Rule/Variable.pm`

**Tasks:**
- Handle `@array` → Generate NewArray + Load IR
- Handle `%hash` → Generate NewHash + Load IR
- Handle `$#array` → Generate ArraySize IR node

**Success criteria:** Variable rule generates correct IR for all three cases.

---

### Step 4: #402 ExpressionList IR

**File:** `lib/Chalk/Grammar/Chalk/Rule/ExpressionList.pm`

**Tasks:**
- Generate proper list IR for `(1, 2, 3)` literals
- Handle function argument lists `foo($a, $b, $c)`
- Support list assignment context `my ($x, $y) = ...`
- Distinguish list vs scalar vs void context

**Success criteria:** Expression lists generate correct IR; list operations work end-to-end.

---

### Step 5: #7 Array/Hash Semantic Actions

**Files:**
- `lib/Chalk/Grammar/Chalk/Rule/VariableDeclaration.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Assignment.pm`
- New test files in `t/data/`

**Tasks:**
- Wire up VariableDeclaration for `my @arr` and `my %hash`
- Wire up indexing operations `$arr[0]`, `$hash{key}`
- Wire up assignment to array/hash elements
- Create `t/data/arrays.t` end-to-end tests
- Create `t/data/hashes.t` end-to-end tests

**Success criteria:** Chalk programs using arrays/hashes compile and execute through full pipeline.

## Notes

- Steps 1-2 (function calls) and Steps 3-4 (data structures) are logically independent but executed sequentially for safety
- Step 5 depends on Steps 3-4 being complete
- IR nodes already exist and pass tests; this work is about semantic actions (grammar→IR bridge)
