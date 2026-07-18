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
