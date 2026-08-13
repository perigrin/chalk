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
use 5.42.0;
my $s = 'hello';
say($s);
```

```behavior
stdout: hello\n
return: Bool:1
context: scalar
```

```ir
%nc  = Constant("s") :Str
%val = Constant("hello") :Str
%vd  = VarDecl(%nc, %val) :Str
%pa  = PadAccess(%vd, "s") :Str
control: %vd
%nl = Constant("\n") :Str
%p  = Print(%pa, %nl)
return %p
L: GREEN
```

## S2 double-quoted literal

A double-quoted string literal with no interpolation produces a Str constant,
identical to a single-quoted literal at the IR level.

```perl
# source
use 5.42.0;
my $s = "hello world";
say($s);
```

```behavior
stdout: hello world\n
return: Bool:1
context: scalar
```

```ir
%nc  = Constant("s") :Str
%val = Constant("hello world") :Str
%vd  = VarDecl(%nc, %val) :Str
%pa  = PadAccess(%vd, "s") :Str
control: %vd
%nl = Constant("\n") :Str
%p  = Print(%pa, %nl)
return %p
L: GREEN
```

## S3 string concatenation (dot operator)

The dot operator concatenates two string values. The IR models this as a Concat
node. Both operands and the result carry Str representation. Concat is RF: it
lowers to malloc+memcpy over `{ptr,len,enc}` buffers.

```perl
# source
use 5.42.0;
say("hello" . " world");
```

```behavior
stdout: hello world\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%lhs = Constant("hello") :Str
%rhs = Constant(" world") :Str
%cat = Concat(%lhs, %rhs) :Str
%nl = Constant("\n") :Str
%p  = Print(%cat, %nl)
return %p
control: %start -> %p
L: GREEN
```

## S4 string concat-assign (.=)

The compound-assign `.=` appends to an existing string variable. A Concat node
replaces the binding in the SSA var_table. Both the VarDecl and the Concat carry
Str representation. The PadAccess after `.=` sees the post-concat SSA value.

```perl
# source
use 5.42.0;
my $s = "a";
$s .= "b";
say($s);
```

```behavior
stdout: ab\n
return: Bool:1
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
%nl = Constant("\n") :Str
%p  = Print(%pa2, %nl)
return %p
L: GREEN
```

## S6 dynamic concat-assign (.= a variable)

A `.=` whose right-hand side is a VARIABLE (`$s .= $t`) rather than a literal.
perl compiles it to a dynamic `multiconcat` (OPpMULTICONCAT_APPEND, nargs=1): the
operand `$t` rides the stack and the aux_list holds only empty segments. The
decoder folds `$s . $t` into a Concat. Both operands are Str, so the Concat lowers
via the shared malloc+memcpy path. (The const-append `$s .= "b"` of S4 is the
nargs=0 form of the same op.)

```perl
# source
use 5.42.0;
my $s = "a";
my $t = "b";
$s .= $t;
say($s);
```

```behavior
stdout: ab\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%va   = Constant("a") :Str
%vb   = Constant("b") :Str
%cat  = Concat(%va, %vb) :Str
%nl = Constant("\n") :Str
%p  = Print(%cat, %nl)
return %p
control: %start -> %p
L: GREEN
```

## S7 string interpolation (qq{$a$b})

Interpolation `qq{$a$b}` compiles to a fresh (non-APPEND) `multiconcat` that
builds a new Str from the two dynamic operands with empty segments between them.
The decoder folds `$a . $b` into a Concat and binds it to the new lexical `$c`.

```perl
# source
use 5.42.0;
my $a = "x";
my $b = "y";
my $c = "$a$b";
say($c);
```

```behavior
stdout: xy\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%va   = Constant("x") :Str
%vb   = Constant("y") :Str
%cat  = Concat(%va, %vb) :Str
%nl = Constant("\n") :Str
%p  = Print(%cat, %nl)
return %p
control: %start -> %p
L: GREEN
```

## S8 interpolation with constant text segments

Interpolation whose format has constant text between the operands
(`qq{p-$a-m-$b-q}`) — the multiconcat aux_list slices the flat segment string
`"p--m--q"` by the per-segment lengths and the decoder interleaves them with the
operands: `"p-" . $a . "-m-" . $b . "-q"`, a left-folded Concat chain.

```perl
# source
use 5.42.0;
my $a = "x";
my $b = "y";
my $c = "p-$a-m-$b-q";
say($c);
```

```behavior
stdout: p-x-m-y-q\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%p    = Constant("p-") :Str
%va   = Constant("x") :Str
%c1   = Concat(%p, %va) :Str
%m    = Constant("-m-") :Str
%c2   = Concat(%c1, %m) :Str
%vb   = Constant("y") :Str
%c3   = Concat(%c2, %vb) :Str
%q    = Constant("-q") :Str
%c4   = Concat(%c3, %q) :Str
%nl = Constant("\n") :Str
%p  = Print(%c4, %nl)
return %p
control: %start -> %p
L: GREEN
```

## S9 interpolation of an integer (Int->Str coercion)

In Chalk `"ok $n"` is COERCION, not interpolation: the non-Str operand `$n` is
stringified before the Concat. The multiconcat decoder wraps a non-Str operand
(here the folded Int Constant `3`) in a `Stringify` (Int->Str), so the Concat
sees only Str inputs. The Stringify lowers to an int-to-decimal loop that renders
the digits and records the RUNTIME digit-count length in `_str_len_table`, so the
Concat can slice exactly `len` bytes. The result is `Str:ok 3`.

```perl
# source
use 5.42.0;
my $n = 3;
say("ok $n");
```

```behavior
stdout: ok 3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0  = Constant("ok ") :Str
%n   = Constant(3) :Int
%sf  = Coerce(%n, from_repr: "Int", to_repr: "Str") :Str
%cat = Concat(%s0, %sf) :Str
%nl = Constant("\n") :Str
%p  = Print(%cat, %nl)
return %p
control: %start -> %p
L: GREEN
```

## S10 interpolation of a negative integer (sign in the digit-count length)

The digit-count length the Stringify records must include the sign: `-5` is two
bytes, not one. The int-to-decimal loop renders the magnitude then prepends `-`,
and the recorded length spans the `-`. Surrounding literal text (`val `) forces a
genuine Str (a lone `"$n"` degenerates to the number itself in perl, which the
oracle tags Int); the result is `Str:val -5`.

```perl
# source
use 5.42.0;
my $n = -5;
say("val $n");
```

```behavior
stdout: val -5\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0  = Constant("val ") :Str
%n   = Constant(-5) :Int
%sf  = Coerce(%n, from_repr: "Int", to_repr: "Str") :Str
%cat = Concat(%s0, %sf) :Str
%nl = Constant("\n") :Str
%p  = Print(%cat, %nl)
return %p
control: %start -> %p
L: GREEN
```

## S11 interpolation of zero (do-while emits one '0')

Zero has no nonzero quotient, so a plain divide-until-zero loop would emit no
digit. The renderer is a do-while: it always writes one digit, so `0` renders as
the single byte `0` (length 1). Surrounding literal text (`val `) forces a genuine
Str (a lone `"$n"` degenerates to the number in perl, tagged Int); the result is
`Str:val 0`.

```perl
# source
use 5.42.0;
my $n = 0;
say("val $n");
```

```behavior
stdout: val 0\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0  = Constant("val ") :Str
%n   = Constant(0) :Int
%sf  = Coerce(%n, from_repr: "Int", to_repr: "Str") :Str
%cat = Concat(%s0, %sf) :Str
%nl = Constant("\n") :Str
%p  = Print(%cat, %nl)
return %p
control: %start -> %p
L: GREEN
```

## S12 print an interpolated integer to stdout

`print "ok $n\n"` combines I2's Print statement effect with the Int->Str coerce:
the interpolation builds `Concat("ok ", Stringify($n), "\n")`, print emits it to
stdout via `printf("%.*s", len, ptr)` using the Concat's tracked runtime length,
and the block yields the trailing `Int:1`. The stdout is `ok 3\n`.

```perl
# source
use 5.42.0;
my $n = 3;
print "ok $n\n"; say(1);
```

```behavior
stdout: ok 3\n1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0  = Constant("ok ") :Str
%n   = Constant(3) :Int
%sf  = Coerce(%n, from_repr: "Int", to_repr: "Str") :Str
%c1  = Concat(%s0, %sf) :Str
%nl  = Constant("\n") :Str
%cat = Concat(%c1, %nl) :Str
%p   = Print(%cat) :Bool
%one = Constant(1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%one : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
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
