# Precedence Semiring

## Overview

The Precedence Semiring is a specialized semiring implementation in Chalk that validates operator precedence during parsing without relying on grammar-encoded precedence rules or SPPF (Shared Packed Parse Forest) dependencies. It uses a declarative, table-driven approach to perform bottom-up precedence validation during the parsing process, ensuring that expressions like `1 + 2 * 3` parse correctly as `1 + (2*3)` rather than `(1+2) * 3`.

**Location**: `/Users/perigrin/dev/chalk/lib/Chalk/Semiring/Precedence.pm`

**Key Tests**:
- `/Users/perigrin/dev/chalk/t/semiring/precedence.t` - Core semiring behavior
- `/Users/perigrin/dev/chalk/t/precedence-arithmetic.t` - Arithmetic operator validation
- `/Users/perigrin/dev/chalk/t/integration/precedence-semiring-composite.t` - Integration with Composite semiring

## Design Philosophy

### Table-Driven Declarative Approach

Traditional parser generators encode operator precedence directly into the grammar, making precedence rules implicit and difficult to maintain. The Precedence Semiring separates this concern by using a declarative precedence table:

```perl
my @precedence_table = (
    { ops => ['**'], assoc => 'right' },         # 0 - highest precedence
    { ops => ['*', '/', '%'], assoc => 'left' }, # 3
    { ops => ['+', '-', '.'], assoc => 'left' }, # 4 - lower precedence
    # ... more operators
);
```

**Key Principle**: Lower index = higher precedence. The operator `*` at index 3 binds tighter than `+` at index 4.

### Bottom-Up Validation

Rather than encoding precedence into grammar productions, the semiring validates precedence relationships during parsing:

1. **On Token Scan** (`on_scan()`): When an operator token is scanned, it's marked as "active" - representing the current rule's operator
2. **On Rule Completion** (`on_complete()`): When a sub-expression completes, its operator becomes "passive" - representing a child expression's operator
3. **During Combination** (`multiply()`): When combining elements, the semiring validates that active (parent) operators don't incorrectly contain passive (child) operators of lower precedence

This approach allows the grammar to remain simple and ambiguous while the semiring disambiguates during parsing.

## The Active/Passive Model

The core innovation of the Precedence Semiring is the active/passive model for tracking operator context.

### Active Operators

**Created by**: `on_scan()` when scanning operator tokens
**Represents**: The operator of the CURRENT rule being parsed (the "parent" in the parse tree)
**Marked with**: `is_active => 1` flag

When the parser scans an operator token like `+` or `*`, the semiring creates an element marking this operator as active. This indicates "we are currently building a parse tree node for this operator."

### Passive Operators

**Created by**: `on_complete()` when a sub-expression finishes
**Represents**: Operators from completed child expressions
**Marked with**: `is_active => 0` flag

When a sub-expression completes (e.g., the `2*3` part of `1 + 2 * 3`), the semiring extracts the operator from that completed expression and marks it as passive. This indicates "this operator came from a child expression that has already been fully parsed."

### Validation Rule

**Parent-Child Constraint**: A parent operator (active) can only contain child operators (passive) of EQUAL OR HIGHER precedence.

This rule prevents incorrect groupings:
- ✅ VALID: `+` (parent, lower precedence) containing `*` (child, higher precedence) → `1 + (2*3)`
- ❌ INVALID: `*` (parent, higher precedence) containing `+` (child, lower precedence) → `(1+2) * 3`

The intuition: If a higher-precedence operator tries to contain a lower-precedence operator as its child, something went wrong - the lower-precedence operator should have been the parent instead.

## Detailed Walk-Through: `1 + 2 * 3`

Let's trace how the Precedence Semiring validates the canonical example `1 + 2 * 3`.

### Precedence Table Setup

```perl
# Index 3: multiplication (higher precedence)
{ ops => ['*'], assoc => 'left' }

# Index 4: addition (lower precedence)
{ ops => ['+'], assoc => 'left' }
```

Remember: Lower index = higher precedence, so `*` (index 3) binds tighter than `+` (index 4).

### Parse Tree Option 1: Correct Parse `1 + (2*3)`

```
      +          <- Active operator (scanned)
     / \
    1   *        <- Passive operator (from completed sub-expr)
       / \
      2   3
```

**Step-by-step validation**:

1. Parse `2 * 3`:
   - Scan `*` token → `on_scan()` creates element with `operator='*', precedence_level=3, is_active=1`
   - Complete multiplication → `on_complete()` converts to `operator='*', precedence_level=3, is_active=0` (passive)

2. Combine with addition:
   - Scan `+` token → `on_scan()` creates element with `operator='+', precedence_level=4, is_active=1`
   - Multiply active `+` with passive `*` (from step 1)
   - Validation check (line 146-163 in Precedence.pm):
     ```perl
     # self is active (+), other is passive (*)
     if ($self_active && !$other_active) {
         # Valid if self (parent) has lower or equal precedence than other (child)
         if ($self_level < $other_level) {
             # Parent has higher precedence - INVALID
             return invalid;
         }
         # Parent has lower or equal precedence - VALID
         return valid;
     }
     ```
   - Check: `$self_level (4) < $other_level (3)` → FALSE
   - Result: VALID (parent `+` at level 4 has lower precedence than child `*` at level 3)

### Parse Tree Option 2: Incorrect Parse `(1+2) * 3`

```
      *          <- Active operator (scanned)
     / \
    +   3        <- Passive operator (from completed sub-expr)
   / \
  1   2
```

**Step-by-step validation**:

1. Parse `1 + 2`:
   - Scan `+` token → `on_scan()` creates active `+` element
   - Complete addition → `on_complete()` converts to passive `+` element

2. Combine with multiplication:
   - Scan `*` token → `on_scan()` creates active `*` element with `precedence_level=3`
   - Receive passive `+` element (from step 1) with `precedence_level=4`
   - Check: `$new_level (3) > $existing_level (4)` → TRUE (line 368)
   - Result: INVALID - parent `*` at level 3 has HIGHER precedence than child `+` at level 4

This is detected early in `on_scan()` when the active `*` operator encounters an existing passive `+`:

```perl
# Line 356-381: Early validation in on_scan()
if (defined($existing_op) && !$element->is_active) {
    # New operator (active/parent) vs existing operator (passive/child)
    my $new_level = $op_info->{level};

    if ($new_level > $existing_level) {
        # New has LOWER precedence - invalid!
        return PrecedenceElement->new(valid => 0, ...);
    }
}
```

### Result

- Option 1 (`1 + (2*3)`): VALID
- Option 2 (`(1+2) * 3`): INVALID

When the parser's `add()` operation combines these alternatives, it chooses the valid one (Option 1), ensuring correct precedence.

## Architecture

### Class Structure

```
Chalk::Semiring::Precedence (main semiring)
    ├─ field: precedence_table (array of {assoc, ops})
    ├─ field: operator_index (hash: operator -> {level, assoc})
    ├─ field: mul_id (identity for multiply = valid element)
    └─ field: add_id (identity for add = invalid element)

Chalk::Semiring::PrecedenceElement (semiring element)
    ├─ field: valid (0 or 1)
    ├─ field: operator (string, e.g., '+', '*')
    ├─ field: precedence_level (integer index into table)
    ├─ field: associativity (left, right, nonassoc, chained, chain/na)
    ├─ field: is_active (1 if from on_scan, 0 if from on_complete)
    └─ field: operator_index (reference to parent's index)
```

### Key Methods

#### `on_scan($item, $element, $pos, $matched_value, $pattern_name)`

**Purpose**: Called when a token is scanned during parsing
**Lines**: 336-398

**Behavior**:
1. Checks if `$matched_value` matches an operator in the precedence table
2. Filters out identifiers and attributes (`:attr`) to avoid false positives
3. Creates an active element with `is_active => 1`
4. **Critical validation**: If the existing element contains a passive operator, validates that the new active operator (parent) can legally contain it (child)
5. Returns the operator element or the unchanged element if not an operator

**Bug Fix (Issue #361)**: Line 368 had an inverted comparison. The correct check is:
```perl
if ($new_level > $existing_level) {
    # New has LOWER precedence - INVALID
}
```

Previously, it incorrectly used `<`, which would invalidate the opposite case.

#### `on_complete($completed_item, $completed_element, $metadata_element)`

**Purpose**: Called when a rule completes
**Lines**: 400-468

**Behavior**:
1. Preserves validity state from `$completed_element` (critical - don't wipe invalid state)
2. **Parentheses handling**: If the rule starts with `(`, clears operator info to "seal off" inner precedence context
3. **Expression rule whitelist**: Only preserves operator info for expression-related rules (Expression, BinaryExpression, ArithmeticOp, etc.)
4. Extracts operator from completed element and marks it passive (`is_active => 0` by default)
5. Returns new element with preserved or cleared operator info

**Important**: The `is_active` flag defaults to 0, making operators passive unless explicitly set active by `on_scan()`.

#### `multiply($x, $y)`

**Purpose**: Combines two precedence elements in sequence
**Lines**: 68-242 (element method)

**Behavior**:
1. Boolean AND for validation: if either is invalid, result is invalid
2. Preserves operator info even when invalid (prevents premature Composite short-circuit)
3. Handles four operator combination cases:
   - Both have no operator → return plain valid element
   - Only one has operator → preserve that operator's info
   - Both have operators → validate based on active/passive status
   - Both active or both passive → use traditional precedence rules
4. For active/passive combinations, enforces parent-child constraint
5. For same precedence level, checks associativity rules (nonassoc, chained, chain/na)

**Precedence Validation Logic**:
```
Active (parent) + Passive (child):
    Valid if: parent_level >= child_level
    Invalid if: parent_level < child_level

Intuition: Parents must have lower or equal precedence numbers
          (which means higher or equal precedence rank)
```

#### `add($other, $swap)`

**Purpose**: Chooses between alternative parses
**Lines**: 46-66 (element method)

**Behavior**:
1. Returns the valid alternative if exactly one is valid
2. If both invalid, returns `$other` (add identity)
3. If both valid, prefers `$self` (first alternative)
4. **Critical contract**: Returns `$self` or `$other` directly (not copies) for reference equality checking by Composite semiring

This method is where ambiguous parses are resolved based on precedence validation.

## Associativity Rules

The semiring supports multiple associativity types:

### Left Associativity (`left`)

Operators chain left-to-right: `a + b + c` parses as `(a+b)+c`

**Examples**: `+`, `-`, `*`, `/`, most binary operators

### Right Associativity (`right`)

Operators chain right-to-left: `a ** b ** c` parses as `a**(b**c)`

**Examples**: `**` (exponentiation), `=` (assignment), `?:` (ternary)

### Non-Associative (`nonassoc`)

Operators cannot chain: `a < b < c` is invalid

**Example**: Some comparison operators in certain contexts

### Chained Comparisons (`chained`)

Operators can chain but must maintain directional consistency:
- `a < b < c` is valid (all "less than" direction)
- `a < b > c` is invalid (mixed directions)

**Examples**: `<`, `>`, `<=`, `>=`, `lt`, `gt`, `le`, `ge`

**Implementation** (lines 223-232):
```perl
if ($self_assoc eq 'chained') {
    my $self_dir = _operator_direction($self_op);    # 'less' or 'greater'
    my $other_dir = _operator_direction($other_op);

    if (defined($self_dir) && defined($other_dir) && $self_dir ne $other_dir) {
        return invalid;  # Mixed directions not allowed
    }
}
```

### Chain/Non-Associative (`chain/na`)

Context-dependent chaining behavior

**Example**: `..`, `...` (range operators)

## Integration with Composite Semiring

The Precedence Semiring is typically used in combination with SPPF (parse forest) and Semantic (evaluation) semirings via the Composite pattern.

### Reference Equality Contract

The Composite semiring uses reference equality to determine which derivation "won" the precedence validation:

```perl
# In Composite::add()
my $prec_result = $prec_self->add($prec_other);

# Check which derivation Precedence chose
my $use_self = $prec_result == $prec_self;    # Reference equality!
my $use_other = $prec_result == $prec_other;

if ($use_self) {
    return $self;  # Use self's elements for ALL semirings
} elsif ($use_other) {
    return $other;  # Use other's elements for ALL semirings
}
```

This ensures that when Precedence invalidates a parse alternative, the Semantic semiring doesn't contribute values from that invalid parse. The coordination prevents semantic evaluation of syntactically invalid parse trees.

### Typical Configuration

```perl
my $sppf_sr = Chalk::Semiring::SPPF->new();
my $precedence_sr = Chalk::Semiring::Precedence->new(
    precedence_table => \@perl_precedence_table
);
my $semantic_sr = Chalk::Semiring::Semantic->new(grammar => $grammar);

my $composite_sr = Chalk::Semiring::Composite->new(
    semirings => [$precedence_sr, $sppf_sr, $semantic_sr]
);
```

**Note**: Precedence must be first in the array to act as the "leader" for the coordinated add operation.

## Parentheses and Precedence Context

Parentheses "seal off" the inner precedence context, preventing operators inside parentheses from interacting with operators outside.

### The Problem

Without special handling, `(1 + 2) * 3` could fail validation if the passive `+` from the completed `(1+2)` expression encounters the active `*`:

```
Passive +: precedence_level=4 (lower precedence)
Active *:  precedence_level=3 (higher precedence)

Check: * (parent) trying to contain + (child)
       3 < 4 → parent has higher precedence → INVALID!
```

### The Solution

When a rule starting with `(` completes, `on_complete()` clears the operator info:

```perl
# Lines 414-419
my $rhs = $completed_item->rule->rhs;
if ($rhs && $rhs->@* > 0 && $rhs->[0] eq '(') {
    return Chalk::Semiring::PrecedenceElement->new(
        valid => $was_valid,
        operator_index => $operator_index
    );  # No operator info - parentheses seal context
}
```

Now `(1+2)` completes with no operator, so it behaves like a primary value:

```
No passive operator in (1+2) result
Active *: precedence_level=3

No precedence conflict - VALID!
```

This allows `(1 + 2) * 3` to parse correctly as `multiply((1+2), 3)` where the parenthesized expression is opaque to precedence rules.

## Common Patterns and Edge Cases

### Pattern 1: Chained Operators of Same Precedence

```perl
# 1 + 2 + 3 → (1+2)+3 (left-associative)
```

Both active or both passive, same precedence level → falls through to "valid" (lines 236-241).

### Pattern 2: Mixed Precedence Chains

```perl
# 1 + 2 * 3 + 4 → 1 + (2*3) + 4
```

The `*` binds first (higher precedence), becomes passive. Both `+` operators are active at different points and contain the passive `*` result (valid: lower precedence containing higher).

### Pattern 3: Identifiers vs Operators

The semiring must distinguish between operator tokens and identifier tokens to avoid treating variable names that happen to match operator strings as operators:

```perl
# Lines 343-346
my $is_identifier = defined($pattern_name) && $pattern_name eq 'IDENTIFIER';
my $is_attribute = $token_str =~ m/^:\w/ && $token_str ne '::';

if (!$is_identifier && !$is_attribute) {
    # Check if it's an operator
}
```

Without this check, a variable named `x` could be confused with the string repetition operator `x`.

### Pattern 4: Expression Rule Whitelist

To prevent unrelated operators from being compared (e.g., the `:` in a hash key vs the `?:` ternary operator), `on_complete()` only preserves operator info for expression-related rules:

```perl
# Lines 423-438
my @expression_rules = qw(
    Expression BinaryExpression ArithmeticExpression
    ComparisonExpression LogicalExpression
    ArithmeticOp ComparisonOp LogicalOp
    ConcatenationOp RangeOp
    Unary Postfix
);

my $is_expression = grep { $rule_name eq $_ } @expression_rules;

if (!$is_expression) {
    # Clear operator info for non-expression rules
    return PrecedenceElement->new(valid => $was_valid, ...);
}
```

This prevents "operator leakage" into non-operator contexts.

## Evolution and History

The Precedence Semiring evolved through several design iterations:

### Phase 1: Initial Implementation (Nov 3, 2025)

- Basic precedence validation using semiring operations
- SPPF dependency for extracting operators from parse trees
- Direct tree walking to find operators

**Limitation**: Tight coupling to SPPF made testing difficult and violated separation of concerns.

### Phase 2: SPPF Integration Refinement (Nov 13, 2025)

- Better SPPF integration for operator extraction
- PackedNode traversal for alternative disambiguation
- Early validation logic in `multiply()`

**Limitation**: Still required SPPF structure; couldn't validate precedence independently.

### Phase 3: Token Type Distinction (Nov 15, 2025)

- Added identifier filtering to avoid treating variable names as operators
- Pattern name checking (`IDENTIFIER` vs operator tokens)
- Attribute token filtering (`:attr` vs `::`)

**Impact**: Fixed false positives where variables like `x` or `lt` were confused with operators.

### Phase 4: Active/Passive Model (Nov 30, 2025)

**Major redesign** introducing the active/passive distinction:

- `on_scan()` marks operators as active (current rule's operator)
- `on_complete()` marks operators as passive (from sub-expressions)
- Validation based on parent-child relationships instead of left-right position

**Impact**: Eliminated SPPF dependency; enabled pure precedence validation without parse tree structure.

### Phase 5: Issue #199 Fix (Nov 30, 2025)

**Problem**: Composite semiring called `add()` before `on_complete()` on some derivations, causing incomplete validation.

**Solution**: Modified parser to ensure all derivations receive `on_complete()` before combining via `add()`.

**Impact**: Guaranteed that passive operators are properly marked before precedence comparison.

### Phase 6: Parentheses Support (Nov 30, 2025)

**Problem**: `(1 + 2) * 3` failed validation because the passive `+` inside parentheses conflicted with the active `*` outside.

**Solution**: Clear operator context when completing rules starting with `(`, making parenthesized expressions opaque to precedence rules.

**Impact**: Parentheses now correctly override precedence, allowing forced grouping.

### Phase 7: Issue #361 Fix (Date TBD)

**Problem**: Inverted comparison in `on_scan()` line 368 caused incorrect validation.

**Bug**:
```perl
if ($new_level < $existing_level) {  # WRONG
```

**Fix**:
```perl
if ($new_level > $existing_level) {  # CORRECT
```

**Impact**: Fixed cases where higher-precedence operators incorrectly failed to contain lower-precedence child expressions.

## Debugging Tips

### Enable Debug Output

Uncomment the debug line in Composite.pm (line 54) to trace coordination decisions:

```perl
warn "COORD: self(v" . $prec_self->valid . ") vs other(v" . $prec_other->valid
     . ") => use_self=$use_self, use_other=$use_other";
```

### Inspect Element State

Use `to_string()` to examine precedence elements:

```perl
my $elem = $precedence_sr->one();
say $elem->to_string();  # "valid" or "Prec(+*:4)" (operator, active flag, level)
```

The `*` suffix indicates active operators: `Prec(+*:4)` means active `+` at level 4.

### Check Validity

```perl
if (!$element->valid) {
    warn "Invalid precedence: " . $element->to_string();
}
```

### Trace on_scan and on_complete

Add temporary debug output to track operator lifecycle:

```perl
method on_scan(...) {
    warn "SCAN: $matched_value -> active" if $op_info;
    ...
}

method on_complete(...) {
    warn "COMPLETE: " . ($operator // 'none') . " -> passive";
    ...
}
```

### Common Failure Patterns

1. **All parses invalid**: Check that precedence table is loaded correctly and operator_index is populated

2. **Wrong parse chosen**: Verify active/passive marking - operators from `on_scan()` should be active, from `on_complete()` should be passive

3. **Parentheses fail**: Ensure `on_complete()` clears operator info for rules starting with `(`

4. **Identifier confusion**: Verify pattern name filtering in `on_scan()` - identifiers should not be treated as operators

## Performance Considerations

### Operator Index Lookup

The operator index is built once in `ADJUST` and provides O(1) lookup:

```perl
ADJUST {
    my %index;
    for my $i (0 .. $precedence_table->@* - 1) {
        for my $op ($entry->{ops}->@*) {
            $index{$op} = { level => $i, assoc => $entry->{assoc} };
        }
    }
    $operator_index = \%index;
}
```

### Identity Elements

Identity elements (`mul_id`, `add_id`) are created once and reused:

```perl
$add_id = PrecedenceElement->new(valid => 0, ...);  # Invalid
$mul_id = PrecedenceElement->new(valid => 1, ...);  # Valid
```

Avoid creating new identity elements in hot paths - use `$self->one()` and `$self->zero()`.

### Reference Equality

The Composite coordination relies on reference equality (`==`), not deep equality:

```perl
# FAST: pointer comparison
if ($prec_result == $prec_self) { ... }

# SLOW: would require deep comparison
# if ($prec_result->equals($prec_self)) { ... }
```

Never create copies in `add()` - always return `$self` or `$other` directly.

## Testing

### Unit Tests

**File**: `/Users/perigrin/dev/chalk/t/semiring/precedence.t`

Tests core element operations (multiply, add) with mock elements.

### Integration Tests

**File**: `/Users/perigrin/dev/chalk/t/precedence-arithmetic.t`

Tests end-to-end parsing with actual Chalk grammar:

```perl
{ code => 'return 1 + 2 * 3;', expected => 7, desc => 'add first 1+(2*3)' }
{ code => 'return 2 * 3 + 1;', expected => 7, desc => 'multiply first (2*3)+1' }
{ code => 'return (1 + 2) * 3;', expected => 9, desc => 'parentheses: (1+2)*3' }
```

### Composite Integration Tests

**File**: `/Users/perigrin/dev/chalk/t/integration/precedence-semiring-composite.t`

Tests coordination between Precedence, SPPF, and Semantic semirings via Composite pattern.

### Test Timeout

Some tests require extended timeout (120s) for complex parsing:

```perl
# In prove command
timeout => 120
```

## Related Files

- **Composite Semiring**: `/Users/perigrin/dev/chalk/lib/Chalk/Semiring/Composite.pm`
- **SPPF Semiring**: `/Users/perigrin/dev/chalk/lib/Chalk/Semiring/SPPF.pm`
- **Semantic Semiring**: `/Users/perigrin/dev/chalk/lib/Chalk/Semiring/Semantic.pm`
- **Grammar**: `/Users/perigrin/dev/chalk/grammar/chalk.bnf`
- **Parser**: `/Users/perigrin/dev/chalk/lib/Chalk/Parser.pm`

## References

- **Original Design Doc**: https://gist.githubusercontent.com/perigrin/aec7e5284b3134567a0160691a6a33c1/raw/9378e897d8c7f60b61da51185bdd7586a4ac2cd7/Precedence-semiring.md
- **Earley Parser Theory**: Aycock & Horspool, "Practical Earley Parsing" (1999)
- **Semiring Parsing**: Goodman, "Semiring Parsing" (1999)
- **Perl Precedence Rules**: perlop(1) - Perl operators and precedence

## Future Enhancements

### Potential Improvements

1. **Post-Processing Pruning**: Implement `prune_invalid_alternatives_from_forest()` to remove invalid alternatives from SPPF after parsing (currently stubbed in tests)

2. **Associativity Enforcement**: More sophisticated handling of left/right associativity to prune invalid chains earlier

3. **Performance Optimization**: Cache precedence comparisons for frequently-encountered operator pairs

4. **Better Error Messages**: When validation fails, provide detailed explanation of why precedence is invalid (which operators conflicted, what the correct precedence should be)

5. **Ambiguity Detection**: Track and report when multiple valid precedence interpretations exist (grammar ambiguity beyond operator precedence)

### Known Limitations

1. **Grammar Coupling**: Relies on expression rule names (`Expression`, `BinaryExpression`, etc.) - grammar refactoring could break precedence tracking

2. **Token Pattern Dependency**: Uses pattern name `IDENTIFIER` to filter identifiers - lexer changes could affect operator detection

3. **Ternary Operator**: Complex multi-part operators like `? :` may require special handling beyond current model

4. **Prefix/Postfix Operators**: Current model focused on binary infix operators; unary operators handled via special cases

## Summary

The Precedence Semiring provides declarative, table-driven operator precedence validation that:

- **Separates concerns**: Precedence logic lives in data (table), not grammar
- **Validates bottom-up**: Uses active/passive model to validate parent-child relationships during parsing
- **Coordinates disambiguation**: Works with Composite semiring to ensure all semirings use the same valid derivation
- **Supports parentheses**: Clears operator context to allow forced grouping
- **Handles edge cases**: Filters identifiers, whitelists expression rules, validates associativity

The active/passive model is the key innovation, allowing precedence validation without SPPF dependency while correctly handling nested expressions and alternative parses.
