# Variant Usage Matrix - Detailed Analysis

## Usage Patterns by Variant

### R Variants (Right-associative / NonBrace contexts)

| Non-terminal | Used By | Purpose | Can Eliminate? |
|--------------|---------|---------|----------------|
| ExprAssignR | ExprComma, ExprCondR, etc. | Right-associative assignment | **NO** - Required |
| ExprCondR | ExprAssignR, ExprRangeR, etc. | Ternary right operand | **NO** - Required |
| ExprRangeR | ExprCondR | Range in NonBrace context | Maybe |
| ExprLogOrR | ExprRangeR | Logical OR in NonBrace | Maybe |
| ExprLogAndR | ExprLogOrR | Logical AND in NonBrace | Maybe |
| ExprBinOrR | ExprLogAndR | Binary OR in NonBrace | Maybe |
| ExprBinAndR | ExprBinOrR | Binary AND in NonBrace | Maybe |
| ExprEqR | ExprBinAndR | Equality in NonBrace | Maybe |
| ExprNeqR | ExprEqR | Inequality in NonBrace | Maybe |
| ExprShiftR | ExprNeqR | Shift in NonBrace | Maybe |
| ExprAddR | ExprShiftR | Addition in NonBrace | Maybe |
| ExprMulR | ExprAddR | Multiplication in NonBrace | Maybe |
| ExprRegexR | ExprMulR | Regex in NonBrace | Maybe |
| ExprUnaryR | ExprRegexR, ExprPowerR | Unary in NonBrace | Maybe |
| ExprPowerR | ExprUnaryR | **Right-associative power** | **NO** - Required |
| ExprIncR | ExprPowerR | Increment in NonBrace | Maybe |
| ExprArrowR | ExprIncR | Arrow in NonBrace | Maybe |
| ExprValueR | ExprArrowR | Terminal in NonBrace | Maybe |

**Key Finding**: Only 3 R variants are semantically required (AssignR, CondR, PowerR). The rest exist solely for the "NonBrace" chain.

### L Variants (Left-associative)

| Non-terminal | Used By | Purpose | Can Eliminate? |
|--------------|---------|---------|----------------|
| ExprAssignL | ExprComma, PrintExpr, etc. | Left context assignment | Keep |
| ExprCondL | ExprAssignL, etc. | Ternary left operand | Keep |
| ExprRangeL | ExprCondL | Range left-assoc | Keep |
| ExprLogOrL | ExprRangeL | Logical OR left-assoc | Keep |
| ExprLogAndL | ExprLogOrL | Logical AND left-assoc | Keep |
| ExprBinOrL | ExprLogAndL | Binary OR left-assoc | Keep |
| ExprBinAndL | ExprBinOrL | Binary AND left-assoc | Keep |
| ExprEqL | ExprBinAndL | Equality left-assoc | Keep |
| ExprNeqL | ExprEqL | Inequality left-assoc | Keep |
| ExprShiftL | ExprNeqL | Shift left-assoc | Keep |
| ExprAddL | ExprShiftL | Addition left-assoc | Keep |
| ExprMulL | ExprAddL | Multiplication left-assoc | Keep |
| ExprRegexL | ExprMulL | Regex left-assoc | Keep |
| ExprUnaryL | ExprRegexL | Unary operators | Keep |
| ExprPowerL | ExprUnaryL | Power (but left?) | Suspicious |
| ExprIncL | ExprPowerL | Increment left-assoc | Keep |
| ExprArrowL | ExprIncL | Arrow left-assoc | Keep |
| ExprValueL | ExprArrowL | Terminal values | Keep |

### 0 Variants (Non-associative / Bridge)

| Non-terminal | Used By | Purpose | Can Eliminate? |
|--------------|---------|---------|----------------|
| ExprCond0 | ExprAssignR/L, many places | Bridge/neutral ternary | Keep (maybe) |
| ExprRange0 | ExprCond0, ExprCondR/L | Bridge for range | Yes |
| ExprLogOr0 | ExprRange0, ExprRangeR/L | Bridge for logical OR | Yes |
| ExprLogAnd0 | ExprLogOr0 | Bridge for logical AND | Yes |
| ExprBinOr0 | ExprLogAnd0 | Bridge for binary OR | Yes |
| ExprBinAnd0 | ExprBinOr0 | Bridge for binary AND | Yes |
| ExprEq0 | ExprBinAnd0 | Bridge for equality | Yes |
| ExprNeq0 | ExprEq0, many places | Bridge for inequality | Yes |
| ExprShift0 | ExprNeq0, ExprNeqR/L | Bridge for shift | Yes |
| ExprAdd0 | ExprShift0 | Bridge for addition | Yes |
| ExprMul0 | ExprAdd0 | Bridge for multiplication | Yes |
| ExprRegex0 | ExprMul0 | Bridge for regex | Yes |
| ExprUnary0 | ExprRegex0 | Bridge for unary | Yes |
| ExprPower0 | ExprUnary0 | Bridge for power | Yes |
| ExprInc0 | ExprPower0 | Bridge for increment | Yes |
| ExprArrow0 | ExprInc0 | Bridge for arrow | Yes |
| ExprValue0 | ExprArrow0 | Bridge for values | Yes |

**Key Finding**: 0 variants are purely structural bridges, not semantic. All can be eliminated.

### U Variants (Uniform recursion)

| Non-terminal | Used By | Purpose | Can Eliminate? |
|--------------|---------|---------|----------------|
| ExprShiftU | ExprShift0/L/R | Left-recursive base | Merge into L |
| ExprAddU | ExprShiftU, ExprAdd0/L/R | Left-recursive base | Merge into L |
| ExprMulU | ExprAddU, ExprMul0/L/R | Left-recursive base | Merge into L |
| ExprRegexU | ExprMulU, ExprRegex0/L/R | Left-recursive base | Merge into L |
| ExprUnaryU | ExprRegexU | Unary recursion | Merge into L |
| ExprPowerU | ExprUnaryU | Power recursion | Special case |
| ExprIncU | ExprPowerU, all ExprPower* | Increment recursion | Merge into L |
| ExprArrowU | ExprIncU | Arrow recursion | Merge into L |
| ExprValueU | ExprArrowU | Terminal values | Merge into L |

**Key Finding**: U variants are implementation details for left-recursion. All can be merged into L.

## Critical Dependencies

### The NonBrace Chain
There's a complete parallel chain of R variants used to avoid consuming `{` as a hashref:
```
BlockLevelExpression → Expression → ExprNameOr → ... → ExprAssignR → ExprCondR →
ExprRangeR → ExprLogOrR → ... → ExprValueR
```

This chain exists because in contexts like:
- `print { a => 1 }` - should be hashref, not block
- `sub { {} }` - inner `{}` should be hashref, not block

### The 0 Bridge Pattern
The 0 variants serve as neutral bridges between L and R:
- `ExprAssignR → ExprCond0 OpAssign ExprAssignR` (uses 0 as left operand)
- `ExprAssignL → ExprCond0 OpAssign ExprAssignL` (uses 0 as left operand)

This suggests 0 variants prevent infinite recursion between L/R variants.

## Consolidation Safety Matrix

| Action | Risk | Benefit | Priority |
|--------|------|---------|----------|
| Merge U into L | Low | -8 non-terminals | High |
| Eliminate unused 0 variants | Low | -5 to -10 non-terminals | High |
| Eliminate bridge 0 variants | Medium | -5 to -8 non-terminals | Medium |
| Merge NonBrace R into L | High | -10 to -12 non-terminals | Low |
| Simplify ExprValue* variants | Low | -4 non-terminals | High |

## Recommended Approach

### Phase 1: Safe Eliminations (Day 1)
1. Merge all U variants into L variants (mechanical transform)
2. Remove ExprValueUU, ExprValueUR, ExprValueU0, ExprValueUL (consolidate to ExprValueU)
3. Test thoroughly
4. **Expected reduction**: 12 non-terminals

### Phase 2: 0 Variant Analysis (Day 2)
1. Identify which 0 variants are actually referenced
2. For unreferenced ones, remove immediately
3. For referenced ones, analyze if they can use L instead
4. **Expected reduction**: 8-10 non-terminals

### Phase 3: Conservative R Consolidation (Day 3)
1. Keep: ExprAssignR, ExprCondR, ExprPowerR (semantic requirements)
2. Analyze: Can NonBrace chain use a different approach?
3. Consider: Special "NonBraceExpression" entry point instead of full R chain
4. **Expected reduction**: 5-8 non-terminals

### Phase 4: Final Cleanup (Day 4)
1. Consolidate ExprNameOr, ExprNameAnd, ExprNameNot (single variants)
2. Simplify ExprComma (single variant)
3. Review and optimize rule ordering
4. **Expected reduction**: 2-3 non-terminals

## Total Expected Reduction

- **Current**: 72 non-terminals
- **After Phase 1**: 60 non-terminals (-12)
- **After Phase 2**: 50-52 non-terminals (-8 to -10)
- **After Phase 3**: 42-47 non-terminals (-5 to -8)
- **After Phase 4**: 40-44 non-terminals (-2 to -3)

**Final**: 40-44 non-terminals (39-44% reduction)

## Conservative Estimate

Being very conservative and keeping more R variants for safety:
- **Minimum reduction**: 72 → 45 non-terminals (37% reduction)
- **Chart explosion**: From O(4^n) to O(2.5^n)
- **Performance gain**: 40-50% faster parsing of dense expressions