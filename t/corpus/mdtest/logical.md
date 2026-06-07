# Logical Operators

Perl's logical operators `&&`, `||`, `//`, and `!` are all runtime-free (RF)
per docs/architecture/runtime-free-boundary.md — they are GAPs only because the
current literal-arithmetic lowering slice lacks the control flow / representations
they need, NOT because they require libperl. Each closes RF once its prerequisite
lands (cfg-blocks-phi for the operand-returning operators, a Bool/Undef
representation for `!` and `//`).

`&&` and `||` are SHORT-CIRCUIT OPERAND-RETURNING operators: they return one
of their operands (not a boolean), so `$a && $b` returns `$a` when `$a` is
falsy or `$b` when `$a` is truthy.  Implementing this correctly requires an
If node selecting which operand to pass through, plus a Phi to merge the two
paths — neither is in the current straight-line lowering slice.

`//` (defined-or) checks definedness (is the value Undef?), not truthiness.
Per the runtime-free boundary (docs/architecture/runtime-free-boundary.md) this
is RF: an Undef-definedness check is a known operation on a known representation
(Undef has a machine representation; the check is a tag/niche test), NOT a
libperl dependency. It is a GAP only because the Undef representation and its
definedness predicate are not yet modelled, not because it needs the interpreter.

`!` (logical not) returns a genuine primitive BOOLEAN: `!5` is `false`, `!0` is
`true` (`is_bool` verified). A boolean *coerces* to `""`/`"1"` in string context
and `0`/`1` in numeric context, but its identity is Bool, not Str. `!` is RF: a
Bool representation (i1) + UnaryNot(Bool)->Bool + `Coerce(Bool->*)` edges — a GAP
only until the Bool representation is modelled, not a Str/libperl dependency.

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
%ca = Constant(3) :Int
%cb = Constant(7) :Int
%r  = And(%ca, %cb) :Int
return %r
L: GREEN
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
%ca = Constant(3) :Int
%cb = Constant(7) :Int
%r  = Or(%ca, %cb) :Int
return %r
L: GREEN
```

## L3 defined-or

Perl `//` returns the left operand when it is defined, otherwise the right
operand.  Definedness (is the value Undef?) is a different test from truthiness
(`||`).  For `$a = 3`, `$b = 7`, the result is `3`.  Per the runtime-free
boundary this is RF: a definedness check is a known predicate on the Undef
representation, paired with the same operand-selecting control flow as `||`
(cfg-blocks-phi).  It is a GAP only until the Undef representation + its
definedness predicate are modelled — not a libperl dependency.

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
L: GAP(// is RF: an Undef-definedness check + operand-selecting control flow (cfg-blocks-phi); GAP only until the Undef representation + definedness predicate are modelled, NOT a libperl dependency)
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
OPERAND and need control flow / cfg-blocks-phi; and L3 `//`, an RF
Undef-definedness check + the same operand-selecting control flow.)
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
