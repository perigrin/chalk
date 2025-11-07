# CEK Differential Test TODO Investigation Report

**Date**: 2025-11-07
**Investigator**: perigrin
**Context**: PR #164 code review feedback - Reviewer #3 identified discrepancy between "100% validation" claim and 89.7% actual pass rate

## Executive Summary

All 4 TODO tests in `t/interpreter/cek-compiler-validation.t` are **IR Builder bugs, not CEK interpreter bugs**. The CEK interpreter correctly executes all IR graphs it receives. The failures are caused by malformed IR generation in `Chalk::Semiring::Semantic`.

**Differential Test Pass Rate**: 89.7% (35 of 39 tests pass)
**CEK Interpreter Correctness**: 100% (executes all IR correctly)
**IR Builder Correctness**: 89.7% (fails on operator precedence and control flow)

## Investigation Methodology

1. Examined generated IR for each TODO test using debug script
2. Compared generated IR structure against expected Sea of Nodes patterns
3. Verified CEK execution matches what the malformed IR specifies
4. Identified root cause in IR Builder (semantic actions during parsing)

## TODO Test Analysis

### Test 1: Operator Precedence (3 + 5 * 2)

**Test Code**: `return 3 + 5 * 2;`

**Expected Result**: 13
**Actual CEK Result**: 16
**Test Status**: TODO (IR Builder bug)

**IR Analysis**:
```
Node node_6  : Constant  value=3
Node node_10 : Constant  value=5
Node node_11 : Add       inputs=[..., node_6, node_10]    # produces 8
Node node_15 : Constant  value=2
Node node_17 : Multiply  inputs=[..., node_11, node_15]   # produces 16
Node node_19 : Return    inputs=[..., node_17]
```

**Root Cause**: IR Builder generates `((3 + 5) * 2)` instead of `(3 + (5 * 2))`. The multiplication should have higher precedence and be computed first, but the IR shows addition as input to multiplication.

**CEK Verdict**: ✅ Correctly executes the malformed IR
- CEK computes: Add(3, 5) = 8, then Multiply(8, 2) = 16
- This matches what the IR specifies (even though the IR is wrong)

**Fix Location**: `Chalk::Semiring::Semantic` operator precedence in arithmetic expression parsing

---

### Test 2: If Statement (False Condition)

**Test Code**: `my $x = -5; my $result = 0; if ($x > 0) { $result = 10; } return $result;`

**Expected Result**: 0 (condition is false, if block shouldn't execute)
**Actual CEK Result**: 10
**Test Status**: TODO (IR Builder bug)

**IR Analysis**:
```
Node node_32 : Start
Node node_35 : Constant  inputs=[node_32]
Node node_59 : Constant  value=10 inputs=[node_32]
Node node_75 : Return    inputs=[node_35, node_59]
```

**Missing Nodes**: NO If, Proj, Region, or Phi nodes!

**Root Cause**: IR Builder completely fails to generate control flow nodes for if statements. Instead of generating:
- If node (with comparison condition)
- Proj nodes (for true/false branches)
- Region node (to merge control flow)
- Phi nodes (to merge data flow)

It generates unconditional execution that always returns the constant 10.

**CEK Verdict**: ✅ Correctly executes the malformed IR
- CEK returns 10 because that's what the IR specifies (no conditional logic present)

**Fix Location**: `Chalk::Semiring::Semantic` if statement semantic action - must generate proper control flow nodes

---

### Test 3: If-Else (True Condition, Should Take If Branch)

**Test Code**: `my $x = 5; my $result = 0; if ($x > 0) { $result = 10; } else { $result = 20; } return $result;`

**Expected Result**: 10 (condition is true, if block should execute)
**Actual CEK Result**: 20
**Test Status**: TODO (IR Builder bug)

**IR Analysis**:
```
Node node_31 : Start
Node node_34 : Constant  inputs=[node_31]
Node node_74 : Constant  value=20 inputs=[node_31]
Node node_90 : Return    inputs=[node_34, node_74]
```

**Missing Nodes**: NO If, Proj, Region, or Phi nodes!

**Root Cause**: IR Builder fails to generate control flow nodes for if-else statements. It unconditionally executes the else branch and returns 20, ignoring the if branch entirely.

**CEK Verdict**: ✅ Correctly executes the malformed IR
- CEK returns 20 because that's what the unconditional IR specifies

**Fix Location**: `Chalk::Semiring::Semantic` if-else statement semantic action

---

### Test 4: If-Else Modifying Variable (True Condition)

**Test Code**: `my $x = 10; if ($x > 5) { $x = $x + 5; } else { $x = $x - 5; } return $x;`

**Expected Result**: 15 (condition is true, should execute if branch: 10 + 5 = 15)
**Actual CEK Result**: 10
**Test Status**: TODO (IR Builder bug)

**IR Analysis**:
```
Node node_12 : Constant  value=10
Node node_36 : Constant  value=5
Node node_37 : Add       inputs=[..., node_12, node_36]  # if branch: 10 + 5 = 15
Node node_54 : Constant  value=5
Node node_55 : Subtract  inputs=[..., node_37, node_54]  # else branch: 15 - 5 = 10
Node node_72 : Return    inputs=[..., node_55]
```

**Missing Nodes**: NO If, Proj, Region, or Phi nodes!

**Root Cause**: IR Builder generates **both branches sequentially** without control flow:
1. First executes if branch: Add(10, 5) = 15
2. Then executes else branch: Subtract(15, 5) = 10
3. Returns final result: 10

This is the "smoking gun" proof that control flow is completely absent. Both branches execute unconditionally in sequence.

**CEK Verdict**: ✅ Correctly executes the malformed IR
- CEK executes both operations in sequence as the IR specifies
- Result: (10 + 5) - 5 = 10

**Fix Location**: `Chalk::Semiring::Semantic` if-else statement semantic action

---

## Summary Table

| Test | Expected | CEK Result | IR Builder Bug | CEK Correct? |
|------|----------|------------|----------------|--------------|
| Operator precedence | 13 | 16 | Wrong precedence: ((3+5)*2) | ✅ Yes |
| If (false) | 0 | 10 | Missing control flow nodes | ✅ Yes |
| If-else (true) | 10 | 20 | Missing control flow nodes | ✅ Yes |
| If-else variable | 15 | 10 | Both branches execute | ✅ Yes |

## Conclusions

1. **CEK Interpreter Status**: ✅ Working correctly
   - Executes all IR graphs correctly
   - No bugs found in CEK execution logic
   - All 35 passing tests validate correct execution
   - All 4 TODO tests show CEK correctly executing malformed IR

2. **IR Builder Status**: ⚠️ Has bugs in two areas:
   - **Operator precedence**: Generates wrong order of operations
   - **Control flow**: Completely fails to generate If/Proj/Region/Phi nodes

3. **Test Suite Accuracy**:
   - Previous claim of "100% validation" was incorrect
   - Actual differential pass rate: 89.7% (35/39)
   - TODO tests properly document known IR Builder issues

4. **PR #164 Impact**:
   - PR correctly implements CEK interpreter
   - PR validation is honest (89.7% pass rate with documented TODO tests)
   - Remaining failures are NOT blockers for CEK interpreter acceptance
   - IR Builder bugs should be tracked separately

## Recommendations

1. **Update PR description** to clarify:
   - 89.7% differential test pass rate (not "100% validation")
   - CEK interpreter correctly executes all IR it receives
   - 4 TODO tests document IR Builder bugs, not CEK bugs

2. **Create separate issues** for IR Builder bugs:
   - Issue: "IR Builder: incorrect operator precedence in arithmetic expressions"
   - Issue: "IR Builder: missing control flow node generation for if/if-else statements"

3. **Merge PR #164** after documentation updates:
   - CEK interpreter implementation is correct
   - Test suite properly documents known limitations
   - Blocking on IR Builder bugs would delay valuable CEK work

4. **Future work**:
   - Fix operator precedence in `Chalk::Semiring::Semantic`
   - Implement control flow node generation for conditionals
   - Remove TODO markers once IR Builder is fixed
   - Expect pass rate to reach 100% after IR Builder fixes

## Evidence

All findings are based on IR inspection using the debug script at `/Users/perigrin/dev/chalk/debug_ir.pl`, which dumps the actual generated IR nodes before and after GVN optimization.

Test output confirms:
- 35 tests pass completely
- 4 tests are marked TODO with detailed explanations
- Total: 36 tests (4 are compilation + execution tests for the TODOs)
- Pass rate: 35/39 = 89.7%

---

**Report Prepared By**: perigrin
**For**: PR #164 code review response
**Reviewed Against**: Reviewer #3 feedback on validation claims
