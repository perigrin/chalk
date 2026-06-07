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
# ir-tag: arith-add
Constant(1) :Int
Constant(2) :Int
Add(Int, Int) :Int
Return(Add)
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
# ir-tag: arith-sub
Constant(5) :Int
Constant(3) :Int
Subtract(Int, Int) :Int
Return(Subtract)
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
# ir-tag: arith-mul
Constant(3) :Int
Constant(4) :Int
Multiply(Int, Int) :Int
Return(Multiply)
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
# ir-tag: arith-div
Constant(3) :Int
Constant(4) :Int
Coerce(Int -> Num)
Coerce(Int -> Num)
Divide(Num, Num) :Num
Return(Divide)
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
# ir-tag: arith-mod
Constant(-7) :Int
Constant(3) :Int
Modulo(Int, Int) :Int
Return(Modulo)
L: GREEN
```
