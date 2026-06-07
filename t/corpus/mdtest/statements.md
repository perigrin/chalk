# Statements

Statement-level idioms: return values from expressions, multi-statement
sequences, numeric comparison results, and pragma declarations.

Return and multi-statement idioms are runtime-free (GREEN) — they lower via
the same typed-arithmetic slice as arithmetic.md and variables.md. Comparison
results (Bool/i1) cannot be returned directly in the current LLVM backend, so
the raw-comparison case is a GAP. Pragmas (use strict, use Module qw(...))
are compile-time declarations with no runtime-free IR representation.

## Return integer literal

A bare integer expression used as the final value of a block evaluates to
that integer. The IR is a single Constant node fed into Return — the simplest
runtime-free case.

```perl
# source
5
```

```behavior
return: 5
context: scalar
```

```ir
%c = Constant(5) :Int
return %c
L: GREEN
```

## Multiple statements with two variables

Two sequential variable declarations followed by their sum. Each VarDecl is a
control node (sequencing the declarations); PadAccess threads each variable's
SSA value into the Add. This is the straight-line two-variable case, mirroring
the A1 pattern from the spec.

```perl
# source
my $x = 1; my $y = 2; $x + $y
```

```behavior
return: 3
context: scalar
```

```ir
%c1   = Constant(1) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %c1) :Int
%c2   = Constant(2) :Int
%yn   = Constant("$y") :Str
%vy   = VarDecl(%yn, %c2) :Int
%rx   = PadAccess(%vx, "$x") :Int
%ry   = PadAccess(%vy, "$y") :Int
%sum  = Add(%rx, %ry) :Int
return %sum
control: %vx -> %vy
L: GREEN
```

## Comparison as a condition (1 < 2 ? 1 : 0)

Bool is a CONDITION type, not a returned-value type. A *bare* `1 < 2` is not a
faithful runtime-free idiom: Perl's true is `1` but its FALSE is `""` (the empty
string, not `0`), so returning a raw i1 as an integer would MISCOMPILE the false
case (`0` ≠ `""`). A perl-faithful bool-as-a-VALUE therefore needs Str
representation (gap group C) — bool-return is blocked on strings, not a freebie.

The faithful runtime-free idiom feeds the comparison (Bool/i1) into a ternary,
which yields an Int — exactly the GREEN D6 `select i1` pattern. So we express
the real idiom `1 < 2 ? 1 : 0`: the NumLt is an internal condition, never a
returned value, and the returned value is a plain Int. Finding (2026-06-07):
the "H Bool-return freebie" is not independent — bool-as-value requires Str
(group C); bool-as-condition is already lowerable.

```perl
# source
1 < 2 ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%one  = Constant(1) :Int
%two  = Constant(2) :Int
%cmp  = NumLt(%one, %two) :Bool
%t    = Constant(1) :Int
%f    = Constant(0) :Int
%tern = TernaryExpr(%cmp, %t, %f) :Int
return %tern
L: GREEN
```

## Pragma declaration (use strict): compile-time GAP

A `use strict` pragma is a compile-time directive. It has no runtime value
and no SoN IR representation — pragmas affect the compiler, not the runtime
graph. A snippet that begins with `use strict` followed by a value expression
behaves identically with or without the pragma (strict only changes parse-time
errors); the trailing value expression is what produces the result.

The IR cannot represent a compile-time pragma as a node, so this idiom is a
GAP at the IR layer. The behavior oracle records the runtime result of the
trailing expression (not the pragma itself).

```perl
# source
use strict;
my $x = 42;
$x
```

```behavior
return: 42
context: scalar
```

```ir
L: GAP(compile-time: use strict is a compile-time pragma; no SoN IR node for pragma declarations)
```

## Pragma with import list (use List::Util qw(...)): compile-time GAP

A `use Module qw(names)` import is compile-time symbol injection. Like
`use strict`, it has no runtime-free IR representation — the import modifies
the symbol table at compile time. The runtime result of the block is the
return value of the last expression, not the use statement itself.

```perl
# source
use List::Util qw(sum);
sum(1, 2, 3)
```

```behavior
return: 6
context: scalar
```

```ir
L: GAP(compile-time: use Module qw(...) is compile-time import; function calls (sum) require Scalar ABI, not in runtime-free slice)
```
