# Chalk Interpreter Test Coverage Analysis

Generated: 2025-10-31

## Summary

This document tracks which IR nodes have `execute()` methods implemented and which have differential test coverage comparing Chalk interpreter output against Perl 5.42.0.

## Coverage Status

### ✅ Fully Implemented & Tested (12 nodes)

These nodes have `execute()` methods AND differential tests validating against Perl 5.42.0:

#### Arithmetic Operations
- **Add** - Addition operator (+)
  - ✅ Tests: positive numbers, with zeros, with variables
- **Subtract** - Subtraction operator (-)
  - ✅ Tests: positive numbers, resulting in zero, with variables
- **Multiply** - Multiplication operator (*)
  - ✅ Tests: positive numbers, by zero, with variables
- **Divide** - Division operator (/)
  - ✅ Tests: integer division, floating-point division, with variables

#### Comparison Operations
- **GT** - Greater than (>)
  - ✅ Tests: true cases validated
  - ⚠️  TODO: false cases (output format difference)
- **LT** - Less than (<)
  - ✅ Tests: true cases validated
  - ⚠️  TODO: false cases (output format difference)
- **EQ** - Equal (==)
  - ✅ Tests: true cases validated
  - ⚠️  TODO: false cases (output format difference)
- **NE** - Not equal (!=)
  - ✅ Tests: true cases validated
- **GE** - Greater than or equal (>=)
  - ✅ Tests: true cases (both greater and equal)
  - ⚠️  TODO: false cases (output format difference)
- **LE** - Less than or equal (<=)
  - ✅ Tests: true cases (both less and equal)
  - ⚠️  TODO: false cases (output format difference)

#### Other
- **Constant** - Constant value node
  - ✅ Tests: integer constants, used in expressions
- **Return** - Return statement
  - ✅ Tests: returning constants, expressions, variables

### ⚠️ Implemented But Not Yet Fully Tested (8 nodes)

These nodes have `execute()` methods but lack comprehensive differential tests:

#### Unary Operations
- **Negate** - Unary negation (-)
  - ✅ Has `execute()` method
  - ❌ TODO: Tests fail - negative literals don't parse correctly
  - 📝 Tracked in: `t/sea-of-nodes/interpreter-differential.t` TODO block

#### Control Flow
- **If** - Conditional branching
  - ✅ Has `execute()` method
  - ✅ Tested in `t/sea-of-nodes/interpreter.t` (basic cases)
  - ⚠️  SKIPPED in differential: creates malformed IR with return statements
- **Proj** - Control flow projection (IfTrue/IfFalse)
  - ✅ Has `execute()` method
  - ✅ Tested in `t/sea-of-nodes/interpreter.t`
  - ❌ No differential tests yet
- **Region** - Control flow merge point
  - ✅ Has `execute()` method
  - ✅ Tested in `t/sea-of-nodes/interpreter.t`
  - ❌ No differential tests yet
- **Phi** - Value selection based on control flow
  - ✅ Has `execute()` method
  - ✅ Tested in `t/sea-of-nodes/interpreter.t`
  - ❌ No differential tests yet

#### Context-Based Variable Access
- **VariableRead** - Read variable from lexical context
  - ✅ Has `execute()` method
  - ✅ Works with context-as-closure memory model
  - ❌ No differential tests yet (blocked by variable reassignment bug)
  - 📝 Note: Chalk uses pure context model - no Store/Load IR nodes exist

#### Array/Hash Operations
- **ArrayValue, HashValue** - Collection construction
  - ✅ Have `execute()` methods
  - ✅ Collections are contexts with index:/key: namespaces
- **ArrayGet, ArraySet, HashGet, HashSet** - Collection access
  - ✅ Have `execute()` methods
  - ⚠️ Limited testing

#### Infrastructure
- **Start** - Function entry point
  - ✅ Has `execute()` method
  - ✅ Tested implicitly (all tests use this)

### ❌ Not Yet Implemented (4 nodes)

These nodes exist but don't have `execute()` methods OR semantic actions:

#### Increment/Decrement (Grammar Rules Exist, Semantic Actions TODO)
- **PreIncrement** - Pre-increment (++$x)
  - ✅ Grammar rule: `Unary -> '++' WS_OPT Unary`
  - ❌ Semantic action not implemented (see `Rule::Unary.pm`)
  - ❌ No `execute()` method
  - 📝 Blocked by: variable reassignment bug (needs context extension)
- **PostIncrement** - Post-increment ($x++)
  - ✅ Grammar rule: `Postfix -> Variable '++'`
  - ❌ Semantic action not implemented (see `Rule::Postfix.pm` line 10-11)
  - ❌ No `execute()` method
  - 📝 Blocked by: variable reassignment bug
- **PreDecrement** - Pre-decrement (--$x)
  - ✅ Grammar rule: `Unary -> '--' WS_OPT Unary`
  - ❌ Semantic action not implemented
  - ❌ No `execute()` method
  - 📝 Blocked by: variable reassignment bug
- **PostDecrement** - Post-decrement ($x--)
  - ✅ Grammar rule: `Postfix -> Variable '--'`
  - ❌ Semantic action not implemented (see `Rule::Postfix.pm` line 12)
  - ❌ No `execute()` method
  - 📝 Blocked by: variable reassignment bug

### ✅ Previously Listed as Missing But Actually Implemented

#### Logical Operations
- **Not** - Logical NOT operator (!)
  - ✅ Has `execute()` method
  - ✅ Semantic action implemented in `Rule::Unary.pm`
  - ⚠️ Needs differential testing

#### Control Flow
- **Loop** - Loop construct
  - ✅ Has `execute()` method
  - ⚠️ Needs testing with actual loop constructs

#### Memory/References
- **Reference** - Reference creation (\$x)
  - ✅ Has `execute()` method
  - ✅ Semantic action implemented in `Rule::Unary.pm`
  - ✅ Uses `(context, label)` pair model
  - ✅ Tested in `t/sea-of-nodes/references.t`
- **ScalarDeref** - Dereference ($$ref)
  - ✅ Has `execute()` method
  - ✅ Tested in `t/sea-of-nodes/references.t`

## Test Coverage Summary (CORRECTED)

```
Total IR Node Types:           34 (excluding Base)
With execute() methods:        30 (88%)
Differential test coverage:    12 (35%)
Implemented but undertested:   18 (53%)
Not yet implemented:            4 (12%)
  - PreIncrement, PostIncrement
  - PreDecrement, PostDecrement
  (Note: Grammar rules exist, just need semantic actions + execute())
```

### Memory Model Note

Chalk uses a **pure context-as-closure memory model**. There are NO Store/Load IR nodes. Variable assignment is handled via:

```perl
# In IR Builder:
$context = Chalk::IR::Context->extend_context($context, "lexical:$x", $value_node);

# In Interpreter:
$node = $context->("lexical:$x");  # Direct context lookup
```

**Context handling** (list vs scalar) is managed by the **Type system** via `Chalk::Type::List->convert_to_target($sigil)`, not by separate IR nodes.

## Known Issues Documented in TODO Tests

1. **Negative literals** - Expressions like `-5 + 3` don't parse/execute correctly
2. **Unary negation** - Standalone `-5` or `-(-5)` don't work
3. **False comparison output** - Returns `0` vs Perl's empty string (may be acceptable)
4. **Control flow with return** - if/else with return creates malformed IR graphs

## Next Steps for Full Coverage

### Phase 2: Complete Basic Operator Coverage
- [ ] Fix negative literal parsing/execution
- [ ] Add differential tests for control flow (after IR construction fix)
- [ ] Fix variable reassignment in context model (BLOCKER)
- [ ] Add differential tests for variable operations (reads after reassignment)
- [ ] Document comparison operator false value behavior decision

### Phase 3: Implement Missing Operators
- [ ] Implement semantic actions for ++/-- in `Rule::Unary.pm` and `Rule::Postfix.pm`
- [ ] Implement PreIncrement/PostIncrement/PreDecrement/PostDecrement execute() methods
- [ ] Add builder methods: `build_pre_increment_node()`, etc.
- [ ] Add differential tests for increment/decrement

### Phase 4: Advanced Coverage
- [ ] Modulo operator (%)
- [ ] Exponentiation operator (**)
- [ ] Bitwise operators (~, &, |, ^, <<, >>)
- [ ] Logical operators (&&, ||)
- [ ] String comparison operators (eq, ne, lt, gt, le, ge, cmp)
- [ ] Division by zero behavior
- [ ] Overflow/underflow handling
- [ ] Operator precedence edge cases

## Usage

To validate coverage, run:

```bash
# Run all interpreter tests
PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/sea-of-nodes/interpreter*.t

# Run only differential tests
PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/sea-of-nodes/interpreter-differential.t

# Check for nodes without execute() methods
grep -L "method execute" lib/Chalk/IR/Node/*.pm | grep -v Base.pm
```

## References

- Issue #128: Expand Interpreter Test Coverage
- PR #129: Add differential testing framework
- Test file: `t/sea-of-nodes/interpreter.t` (unit tests, 979 lines)
- Test file: `t/sea-of-nodes/interpreter-differential.t` (differential tests, 202 lines)
