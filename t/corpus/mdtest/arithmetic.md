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
