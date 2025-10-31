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

#### Memory Operations
- **Load** - Load from memory
  - ✅ Has `execute()` method
  - ✅ Tested in `t/sea-of-nodes/interpreter.t`
  - ❌ No differential tests yet (would need variable assignment support)
- **Store** - Store to memory
  - ✅ Has `execute()` method
  - ✅ Tested in `t/sea-of-nodes/interpreter.t`
  - ❌ No differential tests yet (would need variable assignment support)

#### Infrastructure
- **Start** - Function entry point
  - ✅ Has `execute()` method
  - ✅ Tested implicitly (all tests use this)

### ❌ Not Yet Implemented (7 nodes)

These nodes exist but don't have `execute()` methods yet:

#### Logical Operations
- **Not** - Logical NOT operator (!)
  - ❌ No `execute()` method
  - 📝 Future work: requires logical operator support

#### Increment/Decrement
- **PreIncrement** - Pre-increment (++$x)
  - ❌ No `execute()` method
  - 📝 Future work: requires lvalue support
- **PostIncrement** - Post-increment ($x++)
  - ❌ No `execute()` method
  - 📝 Future work: requires lvalue support
- **PreDecrement** - Pre-decrement (--$x)
  - ❌ No `execute()` method
  - 📝 Future work: requires lvalue support
- **PostDecrement** - Post-decrement ($x--)
  - ❌ No `execute()` method
  - 📝 Future work: requires lvalue support

#### Control Flow
- **Loop** - Loop construct
  - ❌ No `execute()` method
  - 📝 Future work: requires loop support

#### Memory
- **Reference** - Reference creation (\$x)
  - ❌ No `execute()` method
  - 📝 Future work: requires reference support

## Test Coverage Summary

```
Total IR Node Types:           28 (excluding Base)
With execute() methods:        20 (71%)
Differential test coverage:    12 (43%)
TODO/Partial coverage:          8 (29%)
Not yet implemented:            7 (25%)
```

## Known Issues Documented in TODO Tests

1. **Negative literals** - Expressions like `-5 + 3` don't parse/execute correctly
2. **Unary negation** - Standalone `-5` or `-(-5)` don't work
3. **False comparison output** - Returns `0` vs Perl's empty string (may be acceptable)
4. **Control flow with return** - if/else with return creates malformed IR graphs

## Next Steps for Full Coverage

### Phase 2: Complete Basic Operator Coverage
- [ ] Fix negative literal parsing/execution
- [ ] Add differential tests for control flow (after IR construction fix)
- [ ] Add differential tests for memory operations (Load/Store with variables)
- [ ] Document comparison operator false value behavior decision

### Phase 3: Implement Missing Operators
- [ ] Implement `Not` execute() method
- [ ] Implement increment/decrement execute() methods
- [ ] Implement `Loop` execute() method
- [ ] Implement `Reference` execute() method

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
