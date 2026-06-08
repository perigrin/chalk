# Strings

String literals, concatenation, and interpolation idioms.

Str representation is `{ ptr, len, encoding }` where `encoding` is a tagged
enum (0=ASCII/default, 1=UTF-8, 2=UTF-16, ...). The ASCII/default slice (enc=0)
is fully lowered: S1-S4 are GREEN. A non-ASCII (non-default-encoding) case is
explicitly asserted GAP (honest boundary — no silent cap). The campaign forbids
silently dropping coverage; S5 is the required explicit boundary marker.

Archive source: `archive/pu-2026-03-24:t/corpus/ir/string-sq.chalk` (S1),
`archive/pu-2026-03-24:t/corpus/ir/string-dq.chalk` (S2),
`archive/pu-2026-03-24:t/corpus/ir/string-concat.chalk` (S3), and
gap-map entry C3 (S4).

## S1 single-quoted literal

A single-quoted string literal produces a Str-typed constant node. Str is RF:
its representation is `{ptr, len, encoding}` (enc=0 = ASCII/default). A string
constant lowers to a private global, len = byte count, enc = 0.

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
%nc  = Constant("s") :Str
%val = Constant("hello") :Str
%vd  = VarDecl(%nc, %val) :Str
%pa  = PadAccess(%vd, "s") :Str
control: %vd
return %pa
L: GREEN
```

## S2 double-quoted literal

A double-quoted string literal with no interpolation produces a Str constant,
identical to a single-quoted literal at the IR level.

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
%nc  = Constant("s") :Str
%val = Constant("hello world") :Str
%vd  = VarDecl(%nc, %val) :Str
%pa  = PadAccess(%vd, "s") :Str
control: %vd
return %pa
L: GREEN
```

## S3 string concatenation (dot operator)

The dot operator concatenates two string values. The IR models this as a Concat
node. Both operands and the result carry Str representation. Concat is RF: it
lowers to malloc+memcpy over `{ptr,len,enc}` buffers.

```perl
# source
"hello" . " world"
```

```behavior
return: hello world
context: scalar
```

```ir
%lhs = Constant("hello") :Str
%rhs = Constant(" world") :Str
%cat = Concat(%lhs, %rhs) :Str
return %cat
L: GREEN
```

## S4 string concat-assign (.=)

The compound-assign `.=` appends to an existing string variable. A Concat node
replaces the binding in the SSA var_table. Both the VarDecl and the Concat carry
Str representation. The PadAccess after `.=` sees the post-concat SSA value.

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
%nc   = Constant("s") :Str
%va   = Constant("a") :Str
%vd   = VarDecl(%nc, %va) :Str
%pa1  = PadAccess(%vd, "s") :Str
%vb   = Constant("b") :Str
%cat  = Concat(%pa1, %vb) :Str
%asgn = Assign(%pa1, %cat) :Str
%pa2  = PadAccess(%vd, "s") :Str
control: %vd -> %asgn
return %pa2
L: GREEN
```

## S5 non-ASCII string (non-default encoding, explicit GAP boundary)

A string containing non-ASCII characters such as cafe-with-accent (cafe\x{e9})
has byte-len 5 but char-len 4 (the accented e is 2 bytes in UTF-8). The encoding
tag would be non-zero (UTF-8). The ASCII/default-encoding slice (enc=0) does not
cover this case: length must return 4 (char count), not 5 (byte count). This
encoding path is not yet lowered. This GAP is the REQUIRED explicit boundary marker
-- the campaign forbids silently dropping non-ASCII coverage.

```perl
# source
my $s = "caf\x{e9}";
length($s)
```

```behavior
return: 4
context: scalar
```

```ir
L: GAP(non-ASCII Str with enc!=0 not yet lowered: char-len 4 != byte-len 5; a future UTF-8 encoding issue closes this path)
```
