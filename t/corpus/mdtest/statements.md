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

This case lowers the comparison through a ternary into an Int — the GREEN D6
`select i1` pattern: the NumLt is the i1 condition, the returned value is a plain
Int. It is the simplest faithful runtime-free comparison idiom and lowers today.

CORRECTED FINDING (2026-06-07): Bool is its OWN representation, not "the empty
string." Perl 5.36+ has primitive `true`/`false` distinguishable by
`builtin::is_bool()`: `(2 < 1)` is a genuine boolean (`is_bool`=1) that
*coerces* to `""` in string context and `0` in numeric context — but a literal
`""` is NOT a boolean (`is_bool("")`=0). So bool is an `i1`-representable
runtime-free value with explicit `Coerce(Bool->Num)` (-> 0/1) and
`Coerce(Bool->Str)` (-> ""/"1") edges, exactly like `Coerce(Int->Num)`.
Therefore bool-return is NOT blocked on Str/group-C: a bare `1 < 2` is closeable
by modelling the Bool representation + its coercion edges (a small runtime-free
capability). The earlier "needs Str" claim was wrong. We use the ternary form
here as the simplest GREEN case; a bare-bool-return case can be added once the
Bool representation + Coerce(Bool->*) edges are modelled (a separate, clean,
runtime-free gap — not a string dependency).

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
