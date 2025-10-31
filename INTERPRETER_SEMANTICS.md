# Chalk Interpreter Semantic Decisions

This document tracks deliberate semantic differences between Chalk interpreter and Perl 5.42.0, along with rationale.

## Comparison Operators: Boolean Type

**Decision**: Chalk comparison operators currently return `0` for false, while Perl 5.42.0 returns proper boolean objects.

**Status**: ❌ **Should be fixed** - Perl 5.42.0 has proper boolean type support

### Perl 5.42.0 Behavior

```perl
use v5.42;
use builtin qw(is_bool);

my $result = 5 > 10;
is_bool($result);  # Returns true - it's a boolean object!
print $result;     # Stringifies to '' (empty string)
0 + $result;       # Numerifies to 0
```

**Key insight**: In Perl 5.42.0, comparison operators return **actual boolean objects** that:
- Are detected by `builtin::is_bool()`
- Stringify to `''` for false, `'1'` for true
- Numerify to `0` for false, `1` for true
- Are false/true in boolean context

This is different from older Perl where comparisons returned plain `''` or `1`.

### Chalk Behavior (Current)

```perl
return 5 > 10;  # Returns 0 (plain number)
```

- False value is the number 0 (not a boolean object)
- Would not pass `is_bool()` test
- Is false in boolean context (matches Perl)
- Numeric operations work correctly

### Why This Matters

1. **Type correctness**: Chalk targets Perl 5.42.0 semantics, which includes the new boolean type

2. **Future compatibility**: Code that uses `builtin::is_bool()` would behave differently:
   ```perl
   my $x = 5 > 10;
   if (is_bool($x)) { ... }  # Perl: true, Chalk: false
   ```

3. **String operations**: When concatenating, booleans behave specially:
   ```perl
   "Result: " . (5 > 10)  # Perl: "Result: ", Chalk: "Result: 0"
   ```

### Implementation Requirements

To properly support Perl 5.42.0 booleans, Chalk needs:

1. **Boolean IR node type**: Either a new `Chalk::IR::Node::Boolean` or extend `Constant` with a boolean variant

2. **Dual stringification**: Booleans must stringify to:
   - Empty string `''` for false
   - String `'1'` for true

3. **Numeric conversion**: Booleans must numerify to:
   - Number `0` for false
   - Number `1` for true

4. **Type checking**: Support for `builtin::is_bool()` introspection

5. **Comparison node updates**: All comparison operators (GT, LT, EQ, NE, GE, LE) must return boolean nodes instead of numeric constants

### Workaround (Current)

For now, Chalk's numeric `0`/`1` values:
- ✅ Work correctly in boolean context (if, while, etc.)
- ✅ Work correctly in numeric operations
- ❌ Don't pass `is_bool()` checks
- ❌ Stringify differently (`"0"` vs `""`)

### Priority

**Medium-High**: This should be addressed relatively soon because:
- It's a core semantic difference from Perl 5.42.0
- The boolean type is a significant new feature in modern Perl
- It affects type introspection and string operations

### Related Work

- Issue #128: Interpreter test coverage expansion
- `t/sea-of-nodes/interpreter-differential.t`: Documents this in TODO section
- Future: Will need revisiting when implementing string operations

## Variable Reassignment

**Status**: ❌ Bug - needs fixing

**Issue**: Variable reassignment does not update the variable value.

```perl
my $x = 5;
$x = 10;        # Should update $x
return $x;      # Returns 5 instead of 10
```

This is a genuine bug in the IR construction or interpreter, not an acceptable semantic difference.

**Root cause**: Likely related to how Store nodes are being created or how Load nodes resolve to the correct memory state.

## Negative Literals

**Status**: ❌ Bug - parser ambiguity issue

**Issue**: Negative number literals cause parser to create multiple Return nodes, resulting in malformed IR graphs.

```perl
return -5;      # Parser creates 4 different Return nodes
```

**Workaround**: Negative results work fine when produced by arithmetic:
```perl
return 3 - 10;  # Works correctly, returns -7
```

**Root cause**: Grammar ambiguity in how unary minus is parsed. The parser is creating multiple interpretations of the same input.

**Impact**: Blocks use of:
- Negative literal constants
- Unary negation operator on literals
- Negative numbers in arithmetic with literals

## Control Flow with Multiple Returns

**Status**: ❌ Bug - IR construction issue

**Issue**: if/else statements with return in both branches create malformed IR graphs.

```perl
if ($x > 0) { return 42; } else { return -42; }
# Error: Multiple Return nodes without proper control flow links
```

**Root cause**: IR builder doesn't properly handle multiple return paths. Each return creates a Return node, but they aren't properly linked to control flow using the __CONTROL_PLACEHOLDER__ mechanism.

**Workaround**: Use conditional assignment instead:
```perl
my $result;
if ($x > 0) { $result = 42; } else { $result = -42; }
return $result;
```

Note: Even the workaround has issues - assignment in if-branch doesn't work correctly.

## Summary Table

| Issue | Status | Impact | Priority |
|-------|--------|---------|----------|
| Boolean type support | ❌ Missing feature | Medium - affects type introspection & strings | Medium-High |
| Variable reassignment | ❌ Bug | High - blocks basic patterns | High |
| Negative literals | ❌ Parser bug | Medium - workaround exists (use arithmetic) | Medium |
| Control flow returns | ❌ IR bug | High - blocks common patterns | High |

## Verification

To verify these behaviors:

```bash
# Run differential tests
PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/sea-of-nodes/interpreter-differential.t

# Check specific behaviors
perl -e 'sub test { return 5 > 10; } print "[" . test() . "]\n";'  # Perl: []
# Chalk returns: 0
```
