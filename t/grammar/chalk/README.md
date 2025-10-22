# Chalk Grammar Test Suite

This directory contains comprehensive tests for the `grammar/chalk.bnf` grammar, which defines the restricted Perl subset that Chalk supports for compilation.

## Test Coverage

### 01-classes.t
**Coverage: Class declarations and OO features**
- Empty class declarations
- Field declarations with attributes (`:param`, `:reader`)
- Field initialization
- Method declarations
- ADJUST blocks
- Class inheritance (`:isa`)
- Multiple classes in one file
- Negative tests: nested classes, package declarations

### 02-variables.t
**Coverage: Variable declarations and usage**
- Lexical variables: `my`, `state`
- Field declarations in classes
- Scalar, array, and hash variables
- Variable initialization
- Array/hash element access
- Array/hash slices
- Array/hash dereferencing (braced and postfix)

### 03-expressions.t
**Coverage: Operators and expression parsing**
- Arithmetic operators: `+`, `-`, `*`, `/`, `%`, `**`
- Comparison operators: `==`, `!=`, `<`, `>`, `<=`, `>=`, `<=>`
- String comparison: `eq`, `ne`, `lt`, `gt`, `le`, `ge`, `cmp`
- Logical operators: `&&`, `||`, `!`, `and`, `or`, `not`
- Defined-or operator: `//`
- String concatenation: `.`
- Ternary operator: `? :`
- Assignment operators: `=`, `+=`, `-=`, `*=`, `/=`, `//=`, `.=`
- Increment/decrement: `++`, `--`
- Method calls and chaining
- Function calls
- Array/hash access
- Range operator: `..`
- Regex match: `=~`, `!~`

### 04-control-flow.t
**Coverage: Control flow statements**
- `if`/`elsif`/`else` conditionals
- `unless` conditionals
- Statement modifiers (`if`, `unless`)
- `while` loops
- `for` loops (list iteration)
- `return` statements (with and without values)
- Loop control: `last`, `next`
- Nested control structures

### 05-use-statements.t
**Coverage: Pragmas and module loading**
- `use VERSION` (e.g., `use 5.42.0`)
- `use Module`
- `use Module qw(...)`
- `use Module 'string'`
- `use Module EXPR_LIST` (e.g., `use overload`)
- Multiple use statements

### 06-literals.t
**Coverage: Literal values**
- Integer literals (positive, negative, with underscores)
- Float literals (with scientific notation)
- Single-quoted strings (with escapes)
- Double-quoted strings (with escapes)
- Array literals (nested)
- Hash literals (nested)
- Mixed nested structures
- Regex literals: `qr/.../`
- Special values: `undef`
- Quote operators: `q()`, `qq()`, `qw()`

### 07-subroutines.t
**Coverage: Subroutine declarations and calls**
- Simple subroutine declarations
- Subroutines with parameters and signatures
- Default parameters
- Lexical subroutines: `my sub`
- Subroutine calls
- Method declarations in classes
- Method calls
- Anonymous subroutines
- Subroutines with attributes (`:prototype()`)

### 08-standard-perl-compliance.t
**Coverage: Standard Perl alignment**
- Quoted hash keys (required)
- Function calls with parentheses
- Dereferencing with braces and postfix
- Hash/block disambiguation
- Arrow invocants for method calls
- Quote operators with allowed delimiters
- Negative tests: indirect object notation

## Design Principles

These tests verify that chalk.bnf correctly implements:

1. **Classes-only policy**: No `package` keyword support
2. **Static parseability**: All constructs must be parseable without runtime info
3. **Standard Perl alignment**: Adopts beneficial restrictions from Standard Perl spec
4. **Compilation readiness**: Grammar suitable for IR generation and compilation

## Running the Tests

Run all chalk grammar tests:
```bash
PLENV_VERSION=5.42.0 plenv exec prove t/grammar/chalk/
```

Run a specific test:
```bash
PLENV_VERSION=5.42.0 plenv exec perl t/grammar/chalk/01-classes.t
```

Run with verbose output:
```bash
PLENV_VERSION=5.42.0 plenv exec prove -v t/grammar/chalk/
```

## Test Success Criteria

- All tests must pass at 100%
- Tests verify positive cases (code that should parse)
- Tests verify negative cases (code that should NOT parse)
- Tests cover all major grammar rules in chalk.bnf
- Tests demonstrate self-hosting capability (parsing Chalk's own code)

## Coverage Goals

- **Target**: >90% coverage of chalk.bnf rules
- **Current**: 8 test files covering all major categories
- **Categories covered**: Classes, variables, expressions, control flow, use statements, literals, subroutines, Standard Perl compliance

## Related Files

- `grammar/chalk.bnf` - The grammar being tested
- `t/self-hosting.t` - Integration test for parsing all Chalk library files
- `t/bnf-parser-equivalence.t` - BNF parser correctness tests
- `lib/Chalk/Grammar.pm` - Grammar implementation
- `lib/Chalk/Parser.pm` - Parser implementation
