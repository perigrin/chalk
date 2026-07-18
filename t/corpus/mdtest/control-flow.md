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

## D1a void print in a true if arm

An if/else whose ARMS only `print` (no assignment, no value) is a void
statement-effect branch: each arm's `print` fires on its own control path and
nothing is merged into a value. The producer once collapsed such a branch to the
pad-rebind merge path — which merges nothing (a void print rebinds no pad slot),
leaving both Print nodes unpinned so NEITHER fired (a silent effect drop). The
fix routes the branch through the same real control flow an element/field-store
arm uses: an `If` with `Proj(true, 0)` / `Proj(false, 1)`, each arm walked on its
Proj so the `print` is control-dependent on it, and a `Region` merging the arms.
For `$c = 1` the TRUE arm is taken, so stdout is `a\n`; the block's trailing `1`
returns `Int:1`.

```perl
# source
my $c = 1; if ($c) { print "a\n" } else { print "b\n" } 1
```

```behavior
stdout: a\n
return: Int:1
context: scalar
```

```ir
%sa = Constant("a\n") :Str
%pa = Print(%sa) :Bool
%sb = Constant("b\n") :Str
%pb = Print(%sb) :Bool
%c  = Constant(1) :Int
return %c
L: GREEN
```

## D1b void print in a false if arm (else arm fires)

Bilateral to D1a: with `$c = 0` the FALSE (else) arm is taken, so its `print`
fires and stdout is `b\n`; the block's trailing `1` returns `Int:1`. The TRUE
arm's `print` is control-dependent on `Proj(true, 0)` and so emits nothing when
the guard is false — the two Print nodes are each pinned to their own arm's Proj,
proving the merge is genuine control flow and not a straight-line both-arms walk.

```perl
# source
my $c = 0; if ($c) { print "a\n" } else { print "b\n" } 1
```

```behavior
stdout: b\n
return: Int:1
context: scalar
```

```ir
%sa = Constant("a\n") :Str
%pa = Print(%sa) :Bool
%sb = Constant("b\n") :Str
%pb = Print(%sb) :Bool
%c  = Constant(1) :Int
return %c
L: GREEN
```

## D3f void print inside a loop body

A `print` as the sole statement of a `foreach` body is a per-iteration void
statement effect: it fires once per pass, control-pinned inside the loop, and the
loop's trailing `1` returns `Int:1`. For `1..2` the body runs twice, so stdout is
`x\nx\n`. (Unlike the if/else block, the loop body's control chain already
threads a void print — this case is a bilateral acceptance guard that the
loop-body effect path stays green alongside the if/else fix.)

```perl
# source
for my $i (1..2) { print "x\n" } 1
```

```behavior
stdout: x\nx\n
return: Int:1
context: scalar
```

```ir
%sx = Constant("x\n") :Str
%px = Print(%sx) :Bool
%c  = Constant(1) :Int
return %c
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

## D2d while loop whose CONDITION mutates a slot

Perl evaluates a `while` condition N+1 times: the final, FAILING evaluation still
applies its side effects. `while ($i-- > 0)` decrements `$i` on the failing pass
too, so the post-loop `$i` is `-1`, not the header Phi's exit value `0`. The
two-phase loop translation models the condition mutation as the header Phi's
back-edge (`Subtract($i_phi, 1)`); the post-loop read binds to that back-edge (the
value after the failing pass), NOT the Phi (its value on the pass that FAILED).
The backend lowers the condition-mutation back-edge in the loop header (where it
dominates the exit) so the post-loop use is well-formed. Was a producer GAP
("side-effecting loop condition not yet lowered"); now lowers to Int:-1.

```perl
# source
my $i = 3;
while ($i-- > 0) { }
$i
```

```behavior
return: -1
context: scalar
```

```ir
%c3    = Constant(3) :Int
%zero  = Constant(0) :Int
%one   = Constant(1) :Int
%in    = Constant("$i") :Str
%vi    = VarDecl(%in, %c3) :Int
%ri0   = PadAccess(%vi, "$i") :Int
%loop  = Loop(%vi)
%i_phi = Phi(%ri0, region: %loop) :Int
%cmp   = NumGt(%i_phi, %zero) :Bool
%i_new = Subtract(%i_phi, %one) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %i_new
control: %vi -> %loop
loop_backedge: %i_phi -> %i_new
branch_control: %loop -> %cmp
L: GREEN
```

## D2e postfix while whose CONDITION mutates a slot

The postfix form (`STMT while COND`) of a condition mutation. Perl runs the
`$n-- > 0` test N+1 times; the body `$t = $t + $n` accumulates only on the N
passing passes. `$n=3` gives passes with `$n` = 2, 1, 0 (the decremented values
the body reads), summing `$t` to `2+1+0 = 3`. The postfix path delegates to the
same two-phase loop translation at the `enter` scope op, so no pre-evaluation
leaks into the Phi inits (the `$n` Phi init stays 3). `$t` is body-mutated, so its
post-loop read takes its Phi; `$n` is condition-mutated (unused post-loop here).
Was a producer GAP; now lowers to Int:3.

```perl
# source
my $n = 3;
my $t = 0;
$t = $t + $n while $n-- > 0;
$t
```

```behavior
return: 3
context: scalar
```

```ir
%c3    = Constant(3) :Int
%c0    = Constant(0) :Int
%zero  = Constant(0) :Int
%one   = Constant(1) :Int
%nn    = Constant("$n") :Str
%tn    = Constant("$t") :Str
%vn    = VarDecl(%nn, %c3) :Int
%vt    = VarDecl(%tn, %c0) :Int
%rn0   = PadAccess(%vn, "$n") :Int
%rt0   = PadAccess(%vt, "$t") :Int
%loop  = Loop(%vt)
%n_phi = Phi(%rn0, region: %loop) :Int
%t_phi = Phi(%rt0, region: %loop) :Int
%cmp   = NumGt(%n_phi, %zero) :Bool
%t_new = Add(%t_phi, %n_phi) :Int
%n_new = Subtract(%n_phi, %one) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %t_phi
control: %vn -> %vt -> %loop
loop_backedge: %n_phi -> %n_new
loop_backedge: %t_phi -> %t_new
branch_control: %loop -> %cmp
branch_control: %lp0 -> %t_new
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

## D3e element-indexed loop accumulator

`for my $i (0..$#a) { $s += $a[$i] }` reads each element by its loop-carried
index and accumulates. This is the #2 real-lib loop pattern (after foreach-over-
array). Two bugs blocked it: (1) the body scout had no memory, so the element
read's Subscript had an undef memory input and crashed (masked by B::SoN as a
silent sub-drop); (2) the element read was unstamped, so the accumulator's
back-edge Add($s_phi, Subscript) was unstamped and the loop-carried-stamp check
refused it. Fixed by seeding the scout with a MemStart and stamping a
DYNAMIC-index rvalue element read with the container's element type (a LITERAL
index stays unstamped so the out-of-bounds -> Slot analysis still runs, ref R9).
zhi 019f5da9, 019f6198.

```perl
# source
my @a = (10, 20, 30);
my $s = 0;
for my $i (0..$#a) { $s += $a[$i] }
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
%c1    = Constant(1) :Int
%last  = Subtract(%len, %c1) :Int
%bound = Add(%last, %c1) :Int
%c0    = Constant(0) :Int
%loop  = Loop(%c0)
%i_phi = Phi(%c0, region: %loop) :Int
%s_phi = Phi(%c0, region: %loop) :Int
%cmp   = NumGt(%bound, %i_phi) :Bool
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

## T1 list-context ternary (t/base blocker: print $c ? "y" : "n")

The dominant t/base assertion idiom `print $cond ? "ok N\n" : "not ok N\n"` — a
ternary in LIST context as a print arg. Each arm produces exactly ONE value (a
single string), so the ternary lowers to a `TernaryExpr(%cond, %y, %n)` selecting
the printed string — the same select shape as a scalar-context ternary. A
list-context ternary whose arm produces a genuine multi-element list
(`$c ? (1,2) : (3,4)`) still GAPs.

```perl
# source
my $c = 1;
print $c ? "y\n" : "n\n";
1
```

```behavior
stdout: y
return: 1
context: scalar
```

```ir
%c    = Constant(1) :Int
%y    = Constant("y\n") :Str
%n    = Constant("n\n") :Str
%tern = TernaryExpr(%c, %y, %n) :Str
%p    = Print(%tern) :Bool
%one  = Constant(1) :Int
return %one
control: %p
L: GREEN
```

## T2 die inside a branch arm (t/base blocker: rs.t/term.t)

A `die` statement inside an if/else arm — the rs.t / term.t blocker. A `die` is a
runtime-free abort: the die arm becomes a control path that does NOT merge a value
(it aborts via `exit(255)` + `unreachable`), so the `Region` merging the arms sees
only the LIVE (non-die) arm. For `$c = 0` the `die` arm is NOT taken, so the `else`
arm's `1` is returned; the `die` arm's `Unwind` is control-dependent on
`Proj(true, 0)` and never fires. The producer routes the branch through the same
real control flow a void-print arm uses (`If` + `Proj` + `Region`), building the
`Unwind` on the die arm's `Proj`; the LLVM backend lowers `Unwind` to `exit(255)`
+ `unreachable`, so the merge's die predecessor is dead and the live value
dominates.

```perl
# source
my $c = 0;
if ($c) { die "boom\n" } else { 1 }
```

```behavior
return: 1
context: scalar
```

```ir
%boom = Constant("boom\n") :Str
%uw   = Unwind(%boom)
%one  = Constant(1) :Int
return %one
L: GREEN
```

## T2b die inside the TAKEN branch arm (bilateral abort proof)

Bilateral to T2: with `$c = 1` the `die` arm IS taken, so the program ABORTS
(`exit(255)` + `unreachable`) rather than returning the else arm's `42`. This is
the load-bearing correctness property of die-in-arm lowering: a TAKEN die must
abort, NEVER silently return the untaken arm's value. Verified out-of-band: the
lowered `.ll` reaches `if.then.1: call void @exit(i32 255); unreachable`, and
`lli` exits 255 with no stdout (it does NOT print `Int:42`).

This case is a corpus-declared GAP because the triple-contract harness compares
lli's stdout against the perl oracle for EQUALITY: a taken die makes both the
oracle (`die "boom\n"` kills the perl script) and lli (exit 255) abort, so there
is no equal value to assert — `run_through_bson` returns the `lli exited 255`
error, not a matchable result. The abort is proven by T2's not-taken GREEN
(the die arm's `Unwind` lowers) plus the out-of-band abort check above; asserting
a non-zero exit as a behavior match would require a distinct abort-oracle path
the harness does not model.

```perl
# source
my $c = 1;
if ($c) { die "boom\n" } else { 42 }
```

```behavior
return: 42
context: scalar
```

```ir
L: GAP(taken die aborts (lli exits 255); the equality harness cannot assert an abort against the perl die-oracle — proven out-of-band, see T2b prose)
```

## T3 cond_expr inside a loop body (t/base blocker: translate.t)

A ternary (cond_expr) used inside a while-loop body — the translate.t blocker.
The loop body walker dispatches a `cond_expr` to the shared `_handle_cond_expr`
(the same select construction the main walk uses) instead of GAPping, so the
body's `$i > 1 ? 10 : 1` lowers to a `TernaryExpr` feeding the `$s` accumulator's
back-edge Add. Sums `10 + 1 + 1 = 12` over the three passes ($i = 0, 1, 2).

```perl
# source
my $i = 0;
my $s = 0;
while ($i < 3) { $s += ($i > 1 ? 10 : 1); $i++ }
$s
```

```behavior
return: 12
context: scalar
```

```ir
%c0i   = Constant(0) :Int
%c0s   = Constant(0) :Int
%c3    = Constant(3) :Int
%c1    = Constant(1) :Int
%c10   = Constant(10) :Int
%one   = Constant(1) :Int
%in    = Constant("$i") :Str
%sn    = Constant("$s") :Str
%vi    = VarDecl(%in, %c0i) :Int
%vs    = VarDecl(%sn, %c0s) :Int
%ri0   = PadAccess(%vi, "$i") :Int
%rs0   = PadAccess(%vs, "$s") :Int
%loop  = Loop(%vs)
%i_phi = Phi(%ri0, region: %loop) :Int
%s_phi = Phi(%rs0, region: %loop) :Int
%cmp   = NumLt(%i_phi, %c3) :Bool
%gt    = NumGt(%i_phi, %c1) :Bool
%tern  = TernaryExpr(%gt, %c10, %one) :Int
%s_new = Add(%s_phi, %tern) :Int
%i_new = Add(%i_phi, %one) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
control: %vi -> %vs -> %loop
loop_backedge: %i_phi -> %i_new
loop_backedge: %s_phi -> %s_new
branch_control: %loop -> %cmp
L: GREEN
```

## T4 loop control (last) inside a loop body (t/base blocker: while.t)

A `last if COND` at the head of a headless `while (1)` body — the while.t
blocker. The `1` header folds away, so this conditional break IS the loop's
continuation, negated: the loop runs while NOT COND. The producer hoists the
`last`'s guard (`$i >= 3`, a NumGe) into the loop's continuation condition by
negating the comparison (NumLt over the same operands, wired to the Loop as its
control edge) and continues the body walk on the false (continue) arm. The result
is the ordinary single-exit Loop/Phi/Proj/Region shape the backend already
lowers — no new multi-exit loop model. Loop runs `$i` = 0,1,2 accumulating `$s` =
0+1+2 = 3, then the negated header `$i < 3` fails at `$i` = 3. Was a producer GAP
("loop control (last) inside a loop body not yet lowered"); now lowers to Int:3.

```perl
# source
my $i = 0;
my $s = 0;
while (1) { last if $i >= 3; $s += $i; $i++ }
$s
```

```behavior
return: 3
context: scalar
```

```ir
%start = Start()
%c0    = Constant(0) :Int
%c1    = Constant(1) :Int
%c3    = Constant(3) :Int
%loop  = Loop(%start)
%s_phi = Phi(%c0, region: %loop) :Int
%i_phi = Phi(%c0, region: %loop) :Int
%cmp   = NumLt(%i_phi, %c3) :Bool
%s_new = Add(%s_phi, %i_phi) :Int
%i_new = Add(%i_phi, %c1) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
control: %start -> %loop
loop_backedge: %i_phi -> %i_new
loop_backedge: %s_phi -> %s_new
branch_control: %loop -> %cmp
L: GREEN
```

## T4b last with an equality guard (bilateral: negation over NumEq, distinct count)

Bilateral against T4: the `last if` guard is an EQUALITY (`$i == 4`, a NumEq),
so the negated continuation is a NumNe over the SAME operands — proving the
producer's comparison-negation table covers more than the NumGe/NumLt pair. The
distinct exit value (4, not 3) makes the iteration count itself the check: the
loop runs `$i` = 0,1,2,3 (four passes) accumulating `$s` = 0+1+2+3 = 6, then the
negated header `$i != 4` fails at `$i` = 4. A wrong negation (or an off-by-one in
where the exit fires) would give a different sum, so the value pins that the
`last` takes effect at the correct control point — before the fifth `$s += $i`.

```perl
# source
my $i = 0;
my $s = 0;
while (1) { last if $i == 4; $s += $i; $i++ }
$s
```

```behavior
return: 6
context: scalar
```

```ir
%start = Start()
%c0    = Constant(0) :Int
%c1    = Constant(1) :Int
%c4    = Constant(4) :Int
%loop  = Loop(%start)
%s_phi = Phi(%c0, region: %loop) :Int
%i_phi = Phi(%c0, region: %loop) :Int
%cmp   = NumNe(%i_phi, %c4) :Bool
%s_new = Add(%s_phi, %i_phi) :Int
%i_new = Add(%i_phi, %c1) :Int
%lp0   = Proj(%loop, index: 0)
%lp1   = Proj(%loop, index: 1)
%lreg  = Region(%lp1)
return %s_phi
control: %start -> %loop
loop_backedge: %i_phi -> %i_new
loop_backedge: %s_phi -> %s_new
branch_control: %loop -> %cmp
L: GREEN
```

## T4c last not at the head of a loop body (loud GAP: bottom/mid-loop exit)

A `last if COND` that is NOT the first body statement (`BODY; last if C`) is a
bottom/mid-loop exit, not a header continuation. Hoisting its check to the loop
top would reorder the exit test ahead of the statements that ran before it in
source order — a miscompile. The producer refuses loudly instead. Flip to GREEN
only when a genuine multi-exit loop model (a mid-body break edge to the loop
exit, distinct from the header continuation) is built.

```perl
# source
my $i = 0;
my $s = 0;
while (1) { $s += 10; last if $i >= 2; $i++ }
$s
```

```behavior
return: 30
context: scalar
```

```ir
L: GAP(last not at the head of a loop body not yet lowered)
```

## T5 direct no-arg named-sub call (t/ near-miss — simple form GREEN)

A direct call to a named sub with no args. The SIMPLE form already lowers (the
callee is resolved and inlined). The t/ files hit the HARDER variant — a call to
`main::is` (Test::More) with no resolvable callee graph, or an arg-passing call —
which still GAPs. This case locks the working simple form.

```perl
# source
sub helper { 42 }
my $x = helper();
$x
```

```behavior
return: 42
context: scalar
```

```ir
%call   = Call(dispatch_kind: "direct", name: "main::helper") :Int
return %call
L: GREEN
```

## T6 mid-body last (t/ blocker: last NOT at the head of a loop body)

Round 1 (T4) handled a HEAD-of-body `last if` (hoistable as a negated loop header).
A `last` deeper in the body (`BODY; last if C`) is a bottom/mid-loop exit — hoisting
its check to the header would reorder it ahead of earlier body statements. Currently
a loud GAP; flip to GREEN when mid-body loop-exit control-flow lands.

```perl
# source
my $i = 0;
my $s = 0;
while ($i < 5) { $i++; last if $i == 3; $s += $i }
$s
```

```behavior
return: 3
context: scalar
```

```ir
L: GAP(last not at the head of a loop body not yet lowered — mid/bottom-loop exit)
```

## T7 next inside a loop body (t/ blocker: loop control next)

`next` continues to the next iteration (a control edge to the loop header/continue
block). Round 1 handled `last` at the head; `next` is unhandled. Flip to GREEN when
`next` (continue-edge) lowering lands.

```perl
# source
my $s = 0;
for my $i (1..3) { next if $i == 2; $s += $i }
$s
```

```behavior
return: 4
context: scalar
```

```ir
L: GAP(loop control (next) inside a loop body not yet lowered)
```

## T8 value-context ternary with a branch-guarded element store (t/ blocker)

A ternary in value context whose result is stored into an array element
(`$a[0] = $c ? 9 : 8`). The store is branch-guarded by the ternary select. Currently
a loud GAP; flip to GREEN when value-context-ternary-into-element-store lowers.

```perl
# source
my @a = (1, 2, 3);
my $c = 1;
$a[0] = $c ? 9 : 8;
$a[0]
```

```behavior
return: 9
context: scalar
```

```ir
L: GAP(value-context ternary with a branch-guarded element store not yet lowered)
```

## T9 statement-modifier inside an if/else arm (t/ blocker: untranslatable arm op)

An if/else whose TRUE arm contains a statement modifier (`$x = 5 if $x < 10`). The
modifier compiles to a void-context `and(COND, STORE)` — the arm walk hit that `and`
op and stopped BEFORE the join (an "untranslatable op inside an arm" GAP). The fix
recurses into the same void-context `and`/`or` pad-rebind merge the main walk uses:
the modifier's guarded store becomes `TernaryExpr(COND, stored, prior)` for the
rebound slot, so the arm reaches the join and its value merges into the outer
if/else. With `$c = 1` the true arm runs and `$x < 10` holds, so `$x = 5`.

```perl
# source
my $c = 1;
my $x = 0;
if ($c) { $x = 5 if $x < 10 } else { $x = 1 }
$x
```

```behavior
return: 5
context: scalar
```

```ir
%c1    = Constant(1) :Int
%x0    = Constant(0) :Int
%c10   = Constant(10) :Int
%lt    = NumLt(%x0, %c10) :Bool
%c5    = Constant(5) :Int
%mtern = TernaryExpr(%lt, %c5, %x0) :Int
%otern = TernaryExpr(%c1, %mtern, %c1) :Int
return %otern
L: GREEN
```
