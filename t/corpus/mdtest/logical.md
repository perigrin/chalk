# Logical Operators

Perl's logical operators `&&`, `||`, `//`, and `!` all have semantics that
prevent runtime-free lowering in the current literal-arithmetic lowering slice.

`&&` and `||` are SHORT-CIRCUIT OPERAND-RETURNING operators: they return one
of their operands (not a boolean), so `$a && $b` returns `$a` when `$a` is
falsy or `$b` when `$a` is truthy.  Implementing this correctly requires an
If node selecting which operand to pass through, plus a Phi to merge the two
paths — neither is in the current straight-line lowering slice.

`//` (defined-or) checks SvOK (whether the SV is defined), not truthiness.
This is an intrinsic Scalar operation that requires runtime SV inspection.

`!` (logical not) returns either `""` (empty string) or `"1"` — NOT 0 and 1.
Specifically, `!5` is `""` and `!0` is `"1"`.  This dual-representation
result (`""` vs `"1"`) requires Str-typed output with a string-constant
branch, not a runtime-free integer negation.

All four idioms are honest GAPs.  The behavior is still perl-specified and
the GAP reason is documented for each case.

## L1 logical and

Perl `&&` returns an operand: the left operand when it is falsy, the right
operand when the left is truthy.  For `$a = 3`, `$b = 7`, the result is `7`
(not `1`).  This operand-passing semantics requires If+Phi short-circuit
structure that is not in the current lowering slice.

```perl
# source
my $a = 3;
my $b = 7;
$a && $b
```

```behavior
return: 7
context: scalar
```

```ir
L: GAP(cfg-blocks-phi: && is short-circuit control flow (returns an operand, skips RHS when LHS false); needs LLVM basic blocks + br + phi. THE SAME GAP as if/while/for -- && is an if-expression in disguise.)
```

## L2 logical or

Perl `||` also returns an operand: the left operand when it is truthy, the
right operand when the left is falsy.  For `$a = 3`, `$b = 7`, the result is
`3` (not `1`).  Same short-circuit If+Phi structure required.

```perl
# source
my $a = 3;
my $b = 7;
$a || $b
```

```behavior
return: 3
context: scalar
```

```ir
L: GAP(cfg-blocks-phi: || is short-circuit control flow (returns an operand, skips RHS when LHS true); needs LLVM basic blocks + br + phi. THE SAME GAP as if/while/for.)
```

## L3 defined-or

Perl `//` returns the left operand when it is defined (SvOK), otherwise the
right operand.  Definedness is checked via SvOK — a different test from
truthiness (`||`).  For `$a = 3`, `$b = 7`, the result is `3`.  This
requires runtime SV inspection and is inherently a Scalar operation.

```perl
# source
my $a = 3;
my $b = 7;
$a // $b
```

```behavior
return: 3
context: scalar
```

```ir
L: GAP(// needs SvOK defined-check; inherently a Scalar runtime operation)
```

## L4 not

Perl `!` returns a genuine BOOLEAN: `!5` is `false`, `!0` is `true`. These are
primitive booleans (`is_bool(!5)`=1, `is_bool(!0)`=1 — verified), NOT strings.
A boolean *coerces* to `""`/`"1"` in string context and `0`/`1` in numeric
context, but its identity is Bool, not Str (a literal `""` has `is_bool`=0).

CORRECTED CLASSIFICATION (2026-06-07): `!` is a Bool-REPRESENTATION gap, not a
"Str dual-representation" gap (the earlier prose was wrong — `!5` is not an empty
string, it is `false`). It is closeable runtime-free by modelling the Bool
representation (i1) + a UnaryNot(Bool)->Bool op + the `Coerce(Bool->*)` edges —
NOT blocked on Str/group-C. (Contrast L1/L2 `&&`/`||`, which genuinely return an
OPERAND and need control flow / cfg-blocks-phi; and L3 `//`, which needs SvOK.)
Output of a bare bool still needs the context-correct `Coerce(Bool->Str|Num)`.

```perl
# source
my $a = 5;
!$a
```

```behavior
return: 
context: scalar
```

```ir
L: GAP(bool-repr: ! yields a genuine Bool (is_bool), not a Str; closeable runtime-free via a Bool representation + UnaryNot + Coerce(Bool->*) edges. NOT a Str/group-C dependency.)
```
