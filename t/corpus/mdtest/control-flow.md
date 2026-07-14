# Control Flow

Control-flow idioms: ternary select, if/else, while, foreach, postfix modifiers,
nested conditionals, and try/catch.

D6 (ternary / select) is the only idiom in this topic that is runtime-free
lowerable — it maps to an LLVM `select i1` instruction with no basic-block splits.
All other idioms require LLVM basic blocks, `br`, and either `phi` (D1-D5, D7) or
`landingpad` (D8) — none of which are in the current literal-arithmetic lowering
slice.

## D6 ternary (n>0 ? 1 : 2)

The ternary `$n > 0 ? 1 : 2` compiles to a NumGt comparison (producing a Bool/i1)
fed into a TernaryExpr (LLVM `select i1`). No branches, no phi — the only
runtime-free control-flow idiom in this topic.

The named-SSA builder uses the 3-input form `TernaryExpr(%cond, %then, %else)`
to build the graph: `%cmp` is the NumGt (Bool repr), `%c1`/`%c2` are the Int
branch constants, and `%tern` is the TernaryExpr (Int repr). The LLVM backend
lowers this to `select i1 %cmp, i64 1, i64 2`.

```perl
# source
my $n = 5;
my $x = $n > 0 ? 1 : 2;
$x
```

```behavior
return: 1
context: scalar
```

```ir
%n    = Constant(5) :Int
%zero = Constant(0) :Int
%cmp  = NumGt(%n, %zero) :Bool
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%tern = TernaryExpr(%cmp, %c1, %c2) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %tern) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
L: GREEN
```

## D1 if/else

An if/else block requires two LLVM basic blocks (then/else branches) joined by a
phi node at the merge point. This structural pattern is not in the current
literal-arithmetic lowering slice.

```perl
# source
my $n = 5;
my $x;
if ($n > 0) { $x = 1 } else { $x = 2 }
$x
```

```behavior
return: 1
context: scalar
```

```ir
%n     = Constant(5) :Int
%zero  = Constant(0) :Int
%cmp   = NumGt(%n, %zero) :Bool
%xn    = Constant("$x") :Str
%vx    = VarDecl(%xn) :Int
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%lhs1  = PadAccess(%vx, "$x") :Int
%as1   = Assign(%lhs1, %c1) :Int
%lhs2  = PadAccess(%vx, "$x") :Int
%as2   = Assign(%lhs2, %c2) :Int
%if    = If(%vx, %cmp)
%proj0 = Proj(%if, index: 0)
%proj1 = Proj(%if, index: 1)
%region = Region(%proj0, %proj1)
%rx    = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %if
branch_control: %proj0 -> %as1
branch_control: %proj1 -> %as2
L: GREEN
```

## D2 while loop

A while loop requires a back-edge in the control-flow graph: a header block with
a conditional branch, a body block, and a phi node for variables that change on
each iteration. None of these are in the current lowering slice.

```perl
# source
my $n = 3;
my $s = 0;
while ($n > 0) { $s += $n; $n-- }
$s
```

```behavior
return: 6
context: scalar
```

```ir
%c3    = Constant(3) :Int
%c0a   = Constant(0) :Int
%c0b   = Constant(0) :Int
%one   = Constant(1) :Int
%nn    = Constant("$n") :Str
%sn    = Constant("$s") :Str
%vn    = VarDecl(%nn, %c3) :Int
%vs    = VarDecl(%sn, %c0a) :Int
%rn0   = PadAccess(%vn, "$n") :Int
%rs0   = PadAccess(%vs, "$s") :Int
%loop  = Loop(%vs)
%n_phi = Phi(%rn0, region: %loop) :Int
%s_phi = Phi(%rs0, region: %loop) :Int
%cmp   = NumGt(%n_phi, %c0b) :Bool
%s_new = Add(%s_phi, %n_phi) :Int
%n_new = Subtract(%n_phi, %one) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
control: %vn -> %vs -> %loop
loop_backedge: %n_phi -> %n_new
loop_backedge: %s_phi -> %s_new
branch_control: %lp0 -> %n_new
branch_control: %lp0 -> %s_new
L: GREEN
```

## D2b while loop with a body decoy comparison

The loop body contains its own comparison on the loop-carried variable (`$n >
-5`). A first-icmp-consumer-of-a-header-Phi heuristic could pick that decoy as
the loop condition and iterate one extra time (silent miscompile, RC2b C4). The
producer wires the header condition's control edge to the Loop
(`branch_control: %loop -> %cmp`), so the backend recovers it structurally
(`_lower_loop_condition` strategy 1) regardless of body comparisons.

```perl
# source
my $n = 3;
my $s = 0;
while ($n > 0) { my $c = $n > -5; $s += $n; $n-- }
$s
```

```behavior
return: 6
context: scalar
```

```ir
%c3    = Constant(3) :Int
%c0a   = Constant(0) :Int
%c0b   = Constant(0) :Int
%one   = Constant(1) :Int
%nn    = Constant("$n") :Str
%sn    = Constant("$s") :Str
%vn    = VarDecl(%nn, %c3) :Int
%vs    = VarDecl(%sn, %c0a) :Int
%rn0   = PadAccess(%vn, "$n") :Int
%rs0   = PadAccess(%vs, "$s") :Int
%loop  = Loop(%vs)
%n_phi = Phi(%rn0, region: %loop) :Int
%s_phi = Phi(%rs0, region: %loop) :Int
%cmp   = NumGt(%n_phi, %c0b) :Bool
%s_new = Add(%s_phi, %n_phi) :Int
%n_new = Subtract(%n_phi, %one) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
control: %vn -> %vs -> %loop
loop_backedge: %n_phi -> %n_new
loop_backedge: %s_phi -> %s_new
branch_control: %loop -> %cmp
branch_control: %lp0 -> %n_new
branch_control: %lp0 -> %s_new
L: GREEN
```

## D2c while loop with a bare-truthiness header

A bare-scalar header (`while ($n)`) has no comparison -- the condition is the
loop-carried value's truthiness. The producer synthesizes an explicit
`NumNe($n, 0)` truthiness test and wires ITS control edge to the Loop, so the
backend still recovers an icmp condition structurally. Without this, the header
node is a Phi (not an icmp), the backend's strategy 1 skips it, and any body
comparison on the loop-carried value is picked as the exit test (silent
miscompile, e.g. `while ($n){ my $c=$n>2; ... }` returned 2 not 4).

```perl
# source
my $n = 3;
my $s = 0;
while ($n) { $s += $n; $n-- }
$s
```

```behavior
return: 6
context: scalar
```

```ir
%c3    = Constant(3) :Int
%c0a   = Constant(0) :Int
%zero  = Constant(0) :Int
%one   = Constant(1) :Int
%nn    = Constant("$n") :Str
%sn    = Constant("$s") :Str
%vn    = VarDecl(%nn, %c3) :Int
%vs    = VarDecl(%sn, %c0a) :Int
%rn0   = PadAccess(%vn, "$n") :Int
%rs0   = PadAccess(%vs, "$s") :Int
%loop  = Loop(%vs)
%n_phi = Phi(%rn0, region: %loop) :Int
%s_phi = Phi(%rs0, region: %loop) :Int
%cmp   = NumNe(%n_phi, %zero) :Bool
%s_new = Add(%s_phi, %n_phi) :Int
%n_new = Subtract(%n_phi, %one) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
control: %vn -> %vs -> %loop
loop_backedge: %n_phi -> %n_new
loop_backedge: %s_phi -> %s_new
branch_control: %loop -> %cmp
branch_control: %lp0 -> %n_new
branch_control: %lp0 -> %s_new
L: GREEN
```

## D3 foreach loop

A foreach over a range desugars to a counted loop: an induction variable, a
back-edge, and a phi node. Like while, this requires basic-block structure beyond
the current straight-line arithmetic slice.

```perl
# source
my $s = 0;
foreach my $i (1..3) { $s += $i }
$s
```

```behavior
return: 6
context: scalar
```

```ir
%c0    = Constant(0) :Int
%c1    = Constant(1) :Int
%c4    = Constant(4) :Int
%sn    = Constant("$s") :Str
%vs    = VarDecl(%sn, %c0) :Int
%rs0   = PadAccess(%vs, "$s") :Int
%loop  = Loop(%vs)
%i_phi = Phi(%c1, region: %loop) :Int
%s_phi = Phi(%rs0, region: %loop) :Int
%cmp   = NumGt(%c4, %i_phi) :Bool
%s_new = Add(%s_phi, %i_phi) :Int
%i_new = Add(%i_phi, %c1) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
control: %vs -> %loop
loop_backedge: %i_phi -> %i_new
loop_backedge: %s_phi -> %s_new
branch_control: %lp0 -> %s_new
branch_control: %lp0 -> %i_new
L: GREEN
```

## D3a foreach over a range with a runtime high bound

`for my $i (0..$n)` with a runtime `$n` desugars to the same counted loop as the
constant range (D3), but the continuation bound is computed at run time:
NumGt(Add($n, 1), i_phi) instead of a folded constant. This is the #1 Phase-5
lib/ blocker -- 28 real methods use `for (0..$#x)` / `for (0..$n)`. A runtime LOW
bound (`for my $i ($lo..$hi)`) still GAPs (loop-carried-stamp fixpoint). zhi
019f5da9.

```perl
# source
my $n = 3;
my $s = 0;
for my $i (0..$n) { $s += $i }
$s
```

```behavior
return: 6
context: scalar
```

```ir
%c0    = Constant(0) :Int
%c1    = Constant(1) :Int
%cn    = Constant(3) :Int
%bound = Add(%cn, %c1) :Int
%loop  = Loop(%c0)
%i_phi = Phi(%c0, region: %loop) :Int
%s_phi = Phi(%c0, region: %loop) :Int
%cmp   = NumGt(%bound, %i_phi) :Bool
%s_new = Add(%s_phi, %i_phi) :Int
%i_new = Add(%i_phi, %c1) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
loop_backedge: %i_phi -> %i_new
loop_backedge: %s_phi -> %s_new
L: GREEN
```

## D3a2 array last-index $#a is length minus one

`$#a` is the array's LAST INDEX (length - 1), not its length: for a 3-element
array `$#a` is 2. The producer once modelled av2arylen as Length (a silent
off-by-one that made `for my $i (0..$#a)` run one extra iteration); it now emits
Subtract(Length, 1). zhi 019f5da9.

```perl
# source
my @a = (10, 20, 30);
$#a
```

```behavior
return: 2
context: scalar
```

```ir
%c10   = Constant(10) :Int
%c20   = Constant(20) :Int
%c30   = Constant(30) :Int
%arr   = ArrayRef(%c10, %c20, %c30) :ArrayRef
%len   = Length(%arr) :Int
%c1    = Constant(1) :Int
%last  = Subtract(%len, %c1) :Int
return %last
L: GREEN
```

## D3b foreach over a lexical array

A foreach over an ARRAY (not a range) iterates each element in turn. `for` and
`foreach` are aliases -- the same `enteriter` optree -- and both spellings lower
identically. With @a = (10, 20, 30) the loop sums to 60. Unlike the range form
(D3, counted 1..N with synthesized bounds), an array foreach iterates the array's
own elements: the loop is bounded by the array length and the induction variable
reads element[i] each pass. This is the iteration primitive real lib/ methods use
(`for my $input ($self->inputs->@*) { ... }`).

```perl
# source
my @a = (10, 20, 30);
my $s = 0;
for my $x (@a) { $s += $x }
$s
```

```behavior
return: 60
context: scalar
```

```ir
%c10   = Constant(10) :Int
%c20   = Constant(20) :Int
%c30   = Constant(30) :Int
%arr   = ArrayRef(%c10, %c20, %c30) :ArrayRef
%len   = Length(%arr) :Int
%c0    = Constant(0) :Int
%c1    = Constant(1) :Int
%loop  = Loop(%c0)
%i_phi = Phi(%c0, region: %loop) :Int
%s_phi = Phi(%c0, region: %loop) :Int
%cmp   = NumGt(%len, %i_phi) :Bool
%elem  = Subscript(%arr, %i_phi) :Int
%s_new = Add(%s_phi, %elem) :Int
%i_new = Add(%i_phi, %c1) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
loop_backedge: %i_phi -> %i_new
loop_backedge: %s_phi -> %s_new
L: GREEN
```

## D3c array is intact after a foreach reads it

A foreach reads @a but does not mutate it, so `scalar @a` after the loop is
still 3. The loop's element reads (Subscript over the array) must not be treated
as an array mutation. An earlier over-conservative heuristic
(`_is_arith_over_element`) flagged the accumulator `Add($s, arr[i])` as a
possible element read-modify-write (`$a[i] += x`) and spuriously GAPped the read
whenever the accumulator's value was dead (here the sub returns `scalar @a`, not
$s). The heuristic now also requires the arith result to feed an element STORE
before treating it as an RMW, so a scalar accumulator over array elements lowers.
zhi 019f5da9.

```perl
# source
my @a = (2, 4, 6);
my $s = 0;
for my $x (@a) { $s += $x }
scalar @a
```

```behavior
return: 3
context: scalar
```

```ir
%c2    = Constant(2) :Int
%c4    = Constant(4) :Int
%c6    = Constant(6) :Int
%arr   = ArrayRef(%c2, %c4, %c6) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GREEN
```

## D3d foreach body that writes the iterator GAPs (aliasing)

In Perl `for my $x (@a)` ALIASES $x to each element, so a body write `$x = ...`
mutates @a in place: `for my $x (@a) { $x = $x + 1 } $a[0]` returns 11, not 10.
This lowering binds $x to a READ-ONLY element copy (Subscript(arr, i)), so a
write to $x would not propagate back to @a -- a silent miscompile. The producer
GAPs a foreach body that assigns its iterator loudly instead. Flip to `L: GREEN`
when the aliasing write-back is modeled. zhi 019f5da9.

```perl
# source
my @a = (10, 20);
for my $x (@a) { $x = $x + 1 }
$a[0]
```

```behavior
return: 11
context: scalar
```

```ir
%c10   = Constant(10) :Int
%c11   = Constant(11) :Int
return %c11
L: GAP(foreach body writes the iterator: aliasing write-back to the array not modeled)
```

## D4 postfix if

A postfix `EXPR if COND` is syntactic sugar for a single-branch conditional: the
expression runs only when the condition is true. Lowering requires a conditional
branch and a merge block with a phi for the variable being written.

```perl
# source
my $n = 5;
my $x = 0;
$x = 1 if $n > 0;
$x
```

```behavior
return: 1
context: scalar
```

```ir
%n     = Constant(5) :Int
%zero  = Constant(0) :Int
%c0    = Constant(0) :Int
%c1    = Constant(1) :Int
%xn    = Constant("$x") :Str
%vx    = VarDecl(%xn, %c0) :Int
%cmp   = NumGt(%n, %zero) :Bool
%lhs   = PadAccess(%vx, "$x") :Int
%as    = Assign(%lhs, %c1) :Int
%if    = If(%vx, %cmp)
%proj0 = Proj(%if, index: 0)
%proj1 = Proj(%if, index: 1)
%region = Region(%proj0, %proj1)
%rx    = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %if
branch_control: %proj0 -> %as
L: GREEN
```

## D5 postfix while

A postfix `EXPR while COND` is a pre-test statement-modifier while loop: the
condition is checked first, and the body executes only when it is true. Requires
a loop header block, a conditional branch, and phi nodes for induction variables.
Note: `$s += $n-- while $n > 0` with `$n=0` gives `$s=0` (body runs zero times),
confirming the pre-test semantics. A true do-while is only `do{...}while(COND)`.

```perl
# source
my $n = 3;
my $s = 0;
$s += $n-- while $n > 0;
$s
```

```behavior
return: 6
context: scalar
```

```ir
%c3    = Constant(3) :Int
%c0a   = Constant(0) :Int
%c0b   = Constant(0) :Int
%one   = Constant(1) :Int
%nn    = Constant("$n") :Str
%sn    = Constant("$s") :Str
%vn    = VarDecl(%nn, %c3) :Int
%vs    = VarDecl(%sn, %c0a) :Int
%rn0   = PadAccess(%vn, "$n") :Int
%rs0   = PadAccess(%vs, "$s") :Int
%loop  = Loop(%vs)
%n_phi = Phi(%rn0, region: %loop) :Int
%s_phi = Phi(%rs0, region: %loop) :Int
%cmp   = NumGt(%n_phi, %c0b) :Bool
%s_new = Add(%s_phi, %n_phi) :Int
%n_new = Subtract(%n_phi, %one) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
control: %vn -> %vs -> %loop
loop_backedge: %n_phi -> %n_new
loop_backedge: %s_phi -> %s_new
branch_control: %lp0 -> %n_new
branch_control: %lp0 -> %s_new
L: GREEN
```

## D7 nested if

Nested conditionals produce a tree of basic blocks: each if/else level adds
a conditional branch pair and a join phi. The depth of nesting multiplies the
number of blocks required.

```perl
# source
my $n = 5;
my $x;
if ($n > 0) { if ($n > 3) { $x = 3 } else { $x = 1 } } else { $x = 0 }
$x
```

```behavior
return: 3
context: scalar
```

```ir
%n        = Constant(5) :Int
%zero     = Constant(0) :Int
%three    = Constant(3) :Int
%c3val    = Constant(3) :Int
%c1val    = Constant(1) :Int
%c0val    = Constant(0) :Int
%xn       = Constant("$x") :Str
%vx       = VarDecl(%xn) :Int
%cmp_out  = NumGt(%n, %zero) :Bool
%cmp_in   = NumGt(%n, %three) :Bool
%lhs3     = PadAccess(%vx, "$x") :Int
%as3      = Assign(%lhs3, %c3val) :Int
%lhs1     = PadAccess(%vx, "$x") :Int
%as1      = Assign(%lhs1, %c1val) :Int
%lhs0     = PadAccess(%vx, "$x") :Int
%as0      = Assign(%lhs0, %c0val) :Int
%inner_if    = If(%vx, %cmp_in)
%inner_p0    = Proj(%inner_if, index: 0)
%inner_p1    = Proj(%inner_if, index: 1)
%inner_reg   = Region(%inner_p0, %inner_p1)
%outer_if    = If(%vx, %cmp_out)
%outer_p0    = Proj(%outer_if, index: 0)
%outer_p1    = Proj(%outer_if, index: 1)
%outer_reg   = Region(%outer_p0, %outer_p1)
%rx          = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %outer_if
branch_control: %outer_p0 -> %inner_if
branch_control: %inner_p0 -> %as3
branch_control: %inner_p1 -> %as1
branch_control: %outer_p1 -> %as0
L: GREEN
```

## D9 nested if runtime-false inner condition

Nested conditionals with a runtime-FALSE inner condition expose the phi-arm
miscompile (B1): the outer merge phi must arm with the INNER MERGE PHI result
(the value live at the exit of the outer-then branch), not the raw inner-then
assignment value. With n=2, the outer condition (2>0) is true, but the inner
condition (2>3) is false, so x=1 via the inner-else path. lli must agree with perl.

This case differs from D7 (which uses n=5, making the inner condition statically
true and letting lli constant-fold the wrong phi arm away).

```perl
# source
my $n = 2;
my $x = 0;
if ($n > 0) { if ($n > 3) { $x = 3 } else { $x = 1 } } else { $x = 0 }
$x
```

```behavior
return: 1
context: scalar
```

```ir
%cn   = Constant(2) :Int
%zero = Constant(0) :Int
%c0   = Constant(0) :Int
%c1   = Constant(1) :Int
%c3   = Constant(3) :Int
%c3v  = Constant(3) :Int
%nn   = Constant("$n") :Str
%vn   = VarDecl(%nn, %cn) :Int
%rn   = PadAccess(%vn, "$n") :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %c0) :Int
%cmp_out = NumGt(%rn, %zero) :Bool
%cmp_in  = NumGt(%rn, %c3) :Bool
%lhs3 = PadAccess(%vx, "$x") :Int
%as3  = Assign(%lhs3, %c3v) :Int
%lhs1 = PadAccess(%vx, "$x") :Int
%as1  = Assign(%lhs1, %c1) :Int
%lhs0 = PadAccess(%vx, "$x") :Int
%as0  = Assign(%lhs0, %c0) :Int
%inner_if  = If(%vx, %cmp_in)
%inner_p0  = Proj(%inner_if, index: 0)
%inner_p1  = Proj(%inner_if, index: 1)
%inner_reg = Region(%inner_p0, %inner_p1)
%outer_if  = If(%vx, %cmp_out)
%outer_p0  = Proj(%outer_if, index: 0)
%outer_p1  = Proj(%outer_if, index: 1)
%outer_reg = Region(%outer_p0, %outer_p1)
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vn -> %vx -> %outer_if
branch_control: %outer_p0 -> %inner_if
branch_control: %inner_p0 -> %as3
branch_control: %inner_p1 -> %as1
branch_control: %outer_p1 -> %as0
L: GREEN
```

## D8 try/catch

Exception handling requires an LLVM `landingpad` instruction, a personality
function, and an unwind edge from the try block to the catch block. This goes
beyond the integer-arithmetic lowering slice and requires C++ exception-handling
ABI integration.

```perl
# source
my $x = 0;
try { $x = 1 } catch ($e) { $x = 2 }
$x
```

```behavior
return: 1
context: scalar
```

```ir
L: GAP(needs LLVM landingpad + personality function for exception unwind)
```

## D10 do-block value

A `do { ... }` block evaluates its statements and yields the value of its last
expression (`my $x = do { my $t = 5; $t + 1 }` binds $x to 6). B::SoN walks the
do-block's enter/leave scope and the SSA construction folds the intermediate
`my $t = 5` binding into the final expression, so the graph is just the value
computation. (The M20 "Do IR node + DoBlock grammar" was the pre-B::SoN Chalk
grammar plan; the B::SoN optree walker supersedes it — do-blocks lower directly.)

```perl
# source
my $x = do { my $t = 5; $t + 1 };
$x
```

```behavior
return: 6
context: scalar
```

```ir
%five = Constant(5) :Int
%one  = Constant(1) :Int
%sum  = Add(%five, %one) :Int
return %sum
L: GREEN
```
