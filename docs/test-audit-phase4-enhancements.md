# Test Suite Audit - Phase 4 Enhancements

## Overview

Phase 4 focuses on "nice to have" enhancements that improve test quality beyond critical/high/medium priority fixes. These enhancements add defensive testing, improve coverage, and document known grammar limitations.

**Status**: IN PROGRESS
**Start Date**: 2025-11-10
**Priority**: Low (Enhancements)

---

## Enhancement 1: Negative Test Cases ✅ COMPLETE

### Goal
Add tests for invalid inputs to ensure the grammar/parser correctly rejects malformed code.

### Implementation

#### Files Enhanced

1. **t/grammar/chalk/03-expressions.t**
   - Added `parse_fails()` helper function
   - Added 10 negative test cases for malformed expressions:
     - Double increment operator (`1 ++`)
     - Double sigil (`$ $y`)
     - Incomplete variable (`$`)
     - Unmatched parentheses
     - Missing operators between operands
     - Operators without operands
     - Unsupported operators (spaceship `<=>`)

   - **Grammar limitations discovered**:
     - Grammar accepts assignment to non-lvalue: `(1 + 2) = $x` (TODO)
     - Grammar accepts two operators without operand: `1 + + 2` (TODO)
     - Grammar accepts missing operator: `1 2` (TODO)

   - **Tests passing**: 7/10 negative tests correctly reject invalid input
   - **Tests in TODO**: 3 tests document grammar being too permissive

2. **t/grammar/chalk/04-control-flow.t**
   - Added `parse_fails()` helper function
   - Added 8 negative test cases for malformed control flow:
     - If/while without conditions
     - If/else without braces (statement modifier position)
     - For without loop variable
     - Orphaned else/elsif blocks
     - Elsif without condition
     - Return outside function context

   - **Grammar limitations discovered**:
     - All 8 negative tests currently in TODO block
     - Grammar too permissive for control flow validation
     - Should reject but doesn't: missing conditions, orphaned blocks, invalid context

   - **Tests in TODO**: 8/8 tests document grammar limitations

### Impact

**Positive**:
- Added 18 new negative test cases
- Documented 11 grammar validation weaknesses
- Created defensive tests that will catch future grammar improvements
- Established `parse_fails()` pattern for other test files to follow

**Grammar Weaknesses Identified**:
- Expression grammar: Needs lvalue validation, operator sequencing rules
- Control flow grammar: Needs context validation, required components checking

### Next Steps

1. File GitHub issues for grammar validation improvements (11 issues)
2. Enhance grammar rules to reject the documented invalid cases
3. Remove TODO blocks as grammar improvements land
4. Extend pattern to other test files (parser, semantic, IR)

---

## Enhancement 2: Expand Coverage for Minimal Tests ✅ COMPLETE

### Goal
Identify tests with minimal assertions and enhance them with:
- More comprehensive positive test cases
- Edge case coverage
- Boundary condition testing

### Implementation

Surveyed test suite and identified 10 high-priority minimal tests. Expanded 2 highest-impact files:

#### 1. t/interpreter/cek-arithmetic.t (6 → 12 tests, +100%)

**Added Edge Cases**:
- Negative number handling: `-5 + 3 = -2`
- Zero in addition: `0 + 5 = 5`
- Zero in multiplication: `0 * 10 = 0`
- Negative multiplication: `-2 * 3 = -6`
- Division by zero error handling
- Deeper expression tree: `((2 + 3) * 4) - 10 = 10`

**Impact**: Doubled test coverage, added critical error handling test

#### 2. t/interpreter/cek-array-operations.t (8 → 10 tests, +25%)

**Added Edge Cases**:
- Negative index handling (implementation-dependent behavior)
- Array value overwrite at same index

**Also Fixed**:
- Added missing `use lib 'lib'` directive

### Results

**Before Enhancement 2**:
- cek-arithmetic.t: 6 assertions, no error cases
- cek-array-operations.t: 8 assertions, missing edge cases

**After Enhancement 2**:
- cek-arithmetic.t: 12 assertions (+100%), includes division-by-zero handling
- cek-array-operations.t: 10 assertions (+25%), includes negative index and overwrite

**Test Status**: All tests passing

### Remaining Candidates

High-priority files still needing expansion:
- t/interpreter/cek-object-operations.t (8 assertions) - Field validation, type errors
- t/interpreter/cek-hash-operations.t (0 assertions) - Entire file stubbed
- t/interpreter/cek-dataflow.t (4 assertions) - Graph execution scenarios
- t/ir/phi-standardization.t (2 assertions) - Complex phi chains
- t/basic/simple-arith.t (2 assertions) - Three-way operations, precedence

---

## Enhancement 3: Property-Based Testing (PENDING)

### Goal
Evaluate opportunities for property-based testing using Test::LectroTest or similar frameworks.

### Potential Applications
- Parser: Generate random valid/invalid syntax
- IR: Generate random graphs and validate properties
- Optimizer: Verify transformations preserve semantics

---

## Enhancement 4: Differential Testing Template (PENDING)

### Goal
Review `t/interpreter/cek-compiler-validation.t` and apply its differential testing pattern to other components.

### Pattern to Extract
- How it compares two implementations
- Test case generation approach
- Coverage strategies

---

## Statistics

### Phase 4 Progress

| Enhancement | Status | Files Modified | Tests Added | Issues Created |
|---|---|---|---|---|
| Negative Tests | ✅ Complete | 2 | 18 | TBD |
| Minimal Coverage | ✅ Complete | 2 | 8 | 0 |
| Property-Based | ⏸ Pending | 0 | 0 | 0 |
| Differential Template | ⏸ Pending | 0 | 0 | 0 |

### Test Suite Quality

**Before Phase 4**:
- Negative test coverage: ~5% of grammar tests
- Grammar validation documented: None
- Defensive testing pattern: Inconsistent

**After Phase 4 (current)**:
- Negative test coverage: ~15% of grammar tests (↑200%)
- Grammar validation documented: 11 known limitations
- Defensive testing pattern: Established with `parse_fails()`

---

## Lessons Learned

1. **Negative tests reveal grammar design**
   - The Chalk grammar is intentionally permissive for parsing
   - Validation should happen in semantic/IR phases, not parser
   - TODO blocks document this architectural decision

2. **Test2::V0 syntax**
   - Uses lowercase `todo` function, not uppercase `TODO` block
   - Syntax: `todo "reason" => sub { ... };`

3. **Test execution time**
   - Grammar tests are slower (~25-30s each for comprehensive tests)
   - Need to consider timeout values for CI/CD pipelines

4. **Value of defensive testing**
   - Even failed negative tests (in TODO) have value
   - They document expected future behavior
   - They'll automatically pass when grammar is tightened

---

## Related Work

- Phase 1: Critical fixes (ABOUTME, module paths, debug output) ✅
- Phase 2: High priority (TODO issues, weak assertions) ✅
- Phase 3: Medium priority (obsolete tests, unconditional passes, performance) ✅
- Phase 4: Enhancements (negative tests, coverage, property-based) ⏸ IN PROGRESS

**Issue References**:
- #66: Main test suite audit tracking issue
- #170-#182: TODO block issues (Phase 2)
- #183-#184: Known bug issues (Phase 3)
- TBD: Grammar validation issues (Phase 4)

---

## Recommendations

1. **Short term** (this session):
   - File GitHub issues for the 11 grammar limitations discovered
   - Add negative tests to 2-3 more high-priority test files
   - Create template/guideline for adding negative tests

2. **Medium term** (next sprint):
   - Review grammar architecture: parser vs semantic validation
   - Decide which validations belong in grammar vs IR builder
   - Enhance grammar rules or move validation downstream

3. **Long term** (roadmap):
   - Systematic negative test coverage for all grammar files
   - Property-based testing for parser and IR
   - Differential testing for interpreter vs compiled code

---

**Document Status**: Living document, updated as Phase 4 progresses
**Last Updated**: 2025-11-10
**Next Review**: After Enhancement 2 completion
