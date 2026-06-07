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
L: GAP(&& returns an operand not a bool; needs If+Phi short-circuit)
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
L: GAP(|| returns an operand not a bool; needs If+Phi short-circuit)
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

Perl `!` returns `""` (empty string) for truthy input and `"1"` for falsy
input.  This is NOT integer 0 and 1: `!5` is `""` (defined, length 0), and
`!0` is `"1"`.  The result is a Str-typed dual-representation value — not a
runtime-free boolean integer lowering.  Verified: `perl -e 'print !5, "|", !0'`
prints `|1` (empty string before the pipe, then 1).

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
L: GAP(! returns "" not 0 for truthy input; dual-representation Str result not runtime-free)
```
