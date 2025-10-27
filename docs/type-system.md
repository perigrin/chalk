# Chalk Type System Documentation

## Overview

Chalk implements a **latent type system** based on Perl's runtime type semantics. Types are implicit (no annotations required) but checkable during compilation. This document describes the complete type system as implemented in Issue #74.

**Key Principle:** Types are inferred from context (sigils, operations, literals) and checked during IR generation for early error detection.

## Type Lattice

The Chalk type system forms a lattice with Any (⊤) at the top and None (⊥) at the bottom:

```
                        Any (⊤)
                          |
        +-----------------+------------------+
        |                 |                  |
     Scalar             List              Code
        |                 |
        |                 +------+------+
        |                        |      |
        |                     Array   Hash
        |
        +--------+--------+--------+
        |        |        |        |
      Undef   Boolean    Str      Ref
                          |        |
                         Num       +----+----+----+
                          |        |    |    |    |
                         Int    Object ScalarRef ArrayRef
                                      HashRef CodeRef

                        None (⊥)
```

### Subtyping Chains

**Primary Scalar Chain:**
```
Int <: Num <: Str <: Scalar <: Any
```

Why `Num <: Str`? Because numbers can round-trip through string conversion without information loss:
- `42 → "42" → 42` preserves value
- But `"hello" → 0 → "0"` loses information (not all Str are Num)

**Other Important Chains:**
```
Undef <: Scalar <: Any
Boolean <: Scalar <: Any

Object <: Ref <: Scalar <: Any
ScalarRef <: Ref <: Scalar <: Any
ArrayRef <: Ref <: Scalar <: Any
HashRef <: Ref <: Scalar <: Any
CodeRef <: Ref <: Scalar <: Any

Array <: List <: Any
Hash <: List <: Any

Code <: Any

None <: (everything)
```

## Type Classes

### Universal Types

**Chalk::Type::Any** - The top type, supertype of all types

**Chalk::Type::None** - The bottom type, subtype of all types (represents "no value")

### Scalar Types

**Chalk::Type::Scalar** - Base type for all scalar values

**Chalk::Type::Undef** - The undefined value type
- Coerces to `0` in numeric context
- Coerces to `""` in string context
- Coerces to `false` in boolean context

**Chalk::Type::Boolean** - Truthy/falsy values
- All Perl values have boolean interpretation
- `0`, `''`, `"0"`, and `undef` are falsy
- Everything else is truthy

**Chalk::Type::Str** - String values
- All defined values can be stringified
- Supertype of Num (numbers stringify without loss)

**Chalk::Type::Num** - Numeric values
- Integer and floating-point numbers
- Valid numeric strings (e.g., "42", "3.14")
- Subtype of Str (round-trip preserving)

**Chalk::Type::Int** - Integer values
- Whole numbers only
- Subtype of Num

### Reference Types

**Chalk::Type::Ref** - Base reference type

**Chalk::Type::Object** - Blessed references

**Chalk::Type::ScalarRef** - Reference to scalar (`\$x`)

**Chalk::Type::ArrayRef** - Reference to array (`\@arr`)

**Chalk::Type::HashRef** - Reference to hash (`\%hash`)

**Chalk::Type::CodeRef** - Reference to subroutine (`\&sub`)

### Container Types

**Chalk::Type::List** - Ephemeral list values
- Exists only during list-context evaluation
- Converts to Array or Hash on assignment
- Produced by ranges (`1..10`), list literals, function returns

**Chalk::Type::Array** - Persistent array containers
- Subtype of List
- Parameterized: `Array[ElementType]`
- Default element type: `Any`

**Chalk::Type::Hash** - Persistent hash containers
- Subtype of List
- Parameterized: `Hash[ValueType]`
- Default value type: `Any`

### Code Type

**Chalk::Type::Code** - Subroutines and methods
- Top-level type (not a Scalar)

## Type Membership

A value `v` belongs to type `T` if and only if **both** conditions hold:

1. **Syntactic Preservation**: Converting `v` to type `T` and back produces observationally equivalent results without information loss (round-trip coercion test)

2. **Semantic Fulfillment**: `v` satisfies all operational contracts defined for type `T`

### Example: NaN Edge Case

The string `"NaN"`:
- ✅ Passes syntactic preservation (round-trips through numeric interpretation)
- ❌ Fails semantic fulfillment (IEEE NaN violates reflexivity: `NaN ≠ NaN`)
- **Result:** `"NaN" ∉ Num`

## Type Coercion

Chalk implements three coercion operations matching Perl's runtime semantics:

### Numeric Coercion (to_num)

```perl
# Numbers stay unchanged
42 → 42
3.14 → 3.14

# Valid numeric strings parse
"42" → 42
"3.14" → 3.14

# Invalid strings become 0 (with warning)
"hello" → 0  # Warning: information loss

# Undef becomes 0
undef → 0

# References coerce to memory addresses
\$x → 0x7f8a...
```

### String Coercion (to_str)

```perl
# Strings stay unchanged
"hello" → "hello"

# Numbers stringify
42 → "42"
3.14 → "3.14"

# References show type and address
\$x → "SCALAR(0x...)"
\@arr → "ARRAY(0x...)"

# Undef becomes empty string
undef → ""
```

### Boolean Coercion (to_bool)

```perl
# Falsy values
0 → false
"" → false
"0" → false
undef → false

# Truthy values (everything else)
1 → true
"hello" → true
\@arr → true
```

## Type Inference

Types are automatically inferred during parsing from:

### Literals

```perl
42          # Int
3.14        # Num
"hello"     # Str
undef       # Undef
```

### Variables (from sigils)

```perl
$x          # Scalar
@arr        # Array[Any]
%hash       # Hash[Any]
```

### Operations

```perl
$x + $y     # Num (arithmetic)
$a . $b     # Str (concatenation)
1..10       # List (range)
```

### Ephemeral List Conversion

```perl
my @arr = (1..10);        # Range → List → Array
my %hash = (a => 1);      # List → Hash
my ($x, $y) = func();     # func returns List
```

## Built-in Function Signatures

Chalk provides type signatures for common Perl built-ins:

```perl
length(Str) → Int
push(Array, Any) → Int
defined(Any) → Boolean
keys(Hash) → List
join(Str, List) → Str
```

See `lib/Chalk/Builtins.pm` for the complete list.

## Error Messages

The type system provides detailed error messages:

### Type Coercion Errors

```
Cannot coerce value from Str to Num
  Source type: Str
  Target type: Num
  Value: 'hello'
  Context: numeric coercion
```

### Type Mismatch Errors

```
Type mismatch: expected Int, got Str
  Source type: Str
  Target type: Int
  Context: assignment
```

### Information Loss Warnings

```
Warning: information loss in coercion from Str to Num
(value: 'hello') in context: non-numeric string coerced to 0
```

### Invalid List Assignment

```
Cannot assign List to variable with sigil '$'.
List can only be assigned to arrays (@) or hashes (%)
  Context: list assignment
```

## Implementation Architecture

The type system integrates with Chalk's compilation pipeline:

```
Parse → SPPF → Semantic Actions (with type inference) → Typed IR → Codegen
```

### Components

1. **Type Classes** (`lib/Chalk/Type/*.pm`)
   - 19 type classes implementing the lattice
   - Subtyping relationships via `is_subtype_of()`
   - Type membership via `check_membership()`

2. **Type Coercion** (`lib/Chalk/Type/Coercion.pm`)
   - Implements `to_num()`, `to_str()`, `to_bool()`
   - Generates warnings for information-losing coercions

3. **Type Exceptions** (`lib/Chalk/Type/Exception.pm`)
   - Structured error messages
   - Context tracking for debugging

4. **Semantic Semiring** (`lib/Chalk/Semiring/Semantic.pm`)
   - Type environment tracking (`$type_env`)
   - Type inference from grammar rules (`infer_type_from_rule()`)
   - Type propagation through comonad operations

5. **Built-in Signatures** (`lib/Chalk/Builtins.pm`)
   - Function parameter and return types
   - Used for type checking function calls

## Testing

The type system has comprehensive test coverage:

- `t/types/lattice.t` - Type hierarchy and subtyping
- `t/types/membership.t` - Type membership criteria
- `t/types/coercion.t` - Coercion rules
- `t/types/ephemeral.t` - Ephemeral List type
- `t/types/list-conversion.t` - List → Array/Hash conversion
- `t/types/subroutine-types.t` - Function parameter/return types
- `t/types/semantic-type-tracking.t` - Type inference during parsing
- `t/types/builtins.t` - Built-in function signatures
- `t/types/programs.t` - End-to-end integration tests

**Total:** 65+ tests covering all aspects of the type system

## Future Enhancements

Potential extensions (not yet implemented):

- Optional explicit type annotations
- Generic/parameterized types beyond Array/Hash
- Union types for precision
- Refinement types with constraints
- Type-directed optimization passes

## References

- **Formal specification:** https://gist.github.com/perigrin/c4780a7511ba1421e49a4a8b385aaa3d
- **Implementation issue:** #74
- **Perl type documentation:** perldata, perlop, perlfunc

## See Also

- Sea of Nodes IR (`docs/sea-of-nodes-chapter07-loops.md`)
- Grammar specification (`grammar/chalk.bnf`)
- Parser documentation (`lib/Chalk/Parser.pm`)
