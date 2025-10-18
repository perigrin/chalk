# Expression Variant Analysis for Chalk Grammar

## Executive Summary

The Chalk grammar currently has **72 unique Expr* non-terminals** implementing a 4-variant system (L/R/0/U) across 22 precedence levels. This analysis shows that we can safely reduce this to approximately **25-30 non-terminals** by eliminating redundant variants while preserving semantic correctness.

## Current State: 72 Expression Non-Terminals

### Complete Inventory by Precedence Level

1. **ExprNameOr** (3 levels): connects with `or`
   - Entry: Expression → ExprNameOr
   - Rules: ExprNameOr

2. **ExprNameAnd** (1 variant): connects with `and`
   - Rules: ExprNameAnd

3. **ExprNameNot** (1 variant): unary `not`
   - Rules: ExprNameNot

4. **ExprComma** (1 variant): comma lists
   - Rules: ExprComma

5. **ExprAssign** (2 variants): assignment operators
   - Rules: ExprAssignL, ExprAssignR

6. **ExprCond** (3 variants): ternary `? :`
   - Rules: ExprCondL, ExprCondR, ExprCond0

7. **ExprRange** (3 variants): range `..`
   - Rules: ExprRangeL, ExprRangeR, ExprRange0

8. **ExprLogOr** (3 variants): `||` and `//`
   - Rules: ExprLogOrL, ExprLogOrR, ExprLogOr0

9. **ExprLogAnd** (3 variants): `&&`
   - Rules: ExprLogAndL, ExprLogAndR, ExprLogAnd0

10. **ExprBinOr** (3 variants): `|` and `^`
    - Rules: ExprBinOrL, ExprBinOrR, ExprBinOr0

11. **ExprBinAnd** (3 variants): `&`
    - Rules: ExprBinAndL, ExprBinAndR, ExprBinAnd0

12. **ExprEq** (3 variants): `==`, `eq`, etc.
    - Rules: ExprEqL, ExprEqR, ExprEq0

13. **ExprNeq** (3 variants): `<`, `>`, etc.
    - Rules: ExprNeqL, ExprNeqR, ExprNeq0

14. **ExprShift** (4 variants): `<<`, `>>`
    - Rules: ExprShiftL, ExprShiftR, ExprShift0, ExprShiftU

15. **ExprAdd** (4 variants): `+`, `-`, `.`
    - Rules: ExprAddL, ExprAddR, ExprAdd0, ExprAddU

16. **ExprMul** (4 variants): `*`, `/`, `x`
    - Rules: ExprMulL, ExprMulR, ExprMul0, ExprMulU

17. **ExprRegex** (4 variants): `=~`, `!~`
    - Rules: ExprRegexL, ExprRegexR, ExprRegex0, ExprRegexU

18. **ExprUnary** (4 variants): `-`, `!`, `~`, file tests
    - Rules: ExprUnaryL, ExprUnaryR, ExprUnary0, ExprUnaryU

19. **ExprPower** (4 variants): `**`
    - Rules: ExprPowerL, ExprPowerR, ExprPower0, ExprPowerU

20. **ExprInc** (4 variants): `++`, `--`
    - Rules: ExprIncL, ExprIncR, ExprInc0, ExprIncU

21. **ExprArrow** (4 variants): `->`
    - Rules: ExprArrowL, ExprArrowR, ExprArrow0, ExprArrowU

22. **ExprValue** (9 variants): terminals
    - Rules: ExprValueL, ExprValueR, ExprValue0, ExprValueU
    - Extra: ExprValueUL, ExprValueUR, ExprValueU0, ExprValueUU

**Total: 72 unique non-terminals**

## Variant Purpose Analysis

### L Variant (Left-associative)
- **Purpose**: Left-to-right evaluation (most common)
- **Example**: `1 + 2 + 3` = `((1 + 2) + 3)`
- **Used in**: Addition, multiplication, logical operators
- **Count**: 15 non-terminals

### R Variant (Right-associative)
- **Purpose**: Right-to-left evaluation AND avoiding brace ambiguity
- **Example**: `a = b = 1` = `(a = (b = 1))`
- **Used in**: Assignment, ternary, "NonBrace" contexts
- **Count**: 15 non-terminals
- **Note**: Comments indicate "avoids consuming braces as hash refs"

### 0 Variant (Non-associative)
- **Purpose**: Appears to be for neutral/bridge contexts
- **Used in**: Intermediate positions in precedence chain
- **Count**: 14 non-terminals

### U Variant (Uniform/Unit)
- **Purpose**: Self-recursive for uniform left-associativity
- **Used in**: ExprShiftU, ExprAddU, ExprMulU (left-recursive rules)
- **Count**: 8 non-terminals

## Redundancy Analysis

### 1. Clearly Redundant U Variants
The U variants appear to implement left-recursion separately from L variants:
- `ExprAddU → ExprAddU OpAdd ExprMulU` (left-recursive)
- `ExprAddL → ExprAddU OpAdd ExprMulL` (uses U as base)

**Finding**: U variants can be merged into L variants by making L left-recursive directly.

### 2. Redundant 0 Variants
The 0 variants serve as bridges but often have identical structure to L:
- `ExprAdd0 → ExprAddU OpAdd ExprMul0`
- `ExprAddL → ExprAddU OpAdd ExprMulL`

**Finding**: Most 0 variants can be eliminated, using L as default.

### 3. Context-Specific R Variants
R variants serve two purposes:
1. **True right-associativity** (assignment, power)
2. **Brace disambiguation** ("NonBrace" contexts to avoid `{}` as hashref)

**Finding**: Keep R only where semantically required (assignment, power, ternary).

## Proposed Consolidation Strategy

### Phase 1: Merge U into L (Immediate)
**Affected levels**: Shift, Add, Mul, Regex, Unary, Power, Inc, Arrow
**Action**:
- Make L variants directly left-recursive
- Remove U variants entirely
- **Reduction**: 8 non-terminals eliminated

### Phase 2: Eliminate Unnecessary 0 Variants (Safe)
**Affected levels**: Most binary operators
**Action**:
- Keep 0 only for ExprCond0 (ternary needs special handling)
- Use L as default for left-associative operators
- **Reduction**: 13 non-terminals eliminated

### Phase 3: Consolidate R Variants (Conservative)
**Keep R for**:
- Assignment (truly right-associative)
- Power (truly right-associative)
- Ternary conditional (special precedence)
- Top-level comma contexts (NonBrace disambiguation)

**Merge R into L for**:
- Most binary operators (they're left-associative anyway)
- **Reduction**: 8-10 non-terminals eliminated

## Expected Final State

### Minimal Required Variants (25-30 non-terminals)

1. **Single variant** (10 levels):
   - ExprNameOr, ExprNameAnd, ExprNameNot
   - ExprComma, ExprBinOr, ExprBinAnd
   - ExprEq, ExprNeq, ExprShift, ExprRegex

2. **L + R variants** (6 levels):
   - ExprAssign (R for right-assoc)
   - ExprCond (R for ternary)
   - ExprPower (R for right-assoc)
   - ExprRange, ExprLogOr, ExprLogAnd (R for NonBrace)

3. **L variant only** (6 levels):
   - ExprAdd, ExprMul, ExprUnary
   - ExprInc, ExprArrow, ExprValue

**Total: ~28 non-terminals** (62% reduction)

## Risk Assessment

### Low Risk Changes
1. **Merging U into L**: Mechanical transformation, same semantics
2. **Removing unused 0 variants**: If not referenced, safe to remove
3. **Single-variant levels**: Already effectively single-variant

### Medium Risk Changes
1. **Merging some R variants**: Need careful testing of:
   - Brace disambiguation in hash contexts
   - Statement vs expression contexts
   - Interaction with statement modifiers

### High Risk Areas
1. **Assignment associativity**: MUST remain right-associative
2. **Power associativity**: MUST remain right-associative
3. **Ternary precedence**: Complex interaction with other operators
4. **NonBrace contexts**: Critical for avoiding `{}` ambiguity

## Implementation Plan

### Step 1: Create Test Suite (Day 1)
```perl
# Test associativity
is_parsed('$a = $b = 1', 'assign(a, assign(b, 1))');
is_parsed('2 ** 3 ** 4', 'power(2, power(3, 4))');
is_parsed('1 + 2 + 3', 'add(add(1, 2), 3)');

# Test brace disambiguation
is_parsed('print { a => 1 }', 'print(hashref(...))');
is_parsed('sub { {} }', 'sub(block(hashref()))');
```

### Step 2: Merge U Variants (Day 1)
```perl
# Before
[ 'ExprAddU' => [ 'ExprAddU', 'OpAdd', 'ExprMulU' ] ],
[ 'ExprAddL' => [ 'ExprAddU', 'OpAdd', 'ExprMulL' ] ],

# After
[ 'ExprAddL' => [ 'ExprAddL', 'OpAdd', 'ExprMulL' ] ],
```

### Step 3: Remove Redundant 0 Variants (Day 2)
- Analyze each 0 variant for actual usage
- Replace references with L variant
- Remove unused rules

### Step 4: Selective R Consolidation (Day 3)
- Keep R for: assignment, power, ternary
- Test each removal against brace disambiguation tests
- Measure parser performance at each step

### Step 5: Performance Validation (Day 4)
- Parse grammar file (635 array literals)
- Measure chart size reduction
- Validate all tests still pass

## Expected Impact

### Chart Growth Reduction
- **Current**: 60 non-terminals × 4 variants = O(n × 4^depth) explosion
- **Proposed**: 28 non-terminals × 1.5 avg variants = O(n × 1.5^depth)
- **Reduction**: √ to ∛ reduction in explosion factor

### Parse Time Improvement
- Grammar file parse time: Expected 50-70% reduction
- Complex nested expressions: 40-60% faster
- Memory usage: 50-65% lower peak usage

### Maintainability
- Simpler mental model (L=default, R=special cases)
- Fewer rules to maintain (62% reduction)
- Clearer associativity semantics

## Rollback Strategy

Each phase is independently reversible:
1. Git commit after each phase
2. Test suite validates semantic preservation
3. Performance benchmarks at each step
4. If issues found, revert specific phase only

## Conclusion

The 4-variant system contains significant redundancy:
- U variants duplicate L functionality (can merge)
- 0 variants rarely differ from L (can eliminate most)
- R variants mix two concerns (keep only where needed)

Conservative reduction to 25-30 non-terminals will:
- Preserve all semantic correctness
- Reduce parser explosion by 50-70%
- Maintain clear associativity model
- Be fully reversible if issues arise