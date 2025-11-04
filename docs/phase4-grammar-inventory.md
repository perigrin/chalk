# Phase 4 Grammar Inventory - Current State

## Summary

**Total Expression Rules:** 37 rules (from Expression down to Postfix)
**Precedence-Level Non-Terminals:** 13

This document inventories the current expression grammar before Phase 4 simplification.

## Precedence-Level Non-Terminals (Low to High Precedence)

These non-terminals encode operator precedence in the grammar structure:

1. **Expression** - Entry point (delegates to Assignment)
2. **Assignment** - Assignment operators: `=`, `+=`, `-=`, etc.
3. **Ternary** - Ternary conditional: `? :`
4. **LogicalOr** - Logical OR: `||`, `or`, `//`
5. **LogicalAnd** - Logical AND: `&&`, `and`
6. **Comparison** - Comparison: `<`, `>`, `==`, `!=`, `eq`, `ne`, `isa`
7. **RegexMatch** - Regex match: `=~`, `!~`
8. **Range** - Range operator: `..`
9. **Concatenation** - String concatenation: `.`
10. **Additive** - Addition/subtraction: `+`, `-`
11. **Multiplicative** - Multiplication/division: `*`, `/`
12. **Unary** - Unary prefix: `!`, `not`, `-`, `+`, `++`, `--`, `\`
13. **Postfix** - Postfix operators: `++`, `--`

## Current Grammar Rules by Category

### 1. Expression Entry (1 rule)
```
Expression -> Assignment
```

### 2. Assignment Operators (3 rules)
**Non-terminal:** Assignment
**Associativity:** Right
**Rules:**
```
Assignment -> Ternary                                      # Pass-through
Assignment -> Ternary WS_OPT '=' WS_OPT Assignment         # Simple assign
Assignment -> Ternary WS_OPT %ASSIGN_OP% WS_OPT Assignment # Compound assign
```
**Operators:** `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `&=`, `|=`, `^=`, `.=`, `<<=`, `>>=`, `&&=`, `||=`, `//=`

### 3. Ternary Operator (2 rules)
**Non-terminal:** Ternary
**Associativity:** Right
**Rules:**
```
Ternary -> LogicalOr                                                      # Pass-through
Ternary -> LogicalOr WS_OPT '?' WS_OPT Expression WS_OPT ':' WS_OPT Ternary
```
**Operators:** `?:`

### 4. Logical OR Operators (4 rules)
**Non-terminal:** LogicalOr
**Associativity:** Left
**Rules:**
```
LogicalOr -> LogicalAnd                              # Pass-through
LogicalOr -> LogicalOr WS_OPT '||' WS_OPT LogicalAnd
LogicalOr -> LogicalOr WS_OPT 'or' WS_OPT LogicalAnd
LogicalOr -> LogicalOr WS_OPT '//' WS_OPT LogicalAnd
```
**Operators:** `||`, `or`, `//`

### 5. Logical AND Operators (3 rules)
**Non-terminal:** LogicalAnd
**Associativity:** Left
**Rules:**
```
LogicalAnd -> Comparison                              # Pass-through
LogicalAnd -> LogicalAnd WS_OPT '&&' WS_OPT Comparison
LogicalAnd -> LogicalAnd WS_OPT 'and' WS_OPT Comparison
```
**Operators:** `&&`, `and`

### 6. Comparison Operators (4 rules)
**Non-terminal:** Comparison
**Associativity:** Left (but chained in Perl)
**Rules:**
```
Comparison -> RegexMatch                                           # Pass-through
Comparison -> Comparison WS_OPT %NUM_COMPARE_OP% WS_OPT RegexMatch
Comparison -> Comparison WS_OPT %STRING_COMPARE_OP% WS_OPT RegexMatch
Comparison -> Comparison WS_OPT 'isa' WS_OPT QualifiedIdentifier
```
**Operators:** `<`, `>`, `<=`, `>=`, `==`, `!=`, `<=>`, `lt`, `gt`, `le`, `ge`, `eq`, `ne`, `cmp`, `~~`, `isa`

### 7. Regex Match Operators (2 rules)
**Non-terminal:** RegexMatch
**Associativity:** Left
**Rules:**
```
RegexMatch -> Range                                    # Pass-through
RegexMatch -> RegexMatch WS_OPT %REGEX_MATCH_OP% WS_OPT Range
```
**Operators:** `=~`, `!~`

### 8. Range Operator (2 rules)
**Non-terminal:** Range
**Associativity:** Nonassoc (cannot chain)
**Rules:**
```
Range -> Concatenation                         # Pass-through
Range -> Range WS_OPT '..' WS_OPT Concatenation
```
**Operators:** `..`

### 9. String Concatenation (2 rules)
**Non-terminal:** Concatenation
**Associativity:** Left
**Rules:**
```
Concatenation -> Additive                                # Pass-through
Concatenation -> Concatenation WS_OPT '.' WS_OPT Additive
```
**Operators:** `.`

### 10. Additive Operators (3 rules)
**Non-terminal:** Additive
**Associativity:** Left
**Rules:**
```
Additive -> Multiplicative                              # Pass-through
Additive -> Additive WS_OPT '+' WS_OPT Multiplicative
Additive -> Additive WS_OPT '-' WS_OPT Multiplicative
```
**Operators:** `+`, `-`

### 11. Multiplicative Operators (3 rules)
**Non-terminal:** Multiplicative
**Associativity:** Left
**Rules:**
```
Multiplicative -> Unary                          # Pass-through
Multiplicative -> Multiplicative WS_OPT '*' WS_OPT Unary
Multiplicative -> Multiplicative WS_OPT '/' WS_OPT Unary
```
**Operators:** `*`, `/`

### 12. Unary Prefix Operators (8 rules)
**Non-terminal:** Unary
**Associativity:** Right
**Rules:**
```
Unary -> Postfix            # Pass-through
Unary -> '!' WS_OPT Unary
Unary -> 'not' WS_OPT Unary
Unary -> '-' WS_OPT Unary
Unary -> '+' WS_OPT Unary
Unary -> '++' WS_OPT Unary
Unary -> '--' WS_OPT Unary
Unary -> '\\' WS_OPT Unary  # Reference operator
```
**Operators:** `!`, `not`, `-`, `+`, `++`, `--`, `\`

### 13. Postfix Operators (3 rules)
**Non-terminal:** Postfix
**Associativity:** Left
**Rules:**
```
Postfix -> Primary         # Pass-through
Postfix -> Variable '++'
Postfix -> Variable '--'
```
**Operators:** `++`, `--` (postfix)

## Semantic Action Files

Each precedence-level non-terminal has a corresponding semantic action class:

- `lib/Chalk/Grammar/Chalk/Rule/Expression.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Assignment.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Ternary.pm`
- `lib/Chalk/Grammar/Chalk/Rule/LogicalOr.pm`
- `lib/Chalk/Grammar/Chalk/Rule/LogicalAnd.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Comparison.pm`
- `lib/Chalk/Grammar/Chalk/Rule/RegexMatch.pm` (may not exist)
- `lib/Chalk/Grammar/Chalk/Rule/Range.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Concatenation.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Additive.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Multiplicative.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Unary.pm`
- `lib/Chalk/Grammar/Chalk/Rule/Postfix.pm`

## Rule Count Analysis

| Category | Current Rules | Pass-through Rules | Operator Rules |
|----------|---------------|-------------------|----------------|
| Expression | 1 | 1 | 0 |
| Assignment | 3 | 1 | 2 |
| Ternary | 2 | 1 | 1 |
| LogicalOr | 4 | 1 | 3 |
| LogicalAnd | 3 | 1 | 2 |
| Comparison | 4 | 1 | 3 |
| RegexMatch | 2 | 1 | 1 |
| Range | 2 | 1 | 1 |
| Concatenation | 2 | 1 | 1 |
| Additive | 3 | 1 | 2 |
| Multiplicative | 3 | 1 | 2 |
| Unary | 8 | 1 | 7 |
| Postfix | 3 | 1 | 2 |
| **TOTAL** | **37** | **13** | **24** |

**Key Insights:**
- 13 pass-through rules (one per precedence level) - pure overhead
- 24 operator rules (actual work)
- Total: 37 rules encoding precedence in grammar structure

## Phase 4 Simplification Target

After Phase 4, we aim for ~15-20 rules by:

1. **Eliminating pass-through rules** (13 rules removed)
2. **Flattening precedence hierarchy** - replace with semantic categories:
   - `BinaryOperation` - all binary operators
   - `UnaryOperation` - all unary operators
   - `TernaryOperation` - ternary conditional
   - `Primary` - terminals and grouping

**Estimated simplified grammar:**
```
Expression -> BinaryOperation | UnaryOperation | TernaryOperation | Primary

BinaryOperation -> Expression OP Expression
  where OP in {+, -, *, /, ., ==, !=, <, >, &&, ||, =, ...}

UnaryOperation -> OP Expression
  where OP in {!, not, -, +, ++, --, \}

TernaryOperation -> Expression '?' Expression ':' Expression

Primary -> Literal | Variable | '(' Expression ')' | ...
```

**Expected result:** ~15-20 rules (50-60% reduction from 37 rules)

## Operator Categories for Incremental Implementation

Phase 4 will be done incrementally by operator category:

### Category 1: Arithmetic (5 operator rules → 1 BinaryOp rule)
- Current: Additive (3 rules), Multiplicative (3 rules) = 6 rules total
- Operators: `+`, `-`, `*`, `/`
- Target: Collapse into single `BinaryOperation` rule

### Category 2: String Operations (3 operator rules → BinaryOp)
- Current: Concatenation (2 rules), Range (2 rules) = 4 rules total
- Operators: `.`, `..`

### Category 3: Comparison (3 operator rules → BinaryOp)
- Current: Comparison (4 rules) = 4 rules total
- Operators: `<`, `>`, `<=`, `>=`, `==`, `!=`, `<=>`, `eq`, `ne`, `cmp`, `isa`

### Category 4: Regex Match (1 operator rule → BinaryOp)
- Current: RegexMatch (2 rules) = 2 rules total
- Operators: `=~`, `!~`

### Category 5: Logical (5 operator rules → BinaryOp)
- Current: LogicalOr (4 rules), LogicalAnd (3 rules) = 7 rules total
- Operators: `&&`, `||`, `and`, `or`, `//`

### Category 6: Assignment (2 operator rules → BinaryOp)
- Current: Assignment (3 rules) = 3 rules total
- Operators: `=`, `+=`, `-=`, `*=`, etc.

### Category 7: Unary (7 operator rules → UnaryOp)
- Current: Unary (8 rules) = 8 rules total
- Operators: `!`, `not`, `-`, `+`, `++`, `--`, `\`

### Category 8: Postfix (2 operator rules → special handling)
- Current: Postfix (3 rules) = 3 rules total
- Operators: `++`, `--` (postfix)

### Category 9: Ternary (1 operator rule → TernaryOp)
- Current: Ternary (2 rules) = 2 rules total
- Operator: `?:`

## Implementation Strategy

For each category:
1. Update grammar rules to use semantic non-terminals
2. Update corresponding semantic action classes
3. Run tests to ensure 100% pass rate
4. Commit changes before moving to next category

**Critical:** Precedence semiring is already integrated and will handle validation for the flattened grammar.
