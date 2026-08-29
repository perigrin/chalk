# Statements

Statement-level idioms: return values from expressions, multi-statement
sequences, numeric comparison results, and pragma declarations.

Return and multi-statement idioms are runtime-free (GREEN) — they lower via
the same typed-arithmetic slice as arithmetic.md and variables.md. Comparison
results (Boolean/i1) cannot be returned directly in the current LLVM backend, so
the raw-comparison case is a GAP. Pragmas (use strict, use Module qw(...))
are compile-time declarations with no runtime-free IR representation.

## Return integer literal

A bare integer expression used as the final value of a block evaluates to
that integer. The IR is a single Constant node fed into Return — the simplest
runtime-free case.

```perl
# source
use 5.42.0;
say(5);
```

```behavior
stdout: 5\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c = Constant(5) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%c : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Multiple statements with two variables

Two sequential variable declarations followed by their sum. Each VarDecl is a
control node (sequencing the declarations); PadAccess threads each variable's
SSA value into the Add. This is the straight-line two-variable case, mirroring
the A1 pattern from the spec.

```perl
# source
use 5.42.0;
my $x = 1; my $y = 2; say($x + $y);
```

```behavior
stdout: 3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %c1) :Int
%c2   = Constant(2) :Int
%yn   = Constant("$y") :Str
%vy   = VarDecl(%yn, %c2) :Int
%rx   = PadAccess(%vx, "$x") :Int
%ry   = PadAccess(%vy, "$y") :Int
%sum  = Add(%rx, %ry) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%sum : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Comparison as a condition (1 < 2 ? 1 : 0)

This case lowers the comparison through a ternary into an Int — the GREEN D6
`select i1` pattern: the NumLt is the i1 condition, the returned value is a plain
Int. It is the simplest faithful runtime-free comparison idiom and lowers today.

CORRECTED FINDING (2026-06-07): Boolean is its OWN representation, not "the empty
string." Perl 5.36+ has primitive `true`/`false` distinguishable by
`builtin::is_bool()`: `(2 < 1)` is a genuine boolean (`is_bool`=1) that
*coerces* to `""` in string context and `0` in numeric context — but a literal
`""` is NOT a boolean (`is_bool("")`=0). So bool is an `i1`-representable
runtime-free value with explicit `Coerce(Boolean->Num)` (-> 0/1) and
`Coerce(Boolean->Str)` (-> ""/"1") edges, exactly like `Coerce(Int->Num)`.
Therefore bool-return is NOT blocked on Str/group-C: a bare `1 < 2` is closeable
by modelling the Boolean representation + its coercion edges (a small runtime-free
capability). The earlier "needs Str" claim was wrong. We use the ternary form
here as the simplest GREEN case; a bare-bool-return case can be added once the
Boolean representation + Coerce(Boolean->*) edges are modelled (a separate, clean,
runtime-free gap — not a string dependency).

```perl
# source
use 5.42.0;
say(1 < 2 ? 1 : 0);
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%one  = Constant(1) :Int
%two  = Constant(2) :Int
%cmp  = NumLt(%one, %two) :Boolean
%t    = Constant(1) :Int
%f    = Constant(0) :Int
%tern = TernaryExpr(%cmp, %t, %f) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%tern : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Bare bool return true (1 < 2)

A bare numeric comparison used as the final expression returns a genuine Boolean
(`is_bool`=1). `1 < 2` is true: `Bool:1` in the type-tagged oracle. The ir-block
returns the NumLt node directly with repr :Boolean, and the emitter prints the
`Bool:` + string-face tag via a `select i1` between two string-constant globals.
Bilateral coverage for the false case is the next case (2 < 1 => `Bool:`).

```perl
# source
use 5.42.0;
say(1 < 2);
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%one  = Constant(1) :Int
%two  = Constant(2) :Int
%cmp  = NumLt(%one, %two) :Boolean
%nl = Constant("\n") :Str
%co_p  = Coerce(%cmp : Boolean -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Bare bool return false (2 < 1)

The bilateral counterpart to the true case above: `2 < 1` is false, so the result
is `Bool:` (empty string-face) in the type-tagged oracle. A lowering that modelled
Boolean as an integer 0 would emit `Int:0`, which differs from `Bool:` — the
type-discriminating oracle catches this miscompile. This case is the adversarial
guard made concrete: the false Boolean must be `Bool:`, not `Str:` or `Int:0`.

```perl
# source
use 5.42.0;
say(2 < 1);
```

```behavior
stdout: \n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%two  = Constant(2) :Int
%one  = Constant(1) :Int
%cmp  = NumLt(%two, %one) :Boolean
%nl = Constant("\n") :Str
%co_p  = Coerce(%cmp : Boolean -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
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
use 5.42.0;
print "hi\n"; say(1);
```

```behavior
stdout: hi\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0   = Constant("hi\n") :Str
%p    = Print(%s0) :Boolean
%c    = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%c : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Print a mixed argument list to stdout

`print LIST` emits every list element in order. A mixed Str/Int list
(`"ok ", 1, "\n"`) emits each argument by its representation — a Str via
`printf("%.*s")` and an Int via `printf("%d")` — producing the concatenated
`ok 1\n`. The block value is the trailing `Int:1`.

```perl
# source
use 5.42.0;
print "ok ", 1, "\n"; say(1);
```

```behavior
stdout: ok 1\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0   = Constant("ok ") :Str
%i1   = Constant(1) :Int
%s2   = Constant("\n") :Str
%p    = Print(%s0, %i1, %s2) :Boolean
%c    = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%c : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Two prints emit in order

Two sequential `print` statements are two distinct statement effects, threaded
on the control chain in program order. Both survive DCE (neither is the block
value) and emit before the return-value epilogue, so the stdout is `a\nb\n` in
order. The block value is the trailing `Int:1`.

```perl
# source
use 5.42.0;
print "a\n"; print "b\n"; say(1);
```

```behavior
stdout: a\nb\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0   = Constant("a\n") :Str
%p0   = Print(%s0) :Boolean
%s1   = Constant("b\n") :Str
%p1   = Print(%s1) :Boolean
%c    = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%c : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Print as a value (my $ok = print)

`print` returns a genuine boolean (`builtin::is_bool` true) — `1` on success.
Reading its return value (`my $ok = print "x\n"; $ok`) yields `Bool:1` in the
type-tagged oracle, NOT `Int:1`: the Print node's representation is Boolean. The
stdout is `x\n`; the block value is the Print's boolean `1`.

```perl
# source
use 5.42.0;
my $ok = print "x\n"; say($ok);
```

```behavior
stdout: x\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0   = Constant("x\n") :Str
%p    = Print(%s0) :Boolean
%nl = Constant("\n") :Str
%co_p  = Coerce(%p : Boolean -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Print a value exceeding 32 bits to stdout

`print` renders an Int argument via `printf("%d")` on the machine i64. A
value that exceeds 32 bits (`4294967296`, i.e. `2**32`) must print its full
decimal form — perl does. This is a worklist case: the current LLVM backend's
int-print epilogue narrows through an i32 somewhere on the print path, so it
prints `0` (the low 32 bits of `4294967296` truncated) instead of the correct
`4294967296`. The block value (`Int:1`, the trailing bare `1`) is unaffected —
only the printed digits are wrong.

```perl
# source
use 5.42.0;
print 4294967296, "\n"; say(1);
```

```behavior
stdout: 4294967296\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0   = Constant(4294967296) :Int
%p    = Print(%s0) :Boolean
%c    = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%c : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
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

## say a string literal to stdout

`say` is `print` with a trailing newline. It is DESUGARED at the build site into
the same `Print` node with a `"\n"` operand appended, rather than given a node of
its own — so the control pin, the arm-effect predicates and the backend's
`_lower_print` all see one operator and need no `say` case. `say`'s OpMap entry
maps it to a generic `Call`, which the print branch pre-empts; before this it
reached the backend as an unlowered Call.

```perl
# source
use 5.42.0;
say "hi"; say(1);
```

```behavior
stdout: hi\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s   = Constant("hi") :Str
%nl  = Constant("\n") :Str
%p   = Print(%s, %nl)
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## say appends exactly ONE newline to a list

`say LIST` emits every argument and then a single newline — not one per
argument. This is the case that would catch the newline being appended per
operand rather than once to the list.

```perl
# source
use 5.42.0;
say "a", "b", "c"; say(1);
```

```behavior
stdout: abc\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%a   = Constant("a") :Str
%b   = Constant("b") :Str
%c   = Constant("c") :Str
%nl  = Constant("\n") :Str
%p   = Print(%a, %b, %c, %nl)
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## say inside an if/else arm is guarded by the branch

The desugaring must also reach the arm-effect predicate: a `say` in a branch arm
is a statement effect exactly as a `print` is, so each arm's Print is
control-pinned to its own Proj. Were `say` unrecognised there, both arms' output
would land on the shared control and BOTH would fire — the same silent
miscompile the `print` case exists to prevent. Bilateral with the case below.

```perl
# source
use 5.42.0;
my $c = 1;
if ($c) { say "a" } else { say "b" }
say(1);
```

```behavior
stdout: a\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c    = Constant(1) :Int
%if   = If(%c)
%a    = Constant("a") :Str
%nl   = Constant("\n") :Str
%pa   = Print(%a, %nl)
%b    = Constant("b") :Str
%pb   = Print(%b, %nl)
%one  = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## say inside an if/else arm, else polarity

The partner of the case above, with only the guard's value changed. Only the
else arm's output may appear; seeing both is the unguarded-effect miscompile.

```perl
# source
use 5.42.0;
my $c = 0;
if ($c) { say "a" } else { say "b" }
say(1);
```

```behavior
stdout: b\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c    = Constant(0) :Int
%if   = If(%c)
%a    = Constant("a") :Str
%nl   = Constant("\n") :Str
%pa   = Print(%a, %nl)
%b    = Constant("b") :Str
%pb   = Print(%b, %nl)
%one  = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## say to an explicit filehandle (STDOUT): GAP

`say STDOUT ...` sets `OPf_STACKED` exactly as `print STDOUT ...` does, and gets
the same loud producer GAP — the runtime-free backend writes only to stdout, so
honouring a handle would misroute rather than fail.

```perl
# source
use 5.42.0;
say STDOUT "x"; 1
```

```behavior
stdout: x\n
return: Int:1
context: scalar
```

```ir
L: GAP(explicit filehandle: say STDOUT ... sets OPf_STACKED, the same refusal print gets; the runtime-free backend writes only to stdout)
```

## Print coerces a non-Str argument (Print takes Str)

`Print`'s signature is `Print(Str...)`. A non-Str argument is coerced by an
explicit `Stringify` inserted at the producer's build site, exactly as `Divide`'s
Int operands are coerced to Num — rather than `Print` carrying a case per
representation.

That keeps the conversion in ONE place. `Print` previously lowered Str and Int
itself while `Stringify` separately knew how to render an Int, so teaching a new
type meant teaching both, and Boolean/Num/Slot were GAPped in `Print` even though
the coercion node was the natural home for them.

```perl
# source
use 5.42.0;
print "ok ", 1, "\n"; say(1);
```

```behavior
stdout: ok 1\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s1  = Constant("ok ") :Str
%n   = Constant(1) :Int
%sn  = Coerce(%n, from_repr: "Int", to_repr: "Str") :Str
%s2  = Constant("\n") :Str
%p   = Print(%s1, %sn, %s2)
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Print an ARRAY flattens it and coerces each element

`print @a` is where the two senses of "print takes Str" have to be told apart,
and the corpus had no case for it until now.

`Print`'s IR signature is `Print(Str...)` — one operator over one representation.
The Perl BUILTIN `print` takes a LIST and flattens it, which is why
`TypeLibrary.pm` types its argument `List`, in the same breath and for the same
reason as the `die`/`warn` entries three lines above it ("variadic: accept
scalars and arrays via flattening"). Those two statements are about DIFFERENT
LAYERS — `%_STR_CONTEXT_OPS` is keyed by IR op, `%BUILTIN_SIGNATURES` by source
builtin, and TypeLibrary never names an IR node — so they do not contradict each
other. Tightening the builtin's `arg_types` to `Str` on the strength of the IR
contract would REJECT this program at parse time: `TypeInference.pm:391` returns
undef on a signature mismatch, and `Array` is on the collection branch
(`Array -> List`), disjoint from `Str`.

Nothing pinned that. Every existing print case passes a scalar, so the whole
family stayed green while `print @a` broke — the reason this case exists.

The flattening happens at the producer's build site: the array is expanded to its
elements and each Int element gets its own `Coerce`, so `Print` receives three Str
operands and never sees an aggregate. The `ArrayRef` node is built but is NOT on
the control chain and is not an input to the `Print` — a real read would consume
it; here it is dead.

```perl
# source
use 5.42.0;
my @a = (1, 2, 3);
print @a;
print "\n";
```

```behavior
stdout: 123\n
return: Undef
context: scalar
```

```ir
%start = Start()
%nl  = Constant("\n") :Str
%n1  = Constant(1) :Int
%c1  = Coerce(%n1, from_repr: "Int", to_repr: "Str") :Str
%n2  = Constant(2) :Int
%c2  = Coerce(%n2, from_repr: "Int", to_repr: "Str") :Str
%n3  = Constant(3) :Int
%c3  = Coerce(%n3, from_repr: "Int", to_repr: "Str") :Str
%p1  = Print(%c1, %c2, %c3)
%p2  = Print(%nl)
return %p2
control: %start -> %p1 -> %p2
L: GREEN
```

## Stringify of a Boolean prints perl's spelling: "1" and EMPTY

A Boolean stringifies to `1` when true and to the EMPTY STRING when false — not
`0`. Both operands are module globals so their GEPs dominate every use, and the
LENGTH is selected alongside the pointer: a Str value is a (ptr, len) pair, so
selecting only the pointer would print one byte of the empty string. Bilateral
with the case below, which is what catches that.

```perl
# source
use 5.42.0;
say(1 == 1); say(1);
```

```behavior
stdout: 1\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%a   = Constant(1) :Int
%eq  = NumEq(%a, %a) :Boolean
%sb  = Coerce(%eq, from_repr: "Boolean", to_repr: "Str") :Str
%nl  = Constant("\n") :Str
%p   = Print(%sb, %nl)
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Stringify of a FALSE Boolean is the empty string (bilateral)

The partner of the case above. A false Boolean contributes NO bytes, so the only
output is the newline `say` appends. A pointer-only select would print `1`'s
first byte here.

```perl
# source
use 5.42.0;
say(1 == 2); say(1);
```

```behavior
stdout: \n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%a   = Constant(1) :Int
%b   = Constant(2) :Int
%eq  = NumEq(%a, %b) :Boolean
%sb  = Coerce(%eq, from_repr: "Boolean", to_repr: "Str") :Str
%nl  = Constant("\n") :Str
%p   = Print(%sb, %nl)
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Stringify of a Num renders perl's own float format

Perl's float stringification IS `%.15g` — shortest 15 significant digits with
trailing zeros stripped, exponent form outside a range. Verified against perl
5.42 on the corpus floats AND on `t/base/num.t`'s cases (`0.1`, `1e+34`,
`1.000001`, `10.01`, `123.456`, `0.0005`): `sprintf("%.15g")` reproduces perl
exactly in every one. So this is not an approximation of a bespoke dtoa — it is
the rule itself.

`snprintf` renders it: once with a null buffer to learn the length, then into a
buffer of exactly that size. The length is what the `(ptr, len)` Str pair needs,
and computing it any other way would re-implement `%g`. It is the same
host-interface class as the `printf` `Print` already emits — a plain C function,
not libperl.

```perl
# source
use 5.42.0;
say 0.75; say(1);
```

```behavior
stdout: 0.75\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%v   = Constant(0.75) :Num
%sv  = Coerce(%v, from_repr: "Num", to_repr: "Str") :Str
%nl  = Constant("\n") :Str
%p   = Print(%sv, %nl)
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Stringify of a Num that is NOT exactly representable

`0.1` is the case that separates real float formatting from a decimal shortcut:
the stored double is 0.1000000000000000055511151231257827, and perl prints
`0.1`. A renderer that emitted the stored value, or a fixed number of decimal
places, would fail here while passing every case above.

```perl
# source
use 5.42.0;
say 0.1; say(1);
```

```behavior
stdout: 0.1\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%v   = Constant(0.1) :Num
%sv  = Coerce(%v, from_repr: "Num", to_repr: "Str") :Str
%nl  = Constant("\n") :Str
%p   = Print(%sv, %nl)
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## A COMPUTED Num stringifies (not just a literal)

The value must survive arithmetic and still print as perl prints it. `3 / 4` is
float division over two Ints (each coerced to Num by Slice A's
`Coerce(Int->Num)`), so this exercises the coercion chain into the renderer
rather than a folded literal.

```perl
# source
use 5.42.0;
our $a = 3;
our $b = 4;
say $a / $b; say(1);
```

```behavior
stdout: 0.75\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%a   = Constant(3) :Int
%b   = Constant(4) :Int
%ca  = Coerce(%a, from_repr: "Int", to_repr: "Num") :Num
%cb  = Coerce(%b, from_repr: "Int", to_repr: "Num") :Num
%d   = Divide(%ca, %cb) :Num
%sd  = Coerce(%d, from_repr: "Num", to_repr: "Str") :Str
%nl  = Constant("\n") :Str
%p   = Print(%sd, %nl)
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```
