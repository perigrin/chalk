# Strings

String literals, concatenation, and interpolation idioms.

All cases in this topic are L: GAP — string values require a Str/Scalar (SV*)
representation that is not yet part of the runtime-free lowering slice (which
covers only Int/Num arithmetic and Bool). The behavior is still specified by the
perl oracle; the GAP records the honest reason a compile-time-only LLVM path
cannot yet lower these idioms.

Archive source: `archive/pu-2026-03-24:t/corpus/ir/string-sq.chalk` (S1),
`archive/pu-2026-03-24:t/corpus/ir/string-dq.chalk` (S2),
`archive/pu-2026-03-24:t/corpus/ir/string-concat.chalk` (S3), and
gap-map entry C3 (S4).

## S1 single-quoted literal

A single-quoted string literal produces a Str-typed constant node. The
value is not an integer or float so the Int/Num lowering slice cannot
represent it; a Scalar (SV*) allocation is required at runtime.

```perl
# source
my $s = 'hello';
$s
```

```behavior
return: hello
context: scalar
```

```ir
L: GAP(Str constant needs Scalar/SV* representation; no runtime-free string literal lowering)
```

## S2 double-quoted literal

A double-quoted string literal with no interpolation behaves identically to
a single-quoted literal at the IR level — the value is a Str constant. The
Scalar (SV*) representation gap applies equally.

```perl
# source
my $s = "hello world";
$s
```

```behavior
return: hello world
context: scalar
```

```ir
L: GAP(Str constant needs Scalar/SV* representation; no runtime-free string literal lowering)
```

## S3 string concatenation (dot operator)

The dot operator concatenates two string values into a new string. The IR
models this as a StrConcat node whose operands and result carry Str
representation. StrConcat requires heap allocation (or at minimum a
char*/SV* layout) and is not runtime-free lowerable in the current
integer-arithmetic slice.

Source: `archive/pu-2026-03-24:t/corpus/ir/string-concat.chalk`:
`return "hello" . " world";`

```perl
# source
"hello" . " world"
```

```behavior
return: hello world
context: scalar
```

```ir
L: GAP(StrConcat needs Str/SV* representation; not runtime-free lowerable in the current Int/Num slice)
```

## S4 string concat-assign (.=)

The compound-assign `.=` appends to an existing string variable. This
requires both a Str-typed VarDecl and a StrConcat node that mutates (or
replaces) the binding. Neither the Str VarDecl nor the StrConcat are in
the runtime-free lowering slice.

Source: gap-map entry C3: `my $s = "a"; $s .= "b"; return $s`.

```perl
# source
my $s = "a";
$s .= "b";
$s
```

```behavior
return: ab
context: scalar
```

```ir
L: GAP(Concat/.= needs Str/SV* representation; not runtime-free lowerable in the current Int/Num slice)
```
