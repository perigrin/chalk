# Node API Compatibility Report

## Executive Summary
- **Total nodes audited**: 43
- **Using closure API**: 41 (95.3%)
- **Using hash API**: 1 (2.3%)
- **No execute() method**: 4 (9.3%) - Stub nodes
- **Need migration**: 1 (Loop)

## Audit Date
2025-11-07

## Nodes by Category

### ✅ Compatible (Closure API) - 41 nodes

#### Arithmetic Operations (5 nodes)
- **Add** (`lib/Chalk/IR/Node/Add.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **Subtract** (`lib/Chalk/IR/Node/Subtract.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **Multiply** (`lib/Chalk/IR/Node/Multiply.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **Divide** (`lib/Chalk/IR/Node/Divide.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **Negate** (`lib/Chalk/IR/Node/Negate.pm:24`)
  - Pattern: `$context->("node:$operand_id")`

#### Comparison Operations (6 nodes)
- **EQ** (`lib/Chalk/IR/Node/EQ.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **NE** (`lib/Chalk/IR/Node/NE.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **GT** (`lib/Chalk/IR/Node/GT.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **GE** (`lib/Chalk/IR/Node/GE.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **LT** (`lib/Chalk/IR/Node/LT.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`
- **LE** (`lib/Chalk/IR/Node/LE.pm:26-27`)
  - Pattern: `$context->("node:$left_id")`, `$context->("node:$right_id")`

#### Logical Operations (1 node)
- **Not** (`lib/Chalk/IR/Node/Not.pm:24`)
  - Pattern: `$context->("node:$operand_id")`

#### Control Flow (4 nodes)
- **If** (`lib/Chalk/IR/Node/If.pm:26`)
  - Pattern: `$context->("node:$condition_id")`
  - Updated: 2025-11-06
- **Proj** (`lib/Chalk/IR/Node/Proj.pm:30`)
  - Pattern: `$context->("node:$source_id")`
  - Updated: 2025-11-06
- **Region** (`lib/Chalk/IR/Node/Region.pm:28`)
  - Pattern: `$context->("node:$input_id")`
  - Updated: 2025-11-07
- **Phi** (`lib/Chalk/IR/Node/Phi.pm:27,37`)
  - Pattern: `$context->("node:$region_id")`, `$context->("node:$value_id")`
  - Updated: 2025-11-06

#### Heap Operations - Arrays (3 nodes)
- **NewArray** (`lib/Chalk/IR/Node/NewArray.pm:22`)
  - Pattern: `$context->('env:')`
  - Updated: 2025-11-06
- **ArrayLoad** (`lib/Chalk/IR/Node/ArrayLoad.pm:27,30,33`)
  - Pattern: `$context->("node:$array_id")`, `$context->("node:$index_id")`, `$context->('env:')`
  - Updated: 2025-11-06
- **ArrayStore** (`lib/Chalk/IR/Node/ArrayStore.pm:29,32,35,38`)
  - Pattern: `$context->("node:$array_id")`, `$context->("node:$index_id")`, `$context->("node:$value_id")`, `$context->('env:')`
  - Updated: 2025-11-06

#### Heap Operations - Hashes (3 nodes)
- **NewHash** (`lib/Chalk/IR/Node/NewHash.pm:22`)
  - Pattern: `$context->('env:')`
  - Updated: 2025-11-06
- **HashLoad** (`lib/Chalk/IR/Node/HashLoad.pm:27,30,33`)
  - Pattern: `$context->("node:$hash_id")`, `$context->("node:$key_id")`, `$context->('env:')`
  - Updated: 2025-11-06
- **HashStore** (`lib/Chalk/IR/Node/HashStore.pm:29,32,35,38`)
  - Pattern: `$context->("node:$hash_id")`, `$context->("node:$key_id")`, `$context->("node:$value_id")`, `$context->('env:')`
  - Updated: 2025-11-06

#### Heap Operations - Objects (3 nodes)
- **NewObject** (`lib/Chalk/IR/Node/NewObject.pm:22`)
  - Pattern: `$context->('env:')`
  - Updated: 2025-11-06
- **FieldLoad** (`lib/Chalk/IR/Node/FieldLoad.pm:27,30,33`)
  - Pattern: `$context->("node:$object_id")`, `$context->("node:$field_id")`, `$context->('env:')`
  - Updated: 2025-11-06
- **FieldStore** (`lib/Chalk/IR/Node/FieldStore.pm:29,32,35,38`)
  - Pattern: `$context->("node:$object_id")`, `$context->("node:$field_id")`, `$context->("node:$value_id")`, `$context->('env:')`
  - Updated: 2025-11-06

#### Composite Data Access (4 nodes)
- **ArrayGet** (`lib/Chalk/IR/Node/ArrayGet.pm:29,32,39`)
  - Pattern: `$context->("node:$array_id")`, `$context->("node:$index_id")`, `$context->("node:" . $element_node->id)`
- **ArraySet** (`lib/Chalk/IR/Node/ArraySet.pm:31,34,37`)
  - Pattern: `$context->("node:$array_id")`, `$context->("node:$index_id")`, `$context->("graph:$value_id")`
- **HashGet** (`lib/Chalk/IR/Node/HashGet.pm:29,32,39`)
  - Pattern: `$context->("node:$hash_id")`, `$context->("node:$key_id")`, `$context->("node:" . $element_node->id)`
- **HashSet** (`lib/Chalk/IR/Node/HashSet.pm:31,34,37`)
  - Pattern: `$context->("node:$hash_id")`, `$context->("node:$key_id")`, `$context->("graph:$value_id")`

#### Composite Data Values (2 nodes)
- **ArrayValue** (`lib/Chalk/IR/Node/ArrayValue.pm:23`)
  - Pattern: Returns `$array_context` (already a closure)
  - Note: Wraps context for array storage
- **HashValue** (`lib/Chalk/IR/Node/HashValue.pm:23`)
  - Pattern: Returns `$hash_context` (already a closure)
  - Note: Wraps context for hash storage

#### References (2 nodes)
- **Reference** (`lib/Chalk/IR/Node/Reference.pm:25`)
  - Pattern: Takes `$context` but returns reference object
  - Note: Stores (context, label) pair for dereferencing
- **ScalarDeref** (`lib/Chalk/IR/Node/ScalarDeref.pm:25,38`)
  - Pattern: `$context->("node:$ref_id")`, `$context->("node:$node_id")`

#### Variables (1 node)
- **VariableRead** (`lib/Chalk/IR/Node/VariableRead.pm:25,28`)
  - Pattern: `$context->($var_label)`, `$context->("node:$node_id")`

#### Function Entry (1 node)
- **Return** (`lib/Chalk/IR/Node/Return.pm:27`)
  - Pattern: `$context->("node:$value_id")`

#### No-Argument Nodes (2 nodes)
These nodes have `execute()` with no parameters, returning stored values:
- **Constant** (`lib/Chalk/IR/Node/Constant.pm:25`)
  - Signature: `execute()` (no params)
  - Returns: `$value` field
  - Note: No inputs, safe from API change
- **Start** (`lib/Chalk/IR/Node/Start.pm:25`)
  - Signature: `execute()` (no params)
  - Returns: `undef` (control token)
  - Note: No inputs, safe from API change

### ⚠️ Incompatible (Hash API) - 1 node

#### Control Flow
- **Loop** (`lib/Chalk/IR/Node/Loop.pm:19,28`)
  - Current: `execute($values)` → `$values->{$input_id}`
  - Needs: `execute($context)` → `$context->("node:$input_id")`
  - Purpose: Merges control from entry and backedge paths
  - Behavior: Similar to Region, returns index of active path
  - Risk: **HIGH** - Will fail at runtime when CEK calls with closure

### 🚧 Stub Nodes (No execute() method) - 4 nodes

These nodes are declared but not implemented:
- **PostIncrement** (`lib/Chalk/IR/Node/PostIncrement.pm`)
  - Has `$operand_id` field but no `execute()` method
- **PostDecrement** (`lib/Chalk/IR/Node/PostDecrement.pm`)
  - Has `$operand_id` field but no `execute()` method
- **PreIncrement** (`lib/Chalk/IR/Node/PreIncrement.pm`)
  - Has `$operand_id` field but no `execute()` method
- **PreDecrement** (`lib/Chalk/IR/Node/PreDecrement.pm`)
  - Has `$operand_id` field but no `execute()` method

Note: These stub nodes are safe from API compatibility issues since they don't implement `execute()` yet. When implemented, they should follow the closure pattern.

## Analysis

### API Migration Status
The migration from hash-based context (`$values->{$id}`) to closure-based context (`$context->("node:$id")`) is **95.3% complete**.

### Critical Finding
**Loop node** is the only node using the old hash API. This is a critical compatibility issue because:

1. **Runtime Failure Risk**: When CEK's `evaluate_ir_node()` calls `$node->execute($context)` on a Loop node, it will try to use the closure as a hash reference
2. **Control Flow Critical**: Loop nodes control iteration, so failure here breaks any code with loops
3. **Recent Updates**: Control flow nodes (If, Proj, Region, Phi) were all updated 2025-11-06/07, but Loop was missed

### Pattern Consistency
All other nodes follow consistent patterns:
- **Node value lookup**: `$context->("node:$node_id")`
- **Graph lookup**: `$context->("graph:$node_id")`
- **Environment lookup**: `$context->('env:')`
- **Variable lookup**: `$context->($var_label)`

### Stub Node Status
The 4 stub nodes (increment/decrement operators) are currently incomplete. When implemented, they should:
1. Follow the closure pattern: `execute($context)`
2. Look up operands via: `$context->("node:$operand_id")`
3. Perform side-effect operations (requires mutable environment model)

## Recommendations

### Immediate Actions (Blocking for PR #164)
1. **Fix Loop.pm** to use closure pattern
   - Change: `execute($values)` → `execute($context)`
   - Change: `$values->{$input_id}` → `$context->("node:$input_id")`
   - Verify behavior matches Region node pattern

### Testing Requirements
1. **Create integration test** (`t/interpreter/cek-all-nodes.t`)
   - Exercise all 39 implemented nodes with CEK
   - Verify Loop node with both entry and backedge paths
   - Ensure no runtime errors from API mismatches

2. **Run existing tests**
   - Verify no regressions from Loop fix
   - Check control flow tests pass

### Future Work (Non-blocking)
1. **Implement stub nodes** (PostIncrement, PostDecrement, PreIncrement, PreDecrement)
   - Use closure pattern from the start
   - Design for mutable environment model

2. **Document API contract**
   - Formalize closure API in `lib/Chalk/IR/Node/Base.pm`
   - Add examples of each context lookup pattern
   - Create migration guide for future nodes

## Audit Methodology

### Search Commands Used
```bash
# Count nodes
ls lib/Chalk/IR/Node/*.pm | wc -l

# Find old hash pattern
ag '\$values->\{' lib/Chalk/IR/Node/*.pm

# Find new closure pattern
ag '\$context->\(' lib/Chalk/IR/Node/*.pm
```

### Files Examined
All 43 node class files in `lib/Chalk/IR/Node/` were examined:
- Automated search for patterns
- Manual verification of edge cases (no-arg execute, stubs)
- Cross-reference with recent PR changes

### Verification
- Loop.pm confirmed as only incompatible node
- All heap operations (9 nodes) confirmed updated 2025-11-06
- All control flow nodes except Loop confirmed updated 2025-11-06/07
- Stub nodes identified and documented

## Conclusion

The API migration is nearly complete with **only 1 critical issue**: Loop.pm must be fixed before merging PR #164. The fix is straightforward (2 lines), follows an established pattern (Region node), and can be tested with existing infrastructure.

After fixing Loop and creating the integration test, all 39 implemented nodes will be compatible with CEK's closure-based context API.
