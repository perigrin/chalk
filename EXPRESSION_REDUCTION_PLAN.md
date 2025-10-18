# Expression Hierarchy Reduction Plan

## Summary for Review

perigrin, I've analyzed the Chalk grammar's expression hierarchy and identified significant redundancy in the 4-variant system. The grammar currently has **72 expression non-terminals** which causes exponential chart growth when parsing dense array literals (like the grammar file itself with 635 consecutive arrays).

**Key findings:**
- Only 3 R variants are semantically required (assignment, power, ternary)
- All U variants are redundant (just implementation details for left-recursion)
- Most 0 variants are unnecessary bridges
- We can safely reduce from 72 to ~40-45 non-terminals (40-44% reduction)

## Problem Analysis

### Root Cause of Chart Explosion
When parsing `[ 'X' => [...] ]` repeated 635 times:
1. Each `[...]` triggers full Expression hierarchy prediction
2. 72 non-terminals get predicted for each expression
3. Nested structure creates multiplicative explosion: O(n × 4^depth)
4. Parser bogs down in combinatorial explosion

### Current Variant System

The grammar implements 4 variants for most expression levels:
- **L**: Left-associative (standard for most operators)
- **R**: Right-associative + "NonBrace" contexts (avoid `{}` ambiguity)
- **0**: Non-associative bridges between L and R
- **U**: Uniform recursion (implementation detail for left-recursion)

Example of redundancy:
```perl
# Current addition rules (4 variants, but semantically identical):
[ 'ExprAddU' => [ 'ExprAddU', 'OpAdd', 'ExprMulU' ] ],  # U: left-recursive
[ 'ExprAddL' => [ 'ExprAddU', 'OpAdd', 'ExprMulL' ] ],  # L: uses U as base
[ 'ExprAddR' => [ 'ExprAddU', 'OpAdd', 'ExprMulR' ] ],  # R: for NonBrace
[ 'ExprAdd0' => [ 'ExprAddU', 'OpAdd', 'ExprMul0' ] ],  # 0: bridge

# All these represent left-associative addition!
```

## Proposed Solution

### Phase 1: Eliminate U Variants (Low Risk) ✓

**What**: Merge all U variants directly into L variants
**Why**: U variants are just an implementation detail for left-recursion
**How**: Make L variants directly left-recursive

```perl
# Before (2 rules for left-associative addition):
[ 'ExprAddU' => [ 'ExprAddU', 'OpAdd', 'ExprMulU' ] ],
[ 'ExprAddL' => [ 'ExprAddU', 'OpAdd', 'ExprMulL' ] ],

# After (1 rule):
[ 'ExprAddL' => [ 'ExprAddL', 'OpAdd', 'ExprMulL' ] ],
```

**Affected non-terminals** (8 to eliminate):
- ExprShiftU, ExprAddU, ExprMulU, ExprRegexU
- ExprUnaryU, ExprPowerU, ExprIncU, ExprArrowU

**Risk**: Low - mechanical transformation, no semantic change

### Phase 2: Remove Redundant 0 Variants (Low-Medium Risk) ✓

**What**: Eliminate 0 variants that just bridge to other variants
**Why**: They add no semantic value, just parser states
**How**: Replace references to 0 variants with L variants

```perl
# Before (0 variant just bridges):
[ 'ExprAdd0' => [ 'ExprAddU', 'OpAdd', 'ExprMul0' ] ],
[ 'ExprAdd0' => ['ExprMul0'] ],

# After (use L directly):
# Just remove - callers will use ExprAddL instead
```

**Affected non-terminals** (10-14 to eliminate):
- Most can go: ExprRange0, ExprLogOr0, ExprLogAnd0, ExprBinOr0, ExprBinAnd0
- Keep for now: ExprCond0 (ternary uses it specially)
- Analyze usage: ExprNeq0, ExprShift0 (used as left operand in some rules)

**Risk**: Medium - need to verify each 0 variant's usage pattern

### Phase 3: Consolidate NonBrace R Variants (Medium Risk) ⚠️

**What**: Reduce the parallel R chain used for brace disambiguation
**Why**: Most R variants aren't right-associative, just avoiding `{` ambiguity
**How**: Create targeted solution for brace contexts

Current "NonBrace" chain exists to handle:
```perl
print { a => 1 }     # Should parse as hashref argument
sub { {} }           # Inner {} should be empty hashref, not block
```

**Options**:
1. Keep minimal R chain (just where needed)
2. Use different disambiguation approach
3. Conservative: keep more R variants for safety

**Affected non-terminals** (5-10 to potentially eliminate):
- Keep: ExprAssignR (truly right-associative)
- Keep: ExprPowerR (truly right-associative)
- Keep: ExprCondR (ternary special case)
- Analyze: Other R variants in the chain

**Risk**: Medium-High - brace disambiguation is critical

### Phase 4: Cleanup Redundant ExprValue Variants (Low Risk) ✓

**What**: Consolidate 9 ExprValue variants to 3-4
**Why**: Excessive terminal variants
**How**: Merge similar variants

```perl
# Current (9 variants!):
ExprValueL, ExprValueR, ExprValue0, ExprValueU
ExprValueUL, ExprValueUR, ExprValueU0, ExprValueUU

# After (3-4 variants):
ExprValueL, ExprValueR, ExprValue
```

**Risk**: Low - terminal consolidation is safe

## Implementation Steps

### Day 1: Setup and Phase 1
1. Create test file `t/grammar/expression-associativity.t`:
   ```perl
   # Test right-associativity preserved
   is_parsed('$a = $b = 1', '... = ($b = 1) ...');
   is_parsed('2 ** 3 ** 4', '... ** (3 ** 4) ...');

   # Test left-associativity preserved
   is_parsed('1 + 2 + 3', '(1 + 2) + 3 ...');

   # Test brace disambiguation
   is_parsed('print { a => 1 }', 'hashref not block');
   ```

2. Implement Phase 1 (merge U into L)
3. Run full test suite
4. Measure chart size on grammar file

### Day 2: Phase 2
1. Analyze 0 variant usage:
   ```bash
   grep -n "Expr.*0[^A-Za-z]" lib/Chalk/Grammar/Perl.pm
   ```

2. Remove unused 0 variants
3. Replace used 0 references with L
4. Test thoroughly

### Day 3: Phase 3 (Conservative)
1. Keep essential R variants (Assign, Power, Cond)
2. Analyze each other R variant
3. Test brace disambiguation thoroughly
4. Consider keeping more R variants if risky

### Day 4: Validation
1. Parse grammar file - measure improvement
2. Run full test suite
3. Benchmark performance
4. Document changes

## Expected Outcome

### Metrics
- **Non-terminals**: 72 → 40-45 (40-44% reduction)
- **Chart explosion**: O(4^n) → O(2.5^n)
- **Parse time**: 40-50% faster on grammar file
- **Memory**: 50-60% reduction in peak usage

### Semantic Preservation
- All associativity rules maintained
- Brace disambiguation preserved
- No change to language accepted
- All tests continue to pass

## Risk Mitigation

1. **Git branch**: `fix-issue-12-reduce-variants`
2. **Incremental commits**: After each phase
3. **Test coverage**: Add specific associativity tests
4. **Benchmarking**: Measure at each step
5. **Conservative approach**: Keep more variants if uncertain

## Questions for Review

1. **Comfort level**: Are you comfortable with the phased approach?
2. **Priority**: Should we prioritize safety or performance?
3. **R variants**: How important is the NonBrace chain? Would you prefer we keep all R variants for safety?
4. **Testing**: Any specific edge cases you're concerned about?

## Recommendation

I recommend proceeding with Phases 1 and 2 (U and 0 elimination) as they're low risk with good benefit. For Phase 3 (R variants), we should be conservative and only eliminate R variants we're certain are redundant.

The 40-44% reduction in non-terminals should significantly improve parser performance while maintaining complete semantic correctness.