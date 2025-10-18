# Expression Hierarchy Transformation Plan

## Current State
- **72 expression non-terminals**
- Categories:
  - U variants (8): Handle left-recursion
  - 0 variants (18): Bridge/neutral nodes
  - L variants (19): List context / left-associative
  - R variants (19): NonBrace context / right-associative
  - Base (8): Core expression types

## Target State
- **~22-25 expression non-terminals**
- Simplified categories:
  - Base variants: One per precedence level (left-associative, directly left-recursive)
  - R variants: Only for truly right-associative operators (assignment, power, ternary)
  - Essential support: ExprComma, ExpressionList, Expression entry point, etc.

## Transformation Strategy

### Key Principles
1. **Marpa handles left-recursion natively** - no need for separate U variants
2. **Most Perl operators are left-associative** - collapse to single variant
3. **Only 3 operators are right-associative**: `=` (assignment), `**` (power), `?:` (ternary)
4. **Precedence is structural** - maintain nesting order

### Phase 1: Eliminate U Variants (8 → 0)

For each U variant, merge its rules into the base variant:

**Before:**
```perl
[ 'ExprShiftU' => [ 'ExprShiftU', 'OpShift', 'ExprAddU' ] ],
[ 'ExprShiftU' => ['ExprAddU'] ],
[ 'ExprShiftL' => [ 'ExprShiftU', 'OpShift', 'ExprAddL' ] ],
[ 'ExprShiftR' => [ 'ExprShiftU', 'OpShift', 'ExprAddR' ] ],
```

**After:**
```perl
[ 'ExprShift' => [ 'ExprShift', 'OpShift', 'ExprAdd' ] ],  # Direct left-recursion
[ 'ExprShift' => ['ExprAdd'] ],
```

Apply to: ExprShiftU, ExprAddU, ExprMulU, ExprRegexU, ExprUnaryU, ExprPowerU, ExprIncU, ExprArrowU

### Phase 2: Eliminate 0 Variants (18 → 0)

Replace all references to Expr*0 with Expr* (base):

**Before:**
```perl
[ 'ExprNeqR' => [ 'ExprShift0', 'OpInequal', 'ExprShiftR' ] ],
[ 'ExprNeq0' => [ 'ExprShift0', 'OpInequal', 'ExprShift0' ] ],
```

**After:**
```perl
[ 'ExprNeq' => [ 'ExprShift', 'OpInequal', 'ExprShift' ] ],
```

Apply to: All *0 variants

### Phase 3: Consolidate L/R for Left-Associative Operators (19+19 → ~10)

For operators that are truly left-associative (everything except assignment, power, ternary):

**Before:**
```perl
[ 'ExprLogOrL' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAndL' ] ],
[ 'ExprLogOrR' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAndR' ] ],
```

**After:**
```perl
[ 'ExprLogOr' => [ 'ExprLogOr', 'OpLogOr', 'ExprLogAnd' ] ],  # Left-recursive
[ 'ExprLogOr' => ['ExprLogAnd'] ],
```

### Phase 4: Keep Right-Associative Operators Explicit

**Assignment (right-associative):**
```perl
[ 'ExprAssign' => [ 'ExprCond', 'OpAssign', 'ExprAssign' ] ],  # Right-recursive
[ 'ExprAssign' => ['ExprCond'] ],
```

**Power (right-associative):**
```perl
[ 'ExprPower' => [ 'ExprInc', 'OpPower', 'ExprPower' ] ],  # Right-recursive
[ 'ExprPower' => ['ExprInc'] ],
```

**Ternary (right-associative):**
```perl
[ 'ExprCond' => [ 'ExprRange', '?', 'ExprRange', ':', 'ExprCond' ] ],  # Right-recursive
[ 'ExprCond' => ['ExprRange'] ],
```

### Phase 5: Handle NonBrace Chain

The NonBrace R chain (lines 301-451) appears to be for avoiding brace ambiguity in certain contexts (print, list operators).

**Analysis needed:**
- Check all references to ExprAssignR, ExprCondR, etc.
- Determine if we can simplify or eliminate this chain
- Likely keep a minimal R chain only where semantically necessary

### Phase 6: Consolidate ExprValue* Variants (9 → 2-3)

**Current ExprValue variants:**
- ExprValueU, ExprValue0, ExprValueL, ExprValueR
- ExprValueU0, ExprValueUL, ExprValueUR, ExprValueUU

**Simplified:**
- ExprValue (base)
- Possibly one variant for keyword expressions

## Expected Result

### Final Expression Hierarchy (~22-25 non-terminals)

1. Expression (entry)
2. ExprNameOr
3. ExprNameAnd
4. ExprNameNot
5. ExprComma
6. ExprAssign (right-associative)
7. ExprCond (ternary, right-associative)
8. ExprRange
9. ExprLogOr
10. ExprLogAnd
11. ExprBinOr
12. ExprBinAnd
13. ExprEq
14. ExprNeq
15. ExprShift
16. ExprAdd
17. ExprMul
18. ExprRegex
19. ExprUnary
20. ExprPower (right-associative)
21. ExprInc
22. ExprArrow
23. ExprValue
24. ExpressionList (support)
25. Possibly ExprAssignR/ExprCondR if NonBrace context is necessary

Total: ~23-25 non-terminals (vs. current 72)

## Implementation Order

1. Start with innermost operators (ExprArrow, ExprInc, ExprPower)
2. Work outward through precedence chain
3. Test after each major change
4. Commit at stable points
