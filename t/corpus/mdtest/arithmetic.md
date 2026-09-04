# Arithmetic

Integer and numeric arithmetic, the coercion model, and Perl-specific
division/modulo semantics.

## Integer addition

Two integer literals add as native machine integers — no coercion, no SV.

```perl
# source
use 5.42.0;
say(1 + 2);
```

```behavior
stdout: 3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%add : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Integer subtraction

Five minus three — native i64 subtract, no coercion.

```perl
# source
use 5.42.0;
say(5 - 3);
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c5  = Constant(5) :Int
%c3  = Constant(3) :Int
%sub = Subtract(%c5, %c3) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%sub : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Integer multiplication

Three times four — native i64 multiply.

```perl
# source
use 5.42.0;
say(3 * 4);
```

```behavior
stdout: 12\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%mul = Multiply(%c3, %c4) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%mul : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Float division

Perl `/` is ALWAYS float division — `3 / 4` is `0.75`, not `0`. The IR must
coerce both operands to Num and divide as a double.

```perl
# source
use 5.42.0;
say(3 / 4);
```

```behavior
stdout: 0.75\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%d3  = Coerce(%c3 : Int -> Num) :Num
%d4  = Coerce(%c4 : Int -> Num) :Num
%div = Divide(%d3, %d4) :Num
%nl = Constant("\n") :Str
%co_p  = Coerce(%div : Num -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Integer modulo right-sign

Perl `%` follows the sign of the RIGHT operand: `-7 % 3 == 2` (LLVM `srem`
gives -1). The IR lowers with sign-correction.

```perl
# source
use 5.42.0;
say(-7 % 3);
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%cn7 = Constant(-7) :Int
%c3  = Constant(3) :Int
%mod = Modulo(%cn7, %c3) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%mod : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Integer literal exceeding 32 bits

A bare integer literal larger than 2**31-1 (`4294967296`, i.e. `2**32`) must
round-trip through the IR and the LLVM backend as a full 64-bit value — Perl
integers are native machine integers (i64), not 32-bit. This is a worklist
case: the current backend narrows the Constant through an i32 somewhere on
the return-epilogue path, so it prints `Int:0` (the low 32 bits of
`4294967296` truncated to zero) instead of the correct `Int:4294967296`.

```perl
# source
use 5.42.0;
say(4294967296);
```

```behavior
stdout: 4294967296\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c = Constant(4294967296) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%c : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Int exceeding 2^53 entering a Num context loses precision

`my $n = 9007199254740993; my $s = $n + 0.0;` prints `9007199254740993` in perl
and `9.00719925474099e+15` here. A SILENT WRONG ANSWER from ordinary source --
no GAP, no error, just a different number.

The cause is the OBJECT map, not the arrow map. `Coerce(Int -> Num)` forces a
`sitofp` because `%_REPR_LLVM_TYPE` maps `Num` to `double`, and an i64 above
2^53 does not survive a double's 53-bit mantissa. The precision is gone at the
Coerce, BEFORE `Add` runs -- adding `0.0` is not what breaks it, entering `Num`
is.

Perl does not have this problem because it keeps an IV and an NV as distinct
representations of one scalar: `B::svref_2object(\9007199254740993)` is a
`B::IV` and stays one across `+ 0.0`. Chalk's `Num` is likewise a UNION, and
`Chalk::IR::Transform::T2` already records it as the candidate SET
`['double','i64']` -- but `T2::_choose` returns `$candidates->[0]`
unconditionally, and T2 is not wired into lowering at all, so `double` always
wins.

Fixing it needs a per-site representation choice driven by what the value is
OBSERVED to do, which `Context.pm:4640`'s standing note describes and which 46
context-free `_repr_to_llvm_type` call sites currently assume away. That is a
real piece of work, not a table edit. Flipping `Num` to `i64` wholesale was
measured: the composition table collapses from 224 rows to 53, and the cause is
not "fractions stop lowering" but a genuine TYPE CONFLICT -- `my $x = 1.5`
emits `floating point constant invalid for type`, because the literal demands
`double` and the map now says `i64`. LLVM rejects it outright.

That error is the shape of the whole problem. CHALK's types are ORDERED
(Int <: Num <: Str), so T1's operation is a JOIN, and unification would be
wrong there -- it would force Int = Num. But LLVM's types are UNORDERED: `i64`
and `double` have no relation, no subtyping, no implicit conversion. Discrete
equality is exactly what UNIFICATION wants, so T2 -- not T1 -- is the
HM-shaped pass (perigrin, 2026-09-04).

Read that way, `%_REPR_LLVM_TYPE` is a PREMATURE SUBSTITUTION: it binds every
`Num` to `double` before a single constraint has been seen, and flipping it to
`i64` is the same mistake with the other value. The candidate set IS a
unification variable; the literal `1.5` and an `fdiv` are unifications that
bind it; a variable still free at emission needs DEFAULTING, which is a real HM
notion -- GHC defaults numeric literals and RuntimeRep the same way -- rather
than an improvisation.

Recorded as GAP rather than fixed, so the wrong answer is pinned and visible.

```perl
# source
use 5.42.0;
my $n = 9007199254740993;
my $s = $n + 0.0;
print $s, "\n";
```

```behavior
stdout: 9007199254740993\n
return: Bool:1
context: scalar
```

NOT DECLARED A GAP, AND THE GATE IS RIGHT TO REFUSE ONE. A first version of
this case carried `L: GAP(...)`, and the gate rejected it with "a
corpus-declared GAP that LOWERS BUT DISAGREES with perl ... the declaration was
hiding a miscompile, not an absence." That is exactly what it was: a GAP
declaration is a claim that the case DOES NOT COMPILE, and this one compiles
and gets the answer wrong.

Nor is it a `DEVIATES` case. That verdict is for output that is legal Perl
which a static compiler CANNOT match, and this is the other kind: chalk emits a
float only because `_join_repr(Int, Num)` is `Num` and `Num` means `double` --
a choice made before any constraint is seen. perl gets it exact and so could
chalk. Labelling it would freeze a defect behind a legitimising name.

So it stands as a plain worklist failure: the case is red, the number is
honest, and the gate names it every run until the representation choice is
fixed. See docs/plans/2026-09-04-perl-decides-repr-by-value-not-type.md for why
the fix is narrow-and-promote rather than "narrow Num to i64 here".


## Integer literal at INT64_MIN

The most negative representable i64 (`-9223372036854775808`, i.e. `-2**63`)
is a legal Perl integer literal and must lower without overflow or
truncation. This is a worklist case: the current backend's narrowing (the
same i32 path that truncates `2**32`, see the case above) also mishandles
this boundary value, printing `Int:0` instead of the correct
`Int:-9223372036854775808`.

```perl
# source
use 5.42.0;
say(-9223372036854775808);
```

```behavior
stdout: -9223372036854775808\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c = Constant(-9223372036854775808) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%c : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Out-of-bounds array read on a 2-element array reaches the Slot-Int epilogue

A second out-of-bounds instance alongside R9 (references.md): a 2-element
array (`my @a=(1,2)`) read at index 5 also returns perl's `undef` via the
`Slot{defined=false, payload=0}` epilogue. MEASURED (2026-07-20): this case
is already GREEN on head — it exercises the same `@fmt_slot_int`-adjacent
epilogue as R9 with different literal array/index values, so it acts as a
second regression lock on the OOB-Slot format site rather than a new
worklist case.

```perl
# source
use 5.42.0;
my @a=(1,2); say($a[5]);
```

```behavior
stdout: \n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%arr = ArrayLiteral(%c1, %c2) :Array
%idx = Constant(5) :Int
%r   = Subscript(%arr, %idx) :Undef
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Undef -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## Float division of two variables

Perl `/` is ALWAYS float division, including when both operands are
variables rather than literals (see "Float division" above for the literal
case, which constant-folds). `my $x=3; my $y=4; $x/$y` must lower to
`0.75`. This is a worklist case: the current backend emits a divide
(`Divide`, repr `Num`) whose operands are not both coerced to `double`
before the `fdiv` — `lli` rejects the module outright (`'%tmp' defined with
type 'i64' but expected 'double'`), a type mismatch at the LLVM IR level
rather than a wrong-value miscompile.

```perl
# source
use 5.42.0;
my $x=3; my $y=4; say($x/$y);
```

```behavior
stdout: 0.75\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c3   = Constant(3) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %c3) :Int
%c4   = Constant(4) :Int
%yn   = Constant("$y") :Str
%vy   = VarDecl(%yn, %c4) :Int
%rx   = PadAccess(%vx, "$x") :Int
%ry   = PadAccess(%vy, "$y") :Int
%dx   = Coerce(%rx : Int -> Num) :Num
%dy   = Coerce(%ry : Int -> Num) :Num
%div  = Divide(%dx, %dy) :Num
%nl = Constant("\n") :Str
%co_p  = Coerce(%div : Num -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```
