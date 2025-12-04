# Chapter 12 Session 2: Float Operations & Optimizations

## Implementation Plan for Issue #326

### Task 1: Implement AddF (Float Addition)
- Write test file `t/ir-node-addf.t` following TDD
- Implement `lib/Chalk/IR/Node/AddF.pm`
- Include peephole optimizations:
  - Constant folding: `2.5 + 3.5 = 6.0`
  - Identity: `x + 0.0 = x`
- Pattern after Add.pm but using Float types
- Verify all tests pass

### Task 2: Implement SubF (Float Subtraction)
- Write test file `t/ir-node-subf.t` following TDD
- Implement `lib/Chalk/IR/Node/SubF.pm`
- Include peephole optimizations:
  - Constant folding: `5.5 - 2.5 = 3.0`
  - Identity: `x - 0.0 = x`
  - Zero: `x - x = 0.0`
- Verify all tests pass

### Task 3: Implement MulF (Float Multiplication)
- Write test file `t/ir-node-mulf.t` following TDD
- Implement `lib/Chalk/IR/Node/MulF.pm`
- Include peephole optimizations:
  - Constant folding: `2.5 * 3.0 = 7.5`
  - Identity: `x * 1.0 = x`
  - Zero: `x * 0.0 = 0.0`
- Verify all tests pass

### Task 4: Implement DivF (Float Division)
- Write test file `t/ir-node-divf.t` following TDD
- Implement `lib/Chalk/IR/Node/DivF.pm`
- Include peephole optimizations:
  - Constant folding: `7.5 / 2.5 = 3.0`
  - Identity: `x / 1.0 = x`
  - Zero: `0.0 / x = 0.0` (where x != 0)
- Verify all tests pass

### Task 5: Implement MinusF (Float Unary Negation)
- Write test file `t/ir-node-minusf.t` following TDD
- Implement `lib/Chalk/IR/Node/MinusF.pm`
- Include peephole optimizations:
  - Constant folding: `-2.5 = -2.5`
  - Double negation: `-(-x) = x`
- Pattern after integer Minus if it exists, otherwise create unary node
- Verify all tests pass

### Task 6: Implement EQF (Float Equality Comparison)
- Write test file `t/ir-node-eqf.t` following TDD
- Implement `lib/Chalk/IR/Node/EQF.pm`
- Include peephole optimizations:
  - Constant folding: `2.5 == 2.5 = 1`, `2.5 == 3.0 = 0`
  - Self-comparison: `x == x = 1`
- Returns integer (0 or 1) from boolean type
- Verify all tests pass

### Task 7: Implement LTF (Float Less Than Comparison)
- Write test file `t/ir-node-ltf.t` following TDD
- Implement `lib/Chalk/IR/Node/LTF.pm`
- Include peephole optimizations:
  - Constant folding: `2.5 < 3.0 = 1`, `3.0 < 2.5 = 0`
  - Self-comparison: `x < x = 0`
- Returns integer (0 or 1) from boolean type
- Verify all tests pass

### Task 8: Implement LEF (Float Less Than or Equal Comparison)
- Write test file `t/ir-node-lef.t` following TDD
- Implement `lib/Chalk/IR/Node/LEF.pm`
- Include peephole optimizations:
  - Constant folding: `2.5 <= 3.0 = 1`, `2.5 <= 2.5 = 1`
  - Self-comparison: `x <= x = 1`
- Returns integer (0 or 1) from boolean type
- Verify all tests pass

## Success Criteria
- All 8 node types implemented with full test coverage
- All peephole optimizations working correctly
- Full test suite passes at 100%
- Code follows existing patterns (Add.pm, ConstantF.pm)
- TDD followed for each task (test first, then implementation)

## References
- `/Users/perigrin/dev/chalk/lib/Chalk/IR/Node/Add.pm` - Integer addition pattern
- `/Users/perigrin/dev/chalk/lib/Chalk/IR/Node/ConstantF.pm` - Float constant pattern
- `/Users/perigrin/dev/chalk/lib/Chalk/IR/Type/Float.pm` - Float type system
- Issue #326 requirements
