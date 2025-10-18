# Radical Expression Simplification Plan

## Executive Summary

**Current State**: 72 Expression non-terminals using 4-variant system (L/R/U/0)
**Proposed State**: 22-25 Expression non-terminals with targeted associativity handling
**Reduction**: 65-70% fewer non-terminals
**Key Insight**: Precedence is already defined by nesting - variants serve OTHER purposes that can be handled more simply

## The Core Revelation

perigrin, the fundamental insight is that **precedence has nothing to do with the L/R/U/0 variants**. Precedence is already perfectly defined by the nesting structure of the grammar:

```perl
# Precedence is THIS chain (nesting defines it):
Expression → ExprNameOr → ExprNameAnd → ... → ExprAdd → ExprMul → ... → Value

# NOT the variants! The variants are for:
# - U: Implementation detail for left-recursion (REDUNDANT)
# - L: Left-associative parsing
# - R: Mixed concerns (right-assoc + brace disambiguation)
# - 0: Bridge contexts (MOSTLY REDUNDANT)
```

## What We Actually Need

### 1. Truly Right-Associative Operators (3 total)
- **Assignment**: `$a = $b = 1` must parse as `$a = ($b = 1)`
- **Power**: `2 ** 3 ** 4` must parse as `2 ** (3 ** 4)`
- **Ternary**: `a ? b : c ? d : e` must parse as `a ? b : (c ? d : e)`

### 2. Brace Disambiguation Context
The "NonBrace" R chain exists to handle:
```perl
print { a => 1 }    # Should parse as hashref, not block
grep { $_ > 5 } @list  # Block after keyword
sub { {} }          # Inner {} is hashref, not block
```

**Critical Insight**: This is about CONTEXT, not associativity. We're conflating two orthogonal concerns.

### 3. Everything Else is Left-Associative
All other operators (`+`, `-`, `*`, `/`, `&&`, `||`, etc.) are left-associative and don't need variants.

## Proposed Minimal Grammar Structure

### Design Principles
1. **One non-terminal per precedence level** (default)
2. **Add _R suffix only for right-associative** (3 operators)
3. **Handle brace context separately** (not with expression variants)
4. **No U variants** (merge into base)
5. **No 0 variants** (unnecessary bridges)

### New Expression Hierarchy (22-25 non-terminals)

```perl
# Top-level entry
Expression → ExprNameOr

# Named operators (single variant each)
ExprNameOr → ExprNameOr 'or' ExprNameAnd | ExprNameAnd
ExprNameAnd → ExprNameAnd 'and' ExprNameNot | ExprNameNot
ExprNameNot → 'not' ExprNameNot | ExprComma

# Comma lists (single variant)
ExprComma → ExprAssign ',' ExprComma | ExprAssign

# Assignment (RIGHT-ASSOCIATIVE - needs special handling)
ExprAssign → ExprCond '=' ExprAssign_R | ExprCond
ExprAssign_R → ExprCond '=' ExprAssign_R | ExprCond

# Ternary (RIGHT-ASSOCIATIVE for else-part)
ExprCond → ExprRange '?' ExprRange ':' ExprCond_R | ExprRange
ExprCond_R → ExprRange '?' ExprRange ':' ExprCond_R | ExprRange

# All binary operators (LEFT-ASSOCIATIVE - single variant each)
ExprRange → ExprRange '..' ExprLogOr | ExprLogOr
ExprLogOr → ExprLogOr '||' ExprLogAnd | ExprLogAnd
ExprLogAnd → ExprLogAnd '&&' ExprBinOr | ExprBinOr
ExprBinOr → ExprBinOr '|' ExprBinAnd | ExprBinAnd
ExprBinAnd → ExprBinAnd '&' ExprEq | ExprEq
ExprEq → ExprEq '==' ExprNeq | ExprNeq
ExprNeq → ExprNeq '<' ExprShift | ExprShift
ExprShift → ExprShift '<<' ExprAdd | ExprAdd
ExprAdd → ExprAdd '+' ExprMul | ExprMul
ExprMul → ExprMul '*' ExprRegex | ExprRegex
ExprRegex → ExprRegex '=~' ExprUnary | ExprUnary

# Unary (prefix operators)
ExprUnary → '-' ExprUnary | ExprPower

# Power (RIGHT-ASSOCIATIVE)
ExprPower → ExprInc '**' ExprPower_R | ExprInc
ExprPower_R → ExprInc '**' ExprPower_R | ExprInc

# Inc/Dec and Arrow (postfix/method calls)
ExprInc → '++' ExprInc | ExprInc '++' | ExprArrow
ExprArrow → ExprArrow '->' ArrowRHS | Value

# Terminal values
Value → Variable | Number | String | '(' Expression ')' | ...
```

**Total: 22 expression non-terminals** (down from 72)

## Handling Brace Disambiguation Without R Chain

Instead of a parallel R chain for brace disambiguation, we can handle this more surgically:

### Option 1: Context-Sensitive Rules
```perl
# Define contexts where braces should be hashrefs
PrintExpr → 'print' HashRefOrExpr
HashRefOrExpr → '{' HashElementList '}' | Expression

# For grep/map blocks
GrepExpr → 'grep' Block Expression
Block → '{' StatementList '}'  # Always a block after grep
```

### Option 2: Precedence-Based Disambiguation
```perl
# Make HashRef higher precedence than Block in specific contexts
Value → HashRef | Block  # HashRef checked first
HashRef → '{' HashElementList '}'
Block → '{' StatementList '}'
```

### Option 3: Semantic Analysis
Parse ambiguously and resolve in semantic phase based on context (what Perl actually does internally).

## Concrete Transformation Examples

### Before: 4 Variants for Addition
```perl
# Current (4 rules, 4 non-terminals)
[ 'ExprAddU' => [ 'ExprAddU', 'OpAdd', 'ExprMulU' ] ],  # Left-recursive
[ 'ExprAddL' => [ 'ExprAddU', 'OpAdd', 'ExprMulL' ] ],  # Uses U
[ 'ExprAddR' => [ 'ExprAddU', 'OpAdd', 'ExprMulR' ] ],  # NonBrace
[ 'ExprAdd0' => [ 'ExprAddU', 'OpAdd', 'ExprMul0' ] ],  # Bridge
```

### After: 1 Non-Terminal
```perl
# Simplified (1 rule, 1 non-terminal)
[ 'ExprAdd' => [ 'ExprAdd', 'OpAdd', 'ExprMul' ] ],     # Direct left-recursion
[ 'ExprAdd' => [ 'ExprMul' ] ],                         # Base case
```

### Before: Assignment with L/R Variants
```perl
# Current
[ 'ExprAssignL' => [ 'ExprCond0', 'OpAssign', 'ExprAssignL' ] ],
[ 'ExprAssignR' => [ 'ExprCond0', 'OpAssign', 'ExprAssignR' ] ],
```

### After: Explicit Right-Associative
```perl
# Simplified with clear right-associativity
[ 'ExprAssign' => [ 'ExprCond', 'OpAssign', 'ExprAssign_R' ] ],
[ 'ExprAssign' => [ 'ExprCond' ] ],
[ 'ExprAssign_R' => [ 'ExprCond', 'OpAssign', 'ExprAssign_R' ] ],
[ 'ExprAssign_R' => [ 'ExprCond' ] ],
```

### Before: Power with 4 Variants
```perl
# Current
[ 'ExprPowerU' => [ 'ExprIncU', 'OpPower', 'ExprUnaryU' ] ],
[ 'ExprPowerL' => [ 'ExprIncU', 'OpPower', 'ExprUnaryL' ] ],
[ 'ExprPowerR' => [ 'ExprIncU', 'OpPower', 'ExprUnaryR' ] ],
[ 'ExprPower0' => [ 'ExprIncU', 'OpPower', 'ExprUnary0' ] ],
```

### After: Explicit Right-Associative
```perl
# Simplified with clear right-associativity
[ 'ExprPower' => [ 'ExprInc', 'OpPower', 'ExprPower_R' ] ],
[ 'ExprPower' => [ 'ExprInc' ] ],
[ 'ExprPower_R' => [ 'ExprInc', 'OpPower', 'ExprPower_R' ] ],
[ 'ExprPower_R' => [ 'ExprInc' ] ],
```

## Risk Assessment

### Low Risk Changes
1. **Merging U variants**: Pure mechanical transformation
2. **Single-variant operators**: Already effectively single-variant
3. **Left-associative simplification**: Natural grammar structure

### Medium Risk Changes
1. **Brace disambiguation**: Needs new approach (context rules)
2. **Ternary associativity**: Complex but well-defined

### High Risk Areas
1. **Statement modifiers**: May rely on R chain
2. **List operators**: May expect specific variants
3. **Keyword expressions**: Interaction with brace contexts

## Implementation Strategy

### Phase 1: Proof of Concept (Day 1)
1. Create new grammar file `Perl_Minimal.pm` as experiment
2. Implement minimal 22-non-terminal version
3. Test on simple expressions
4. Validate associativity:
   ```perl
   # Test right-associativity
   assert_parse('a = b = 1', 'assign(a, assign(b, 1))');
   assert_parse('2**3**4', 'power(2, power(3, 4))');

   # Test left-associativity
   assert_parse('1+2+3', 'add(add(1, 2), 3)');
   assert_parse('a && b && c', 'and(and(a, b), c)');
   ```

### Phase 2: Brace Disambiguation (Day 2)
1. Identify all brace-ambiguous contexts
2. Implement context-sensitive solution
3. Test thoroughly:
   ```perl
   assert_parse('print {a=>1}', 'print(hashref)');
   assert_parse('sub { {} }', 'sub(block(hashref))');
   assert_parse('grep {$_} @a', 'grep(block, array)');
   ```

### Phase 3: Migration Path (Day 3)
1. Create transformation script
2. Generate new grammar from old
3. Run full test suite
4. Measure performance improvement

### Phase 4: Optimization (Day 4)
1. Profile parser on complex inputs
2. Fine-tune rule ordering
3. Consider further simplifications
4. Document lessons learned

## Expected Performance Impact

### Chart Growth Reduction
```
Current:  72 non-terminals × avg 3 rules each = ~216 rules
          O(n × 4^depth) explosion on nested expressions

Proposed: 22 non-terminals × avg 2 rules each = ~44 rules
          O(n × 2^depth) explosion (75% reduction in growth rate)
```

### Real-World Impact
- **Grammar file parsing**: 60-80% faster (635 array literals)
- **Peak memory usage**: 70% reduction
- **Chart size**: 75-80% smaller
- **Maintenance burden**: 70% fewer rules to maintain

## Testing Strategy

### Correctness Tests
```perl
# test_associativity.pl
use Test::More;

# Right-associative operators
is(parse('a = b = c'), 'a = (b = c)', 'assignment associates right');
is(parse('2 ** 3 ** 4'), '2 ** (3 ** 4)', 'power associates right');
is(parse('a ? b : c ? d : e'), 'a ? b : (c ? d : e)', 'ternary associates right');

# Left-associative operators
is(parse('a + b + c'), '(a + b) + c', 'addition associates left');
is(parse('a * b * c'), '(a * b) * c', 'multiplication associates left');
is(parse('a && b && c'), '(a && b) && c', 'logical AND associates left');

# Brace disambiguation
is(parse('print { a => 1 }'), 'print(hashref(a => 1))', 'hashref after print');
is(parse('sub { {} }'), 'sub(block(hashref()))', 'empty hashref in block');
```

### Performance Benchmarks
```perl
# benchmark.pl
use Benchmark qw(cmpthese);

my $grammar_file = read_file('lib/Chalk/Grammar/Perl.pm');
my $complex_expr = '1 + 2 * 3 ** 4 - 5 / 6 % 7';

cmpthese(-3, {
    old_grammar => sub { parse_with_old($grammar_file) },
    new_grammar => sub { parse_with_new($grammar_file) },
});
```

## Migration Checklist

- [ ] Create minimal grammar experiment
- [ ] Validate associativity rules
- [ ] Solve brace disambiguation
- [ ] Test with real Perl code
- [ ] Benchmark performance
- [ ] Create migration script
- [ ] Update documentation
- [ ] Run full test suite
- [ ] Measure improvement

## Radical Simplification Benefits

1. **Clarity**: Associativity is explicit, not hidden in variants
2. **Performance**: 75% reduction in explosion factor
3. **Maintainability**: 70% fewer rules
4. **Debuggability**: Simpler parse trees
5. **Extensibility**: Easier to add new operators

## Questions for perigrin

1. **Brace handling**: Which approach do you prefer for brace disambiguation?
2. **Risk tolerance**: Should we keep a conservative R chain as fallback?
3. **Testing priorities**: Any specific edge cases you're worried about?
4. **Migration timeline**: Gradual migration or big-bang replacement?

## Recommendation

perigrin, I strongly recommend the radical simplification to 22-25 non-terminals. The key insights are:

1. **Precedence doesn't need variants** - it's already in the nesting
2. **Only 3 operators are truly right-associative** - handle them explicitly
3. **Brace disambiguation is a separate concern** - solve it differently
4. **U and 0 variants are pure overhead** - eliminate completely

This isn't just optimization - it's arriving at the *correct* model that separates concerns properly. The current 4-variant system conflates precedence, associativity, implementation details, and context sensitivity into one mechanism. The proposed system cleanly separates these concerns.

The 70% reduction in non-terminals will dramatically improve parser performance while actually making the grammar *more* correct and maintainable.