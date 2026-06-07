# Arithmetic

Integer and numeric arithmetic, the coercion model, and Perl-specific
division/modulo semantics.

## Integer addition

Two integer literals add as native machine integers — no coercion, no SV.

```perl
# source
1 + 2
```

```behavior
return: 3
context: scalar
```

```ir
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
```

## Integer subtraction

Five minus three — native i64 subtract, no coercion.

```perl
# source
5 - 3
```

```behavior
return: 2
context: scalar
```

```ir
%c5  = Constant(5) :Int
%c3  = Constant(3) :Int
%sub = Subtract(%c5, %c3) :Int
return %sub
L: GREEN
```

## Integer multiplication

Three times four — native i64 multiply.

```perl
# source
3 * 4
```

```behavior
return: 12
context: scalar
```

```ir
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%mul = Multiply(%c3, %c4) :Int
return %mul
L: GREEN
```

## Float division

Perl `/` is ALWAYS float division — `3 / 4` is `0.75`, not `0`. The IR must
coerce both operands to Num and divide as a double.

```perl
# source
3 / 4
```

```behavior
return: 0.75
context: scalar
```

```ir
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%d3  = Coerce(%c3 : Int -> Num) :Num
%d4  = Coerce(%c4 : Int -> Num) :Num
%div = Divide(%d3, %d4) :Num
return %div
L: GREEN
```

## Integer modulo right-sign

Perl `%` follows the sign of the RIGHT operand: `-7 % 3 == 2` (LLVM `srem`
gives -1). The IR lowers with sign-correction.

```perl
# source
-7 % 3
```

```behavior
return: 2
context: scalar
```

```ir
%cn7 = Constant(-7) :Int
%c3  = Constant(3) :Int
%mod = Modulo(%cn7, %c3) :Int
return %mod
L: GREEN
```
