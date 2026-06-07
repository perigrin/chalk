# Strings

String literals, concatenation, and interpolation idioms.

All cases in this topic are L: GAP — but Str is runtime-free (RF). Per the
runtime-free boundary, every in-subset value is a machine representation plus
coercions; there is no libperl/SV* dependency. Str's representation is a
`{ptr, len}` machine string buffer (NOT an SV*): constants are static data,
concat is alloc+copy, Coerce(Str→Num) is perl's leading-numeric rule, and
Coerce(Str→Bool) maps `""`/`"0"` to false. These cases are GAPs only until the
Str representation is modelled (campaign group G3) — not because they need the
interpreter. The behavior is specified by the perl oracle; each GAP records the
work-list item that closes it.

Archive source: `archive/pu-2026-03-24:t/corpus/ir/string-sq.chalk` (S1),
`archive/pu-2026-03-24:t/corpus/ir/string-dq.chalk` (S2),
`archive/pu-2026-03-24:t/corpus/ir/string-concat.chalk` (S3), and
gap-map entry C3 (S4).

## S1 single-quoted literal

A single-quoted string literal produces a Str-typed constant node. Str is
RF: its representation is a `{ptr, len}` machine string buffer, and a string
constant lowers to static data — no SV* allocation, no interpreter. The GAP
is only that the Str representation is not modelled yet.

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
L: GAP(Str is RF: a {ptr,len} machine buffer + coercions; GAP only until the Str representation (G3) is modelled, NOT a libperl/SV dependency)
```

## S2 double-quoted literal

A double-quoted string literal with no interpolation behaves identically to
a single-quoted literal at the IR level — the value is a Str constant. The
same RF `{ptr, len}` buffer representation applies; the GAP is equally just
that the Str representation is not modelled yet.

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
L: GAP(Str is RF: a {ptr,len} machine buffer + coercions; GAP only until the Str representation (G3) is modelled, NOT a libperl/SV dependency)
```

## S3 string concatenation (dot operator)

The dot operator concatenates two string values into a new string. The IR
models this as a StrConcat node whose operands and result carry Str
representation. Concat is RF: it lowers to alloc+copy over `{ptr, len}`
buffers — no SV*, no interpreter. The GAP is only that the Str representation
and its concat operation are not modelled yet (campaign group G3).

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
L: GAP(StrConcat is RF: alloc+copy over {ptr,len} buffers; GAP only until the Str representation (G3) is modelled, NOT a libperl/SV dependency)
```

## S4 string concat-assign (.=)

The compound-assign `.=` appends to an existing string variable. This
involves both a Str-typed VarDecl and a StrConcat node that replaces the
binding. Both are RF: the binding holds a `{ptr, len}` buffer and the
append is alloc+copy — no SV*, no interpreter. The GAP is only that the Str
representation and its concat are not modelled yet (campaign group G3).

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
L: GAP(Concat/.= is RF: a {ptr,len} buffer + alloc+copy append; GAP only until the Str representation (G3) is modelled, NOT a libperl/SV dependency)
```
