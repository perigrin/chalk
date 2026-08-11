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
(cfg-blocks-phi).

G2 GREEN: DefinedOr lowers runtime-free via the Undef representation
(alloca+store+load defined bit) + a definedness branch (br on i1 defined bit) +
Phi to select the defined operand. The LHS is `Int`-typed (always defined), so
the definedness branch always takes the defined path. The return is :Int, and the
type-tagged output is `Int:3`.

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
%cn  = Constant("$a") :Str
%ca  = Constant(3) :Int
%vda = VarDecl(%cn, %ca) :Int
%pa  = PadAccess(%vda, "$a") :Int
%cnb = Constant("$b") :Str
%cb  = Constant(7) :Int
%vdb = VarDecl(%cnb, %cb) :Int
%pb  = PadAccess(%vdb, "$b") :Int
%r   = DefinedOr(%pa, %pb) :Int
return %r
control: %vda -> %vdb
L: GREEN
```

## L3b defined-or undef-left

Perl `//` with an undef left operand: the left operand is Undef, so `//`
returns the right operand.  For `$a = undef`, `$b = 7`, the result is `7`.
This is the RUNTIME-UNDEF path: the Undef representation uses alloca+store+load
to make the definedness bit runtime-opaque (not constant-foldable by the LLVM
optimizer).  The DefinedOr branches on the loaded i1 bit and the phi selects
the RHS value on the undef path.

```perl
# source
my $a = undef;
my $b = 7;
$a // $b
```

```behavior
return: 7
context: scalar
```

```ir
%cn    = Constant("$a") :Str
%cundef = Constant(undef) :Undef
%vda   = VarDecl(%cn, %cundef) :Undef
%pa    = PadAccess(%vda, "$a") :Undef
%cnb   = Constant("$b") :Str
%cb    = Constant(7) :Int
%vdb   = VarDecl(%cnb, %cb) :Int
%pb    = PadAccess(%vdb, "$b") :Int
%r     = DefinedOr(%pa, %pb) :Int
return %r
control: %vda -> %vdb
L: GREEN
```

## L3c defined-or with an early-return fallback

Perl `//` whose fallback is a function EXIT: `my $x = $a // return 99`. This is
NOT the operand-selecting `DefinedOr` -- the fallback LEAVES the sub when `$a`
is undefined, so it is a guarded early return, not a value. For `$a = 3`
(defined) the sub falls through: `$x = 3`, and returns `$x + 1 = 4`.

The producer models it as a guarded exit -- `If(Not(Defined($a)))` -- true when
`$a` is undef (the early-return path, the If's TRUE branch so it aligns with the
exit value in the single-exit Phi); the main path continues on the FALSE Proj
(index 1) where `$a` is defined and the dor value is `$a`. The two exits (the
early `return 99` and the fall-through `$x + 1`) merge through a Region + Phi
into the single-exit Return. Was a silent miscompile (the fallback return was
dropped and `$a // return 99` degenerated to `DefinedOr($a, $a)`); zhi
019f26a5.

```perl
# source
my $a = 3;
my $x = $a // return 99;
$x + 1
```

```behavior
return: 4
context: scalar
```

```ir
%a   = Constant(3) :Int
%def = Defined(%a) :Bool
%nd  = Not(%def) :Bool
%if  = If(%nd)
%p1  = Proj(%if, index: 1)
%c99 = Constant(99) :Int
%c1  = Constant(1) :Int
%add = Add(%a, %c1) :Int
%reg = Region(%p1)
%phi = Phi(%c99, %add) :Int
return %phi
L: GREEN
```

## L5 void print in a true && arm

`EXPR && (print ...)` in VOID context is a short-circuit whose RHS arm is
evaluated for its SIDE EFFECT (the `print`), not its value — the same statement
modifier shape as `print ... if EXPR`. The arm fires ONLY when the left operand
is truthy. For `$x == $x` (always true) the print fires, so stdout is `y\n`; the
block's trailing `1` is the return value `Int:1`.

The producer effect-threads the void arm `print` on the arm's control path (the
If's TRUE Proj) exactly like an element-store or void-call arm, and merges the
arms so the Print is control-dependent on the guard — it survives DCE and emits
only when the arm is taken.

```perl
# source
my $x = 1; $x == $x && (print "y\n"); 1
```

```behavior
stdout: y\n
return: Int:1
context: scalar
```

```ir
%s0 = Constant("y\n") :Str
%p  = Print(%s0) :Bool
%c  = Constant(1) :Int
return %c
L: GREEN
```

## L5b void print in a false && arm (does not fire)

Bilateral to L5: when the left operand is FALSE the `&&` short-circuits and the
arm `print` does NOT fire. For `$x != $x` (always false) the print is skipped, so
stdout is empty; the block's trailing `1` returns `Int:1`. The Print is
control-dependent on the guard's TRUE Proj, so a false guard emits nothing.

```perl
# source
my $x = 1; $x != $x && (print "y\n"); 1
```

```behavior
return: Int:1
context: scalar
```

```ir
%s0 = Constant("y\n") :Str
%p  = Print(%s0) :Bool
%c  = Constant(1) :Int
return %c
L: GREEN
```

## L5c void print in a false || arm (fires when left is false)

The `||` polarity of L5: `EXPR || (print ...)` fires the arm `print` when the
left operand is FALSE (`||` short-circuits on a truthy left). For `$x != $x`
(always false) the arm is reached, so stdout is `y\n`; the block's trailing `1`
returns `Int:1`. The producer builds the body on the FALSE Proj for `or`
(matching the `unless` polarity), so the Print is control-dependent on the guard
being false.

```perl
# source
my $x = 1; $x != $x || (print "y\n"); 1
```

```behavior
stdout: y\n
return: Int:1
context: scalar
```

```ir
%s0 = Constant("y\n") :Str
%p  = Print(%s0) :Bool
%c  = Constant(1) :Int
return %c
L: GREEN
```

## L5d last-statement `&&` with a print arm (Bool operands, WANT=0)

The cond.t idiom: `EXPR && (print ...)` as the LAST statement of the block, so its
value is the block's RETURN (OPf_WANT=0, NOT OPf_WANT_VOID). Unlike L5 (which has a
trailing `1`, making the `&&` a mid-body VOID statement that the producer lowers to
control flow), the last-statement form is lowered as a value-returning `And` node
whose operands are BOTH Bool (the `StrEq` guard and the `Print`, which returns a
`builtin::is_bool` boolean).

`$x eq $x` is always true, so the `&&` reaches the print arm: stdout is `y\n`. Perl
`A && B` returns B when A is truthy, so the block returns the print's Bool `1`. The
backend expands `And` into short-circuit br+phi: the Bool LHS is already the i1 branch
condition (its truthiness is the identity, no `icmp ne i64`), the print fires only on
the truthy branch, and the i1 phi merges the two Bool operands. (t/base/cond.t.)

```perl
# source
my $x = "a"; $x eq $x && (print "y\n")
```

```behavior
stdout: y\n
return: Bool:1
context: scalar
```

```ir
%xa = Constant("a") :Str
%eq = StrEq(%xa, %xa) :Bool
%s0 = Constant("y\n") :Str
%p  = Print(%s0) :Bool
%r  = And(%eq, %p) :Bool
return %r
L: GREEN
```

## L5e last-statement `||` with a print arm (Bool operands, WANT=0)

Bilateral `||` polarity of L5d, matching cond.t's actual last line (`$x != $x ||
(print ...)`). `$x ne $x` is always FALSE, so `||` short-circuits to the RIGHT arm and
the print fires: stdout is `y\n`. Perl `A || B` returns B when A is falsy, so the
block returns the print's Bool `1`. The backend `Or` br+phi tests the Bool LHS
directly (i1 truthiness = identity) and merges an i1 phi.

```perl
# source
my $x = "a"; $x ne $x || (print "y\n")
```

```behavior
stdout: y\n
return: Bool:1
context: scalar
```

```ir
%xa = Constant("a") :Str
%ne = StrNe(%xa, %xa) :Bool
%s0 = Constant("y\n") :Str
%p  = Print(%s0) :Bool
%r  = Or(%ne, %p) :Bool
return %r
L: GREEN
```

## L4 not

Perl `!` returns a genuine BOOLEAN: `!5` is `false`, `!0` is `true`. These are
primitive booleans (`is_bool(!5)`=1, `is_bool(!0)`=1 — verified), NOT strings.
A boolean *coerces* to `""`/`"1"` in string context and `0`/`1` in numeric
context, but its identity is Bool, not Str (a literal `""` has `is_bool`=0).

G2 GREEN: `!` lowers runtime-free via the Bool representation (i1) + UnaryNot
(xor i1 %cond, true) + Coerce(Int->Bool) truthiness (icmp ne). The return value
is :Bool (i1), and the type-tagged epilogue selects between `@bool_true_str`
("Bool:1\n") and `@bool_false_str` ("Bool:\n") directly — no Coerce(Bool->Str)
node is in the return path. Coerce(Bool->Str) is the edge for internal string-context
use (e.g., a Bool in string interpolation), exercised separately; its string-face
globals ("1\0" and "\0") are distinct from the tagged epilogue constants ("Bool:1\n"
and "Bool:\n"). The type-tagged oracle (`Bool:` for false, `Bool:1` for true)
distinguishes a Bool result from its Str coercion (which would be `Str:`) — so
Int-as-0 or Str-as-empty miscompiles are caught at the oracle layer.

Source: `my $a = 5; !$a` — $a is 5 (truthy), so !$a is false. The ir-block
models the Not over a PadAccess(:Int), coercing Int to Bool via truthiness, then
negating. The final return is :Bool, and the type-tagged output is `Bool:`.

```perl
# source
my $a = 5;
!$a
```

```behavior
return: Bool:
context: scalar
```

```ir
%cn   = Constant("$a") :Str
%c5   = Constant(5) :Int
%vd   = VarDecl(%cn, %c5) :Int
%pa   = PadAccess(%vd, "$a") :Int
%b    = Coerce(%pa : Int -> Bool) :Bool
%nb   = Not(%b) :Bool
return %nb
control: %vd
L: GREEN
```

## L6 string equality (eq) — t/base blocker (if.t/num.t string compare)

The `eq` string-comparison operator lowers to a `StrEq` op: a byte-compare of the
two Str {ptr,len} buffers. Equality = same length AND memcmp==0. StrEq yields a
Bool (i1) that the ternary condition selects on. The if.t/num.t assertions compare
strings; this is the blocker they hit. The `my $a=..; my $b=..` operands
propagate to Str constants (perl folds the pad reads), leaving a genuine StrEq
node on distinct constants — perl folds `"x" eq "x"` outright only when BOTH sides
are literal in the same op, which is why the pad form keeps the compare.

```perl
# source
my $a = "x";
my $b = "x";
($a eq $b) ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%ax = Constant("x") :Str
%bx = Constant("x") :Str
%eq = StrEq(%ax, %bx) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%eq, %t, %f) :Int
return %r
L: GREEN
```

## L6b string equality — unequal same-length (eq is false)

Bilateral against L6: two DIFFERENT single-char strings. Same length, differing
bytes, so the memcmp is nonzero and `eq` is false — the ternary selects the false
arm (0). This proves the memcmp leg is real, not a constant-true.

```perl
# source
my $a = "x";
my $b = "y";
($a eq $b) ? 1 : 0
```

```behavior
return: 0
context: scalar
```

```ir
%ax = Constant("x") :Str
%by = Constant("y") :Str
%eq = StrEq(%ax, %by) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%eq, %t, %f) :Int
return %r
L: GREEN
```

## L6c string equality — different length (length guard, eq is false)

Bilateral against L6: "ab" vs "abc" — DIFFERENT lengths. The length guard
short-circuits to false BEFORE any memcmp (a memcmp of len_a bytes over the shorter
buffer would over-read). `eq` is false, ternary selects 0. This proves the length
guard gates the memcmp.

```perl
# source
my $a = "ab";
my $b = "abc";
($a eq $b) ? 1 : 0
```

```behavior
return: 0
context: scalar
```

```ir
%aab  = Constant("ab") :Str
%babc = Constant("abc") :Str
%eq   = StrEq(%aab, %babc) :Bool
%t    = Constant(1) :Int
%f    = Constant(0) :Int
%r    = TernaryExpr(%eq, %t, %f) :Int
return %r
L: GREEN
```

## L6d string equality with an INT operand (`$a eq "1"`, t/base/num.t blocker)

Perl `eq` compares STRINGS, so an Int operand is stringified to its decimal form
first: `1 eq "1"` stringifies `1` to `"1"` and byte-compares (equal, true).
The backend stringifies the Int operand (the shared int-to-decimal renderer,
`_emit_int_to_str`, also used by interpolation's Stringify[Int]) into a
length-tracked {ptr,len}, then runs the same length-guard + memcmp as a Str/Str
compare. This is the t/base/num.t first blocker (`$a = 1; $a eq "1"`), and also
covers octal/hex/binary integer literals (`0x100 eq "256"`) since those are Ints.

```perl
# source
my $a = 1; ($a eq "1") ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%a  = Constant(1) :Int
%s1 = Constant("1") :Str
%eq = StrEq(%a, %s1) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%eq, %t, %f) :Int
return %r
L: GREEN
```

## L6e int-eq is a real byte compare (negative int, and a mismatch is false)

Bilateral against L6d: a NEGATIVE int stringifies with its sign (`-1` -> `"-1"`,
the renderer prepends '-'), so `-1 eq "-1"` is true; and a value/string mismatch
(`1 eq "2"`) is false — proving the stringified bytes are really compared, not a
constant-true. This case uses the mismatch (`1 eq "2"` -> 0) as the distinguishing
check.

```perl
# source
my $a = 1; ($a eq "2") ? 1 : 0
```

```behavior
return: 0
context: scalar
```

```ir
%a  = Constant(1) :Int
%s2 = Constant("2") :Str
%eq = StrEq(%a, %s2) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%eq, %t, %f) :Int
return %r
L: GREEN
```

## L7 string inequality (ne) — t/base blocker

The `ne` operator lowers to `StrNe`, the negation of StrEq — same byte-compare,
result xored with 1. Bilateral with L6: L6 tests eq of equal strings, L7 tests ne
of DIFFERENT strings (both true).

```perl
# source
my $a = "x";
my $b = "y";
($a ne $b) ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%ax = Constant("x") :Str
%by = Constant("y") :Str
%ne = StrNe(%ax, %by) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%ne, %t, %f) :Int
return %r
L: GREEN
```

## L7b string inequality — equal strings (ne is false)

Bilateral against L7: two EQUAL strings, so `ne` is false (StrEq true, xored to
false) and the ternary selects the false arm (0). This proves the xor negation is
real, not a constant-true.

```perl
# source
my $a = "x";
my $b = "x";
($a ne $b) ? 1 : 0
```

```behavior
return: 0
context: scalar
```

```ir
%ax = Constant("x") :Str
%bx = Constant("x") :Str
%ne = StrNe(%ax, %bx) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%ne, %t, %f) :Int
return %r
L: GREEN
```

## L9 numeric equality (==) over Str operands — t/base/cond.t blocker

Perl `==` is NUMERIC: string operands are numified (leading-numeric rule) then
compared as numbers. `"0" == "0"` numifies both to 0 and is TRUE. This is the
t/base/cond.t blocker: `$x == $x` where `$x` is a string package scalar. The
backend must coerce each Str operand to Num (double, via @chalk_str_to_num) and
`fcmp oeq` the doubles — NOT `icmp i64` on the raw i8* pointers.

Bilateral against L6 (StrEq): L6 is BYTE equality (memcmp), L9 is NUMERIC
equality (numify then compare). `"0"` and `"0"` are byte-equal here too, so the
distinguishing case is L9b (`" 3"` vs `"3"` — numerically equal, byte-unequal).

```perl
# source
my $x = "0"; ($x == $x) ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%x0 = Constant("0") :Str
%eq = NumEq(%x0, %x0) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%eq, %t, %f) :Int
return %r
L: GREEN
```

## L9b numeric equality — byte-unequal but numerically equal (`" 3"` == `"3"`)

The case that separates NUMERIC `==` from BYTE `eq`: `" 3"` (leading space) and
`"3"` are byte-UNEQUAL (StrEq would be false) but numerically EQUAL (both numify
to 3), so `==` is TRUE. Proves the operands are numified, not memcmp'd.

```perl
# source
my $a = " 3"; my $b = "3"; ($a == $b) ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%a = Constant(" 3") :Str
%b = Constant("3") :Str
%eq = NumEq(%a, %b) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%eq, %t, %f) :Int
return %r
L: GREEN
```

## L9c numeric inequality (!=) over Str operands (cond.t `$x != $x`)

The `!=` polarity, matching cond.t's `$x != $x` / `$x != $y` lines. `"0" != "1"`
numifies to `0 != 1` = TRUE. `fcmp une` (unordered-or-not-equal) is the float
`!=` predicate.

```perl
# source
my $x = "0"; my $y = "1"; ($x != $y) ? 1 : 0
```

```behavior
return: 1
context: scalar
```

```ir
%x = Constant("0") :Str
%y = Constant("1") :Str
%ne = NumNe(%x, %y) :Bool
%t  = Constant(1) :Int
%f  = Constant(0) :Int
%r  = TernaryExpr(%ne, %t, %f) :Int
return %r
L: GREEN
```

## L8 void call in an `and` arm — t/ near-miss (simple form GREEN)

`EXPR and (print ...)` — the low-precedence `and` form of the `&&`-arm void print
(I7). The SIMPLE form already lowers (the arm print is effect-threaded on the taken
control path). The t/ files hit a harder variant (an `and` arm that combines a
void call with a scalar rebind — the 2b-3 mixed-effect GAP), which still GAPs.
This case locks the working simple form.

```perl
# source
my $c = 1;
$c and (print "y\n");
1
```

```behavior
stdout: y
return: 1
context: scalar
```

```ir
%c      = Constant(1) :Int
%if     = If(%c) :Control
%pt     = Proj(%if, index: 0) :Control
%msg    = Constant("y\n") :Str
%print  = Print(%pt, %msg) :Bool
%region = Region(%if, %print) :Control
%one    = Constant(1) :Int
return %one
L: GREEN
```

## L6f `eq` coerces a NUM operand (t/base/num.t idiom)

`eq` compares STRINGS: its signature is `(Str, Str)`, so a Num operand is
coerced by an explicit `Stringify` inserted at the producer build site — the
same treatment `Print`'s arguments get. `eq` does not learn a representation.

This is `t/base/num.t`'s central idiom (`$a = 0.1; $a eq "0.1"`). It was
previously a GAP reading "string comparison stringifies only Str and Int
operands runtime-free; Num stringification for eq/ne is unbuilt" — because the
backend carried its OWN int-to-decimal renderer inside the comparison, separate
from `Stringify`'s. Routing the operand through the coercion made Num work with
no new rendering code at all.

```perl
# source
use 5.42.0;
our $a = 0.1;
say($a eq "0.1" ? "y" : "n"); 1
```

```behavior
stdout: y\n
return: Int:1
context: scalar
```

```ir
%v   = Constant(0.1) :Num
%sv  = Coerce(%v, from_repr: "Num", to_repr: "Str") :Str
%lit = Constant("0.1") :Str
%eq  = StrEq(%sv, %lit) :Bool
%y   = Constant("y") :Str
%n   = Constant("n") :Str
%t   = TernaryExpr(%eq, %y, %n) :Str
%nl  = Constant("\n") :Str
%p   = Print(%t, %nl)
%one = Constant(1) :Int
return %one
control: %p
L: GREEN
```

## L6g `eq` over a Num that does NOT match (bilateral)

The partner of L6f. Without it, L6f passes against a comparison that always
answers true — which is exactly what a dropped or misrendered operand would
produce.

```perl
# source
use 5.42.0;
our $a = 0.1;
say($a eq "0.2" ? "y" : "n"); 1
```

```behavior
stdout: n\n
return: Int:1
context: scalar
```

```ir
%v   = Constant(0.1) :Num
%sv  = Coerce(%v, from_repr: "Num", to_repr: "Str") :Str
%lit = Constant("0.2") :Str
%eq  = StrEq(%sv, %lit) :Bool
%y   = Constant("y") :Str
%n   = Constant("n") :Str
%t   = TernaryExpr(%eq, %y, %n) :Str
%nl  = Constant("\n") :Str
%p   = Print(%t, %nl)
%one = Constant(1) :Int
return %one
control: %p
L: GREEN
```

## L6h a Num whose value is INTEGRAL (1e3 stringifies as "1000")

An integral float reaches the backend as a bare integer literal — `1e3` and
`2.0` both arrive as "1000" / "2" — and LLVM rejects an integer constant in a
double operand ("integer constant must have integer type"). The emitted module
did not run AT ALL: `say 1e3` produced `fadd double 0.0, 1000` and lli refused
it, exit 1 with no output.

This case pins both halves: the constant is emitted as a double, and `%.15g`
renders it as perl does — `1000`, not `1000.0` or `1e+03`.

```perl
# source
use 5.42.0;
our $a = 1e3;
say($a eq "1000" ? "y" : "n"); 1
```

```behavior
stdout: y\n
return: Int:1
context: scalar
```

```ir
%v   = Constant(1000) :Num
%sv  = Coerce(%v, from_repr: "Num", to_repr: "Str") :Str
%lit = Constant("1000") :Str
%eq  = StrEq(%sv, %lit) :Bool
%y   = Constant("y") :Str
%n   = Constant("n") :Str
%t   = TernaryExpr(%eq, %y, %n) :Str
%nl  = Constant("\n") :Str
%p   = Print(%t, %nl)
%one = Constant(1) :Int
return %one
control: %p
L: GREEN
```
