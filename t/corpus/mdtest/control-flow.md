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

A postfix `EXPR while COND` is a do-while loop: the body executes, then the
condition is checked for the back-edge. Requires a loop header block, a
conditional branch, and phi nodes for induction variables.

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
