# Interpolated Strings Design (#201)

## Summary

Implement proper handling of double-quoted strings with variable interpolation and escape sequences. Single-quoted strings get minimal escape processing.

## Scope (Stage 0)

Based on analysis of `lib/` usage:

**Interpolation:** Simple scalars only (`$var`)
- No `@array` interpolation
- No `$hash{key}` or `${expr}`

**Escape sequences:**
| Escape | Output | Usage in lib/ |
|--------|--------|---------------|
| `\n` | newline | 119 |
| `\@` | literal @ | 110 |
| `\\` | literal \ | 29 |
| `\$` | literal $ | 26 |
| `\t` | tab | 2 |
| `\"` | literal " | 2 |
| `\r` | CR | 1 |

## Architecture

All parsing logic lives in the semantic actions. No grammar changes needed.

### DoubleQuotedString.pm

1. Strip surrounding quotes
2. Scan for unescaped `$identifier` patterns
3. Build parts array:
   - `Constant` nodes for literal text (with escapes processed)
   - `VarGet` nodes for variable references
4. Return:
   - `Constant` if no interpolation
   - `InterpolatedString` if has interpolation

**Escape processing:**
```perl
my %esc = (n => "\n", t => "\t", r => "\r");
$text =~ s/\\([ntr\\"$\@])/$esc{$1} \/\/ $1/ge;
```

### SingleQuotedString.pm

Only process `\\` and `\'`:
```perl
$text =~ s/\\([\\'])/$1/g;
```

Return `Constant` node.

### String.pm

Simplify to pass-through. The child rules handle all processing.
Only needs special handling for `%VERSION%` token.

## Existing Infrastructure

- **IR Node:** `Chalk::IR::Node::InterpolatedString` exists with `parts` array
- **XS Visitor:** `visit_InterpolatedString` generates concatenation code
- **Grammar:** Already distinguishes `SingleQuotedString` and `DoubleQuotedString`

## Implementation Tasks

1. Update `SingleQuotedString.pm` - escape processing, return Constant
2. Update `DoubleQuotedString.pm` - interpolation parsing, escape processing
3. Simplify `String.pm` - delegate to child rules
4. Add tests for escape sequences
5. Add tests for variable interpolation
6. Add E2E test that compiles and runs

## Stage 0 Acceptance Criteria

- [ ] Grammar parses the syntax (already done)
- [ ] Semantic action generates IR nodes
- [ ] XS visitor generates valid XS code (already done)
- [ ] E2E test compiles and runs successfully
