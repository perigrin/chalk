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

## Bare bool return true (1 < 2)

A bare numeric comparison used as the final expression returns a genuine Bool
(`is_bool`=1). `1 < 2` is true: `Bool:1` in the type-tagged oracle. The ir-block
returns the NumLt node directly with repr :Bool, and the emitter prints the
`Bool:` + string-face tag via a `select i1` between two string-constant globals.
Bilateral coverage for the false case is the next case (2 < 1 => `Bool:`).

```perl
# source
1 < 2
```

```behavior
return: Bool:1
context: scalar
```

```ir
%one  = Constant(1) :Int
%two  = Constant(2) :Int
%cmp  = NumLt(%one, %two) :Bool
return %cmp
L: GREEN
```

## Bare bool return false (2 < 1)

The bilateral counterpart to the true case above: `2 < 1` is false, so the result
is `Bool:` (empty string-face) in the type-tagged oracle. A lowering that modelled
Bool as an integer 0 would emit `Int:0`, which differs from `Bool:` — the
type-discriminating oracle catches this miscompile. This case is the adversarial
guard made concrete: the false Bool must be `Bool:`, not `Str:` or `Int:0`.

```perl
# source
2 < 1
```

```behavior
return: Bool:
context: scalar
```

```ir
%two  = Constant(2) :Int
%one  = Constant(1) :Int
%cmp  = NumLt(%two, %one) :Bool
return %cmp
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

## Print a string literal to stdout

A bare `print "hi\n"` writes its argument to stdout as an ordered statement
effect, then the block yields `1`. The Print node is control-pinned (a void
`print` is `OPf_WANT_VOID`) so it survives DCE and emits before the return-value
epilogue. The printed string is emitted as raw bytes (`printf("%.*s", len, ptr)`),
so the stdout is `hi\n`; the block value is the trailing `Int:1`.

```perl
# source
print "hi\n"; 1
```

```behavior
stdout: hi\n
return: Int:1
context: scalar
```

```ir
%s0   = Constant("hi\n") :Str
%p    = Print(%s0) :Bool
%c    = Constant(1) :Int
return %c
control: %p
L: GREEN
```

## Print a mixed argument list to stdout

`print LIST` emits every list element in order. A mixed Str/Int list
(`"ok ", 1, "\n"`) emits each argument by its representation — a Str via
`printf("%.*s")` and an Int via `printf("%d")` — producing the concatenated
`ok 1\n`. The block value is the trailing `Int:1`.

```perl
# source
print "ok ", 1, "\n"; 1
```

```behavior
stdout: ok 1\n
return: Int:1
context: scalar
```

```ir
%s0   = Constant("ok ") :Str
%i1   = Constant(1) :Int
%s2   = Constant("\n") :Str
%p    = Print(%s0, %i1, %s2) :Bool
%c    = Constant(1) :Int
return %c
control: %p
L: GREEN
```

## Two prints emit in order

Two sequential `print` statements are two distinct statement effects, threaded
on the control chain in program order. Both survive DCE (neither is the block
value) and emit before the return-value epilogue, so the stdout is `a\nb\n` in
order. The block value is the trailing `Int:1`.

```perl
# source
print "a\n"; print "b\n"; 1
```

```behavior
stdout: a\nb\n
return: Int:1
context: scalar
```

```ir
%s0   = Constant("a\n") :Str
%p0   = Print(%s0) :Bool
%s1   = Constant("b\n") :Str
%p1   = Print(%s1) :Bool
%c    = Constant(1) :Int
return %c
control: %p0 -> %p1
L: GREEN
```

## Print as a value (my $ok = print)

`print` returns a genuine boolean (`builtin::is_bool` true) — `1` on success.
Reading its return value (`my $ok = print "x\n"; $ok`) yields `Bool:1` in the
type-tagged oracle, NOT `Int:1`: the Print node's representation is Bool. The
stdout is `x\n`; the block value is the Print's boolean `1`.

```perl
# source
my $ok = print "x\n"; $ok
```

```behavior
stdout: x\n
return: Bool:1
context: scalar
```

```ir
%s0   = Constant("x\n") :Str
%p    = Print(%s0) :Bool
return %p
control: %p
L: GREEN
```

## Print to an explicit filehandle (STDOUT): GAP

`print STDOUT ...` (and `print $fh ...`) set `OPf_STACKED` and push a gv/rv2gv
handle operand before the args. The runtime-free backend writes only to stdout,
so honoring an explicit handle would be a miscompile — the producer GAPs (dies)
on the stacked form rather than silently misrouting. This is a loud GAP at the
producer, recorded here as a corpus-declared GAP.

```perl
# source
print STDOUT "x\n"; 1
```

```behavior
stdout: x\n
return: Int:1
context: scalar
```

```ir
L: GAP(explicit filehandle: print STDOUT ... / print $fh ... sets OPf_STACKED; the runtime-free backend writes only to stdout, so an explicit handle is a loud producer GAP, never a silent misroute)
```
