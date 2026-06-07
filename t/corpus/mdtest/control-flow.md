# Control Flow

Control-flow idioms: ternary select, if/else, while, foreach, postfix modifiers,
nested conditionals, and try/catch.

D6 (ternary / select) is the only idiom in this topic that is runtime-free
lowerable — it maps to an LLVM `select i1` instruction with no basic-block splits.
All other idioms require LLVM basic blocks, `br`, and either `phi` (D1-D5, D7) or
`landingpad` (D8) — none of which are in the current literal-arithmetic lowering
slice.

One builder gap is reported below: the constructive ir-block builder parses binary
(2-input) and unary (1-input) op forms but has no 3-input form. TernaryExpr takes
three inputs (condition, true-branch, false-branch) and cannot be expressed in the
current named-SSA syntax. The LLVM backend does support TernaryExpr via `select`;
the gap is in the markdown builder, not the lowering pass.

## D6 ternary (n>0 ? 1 : 2)

The ternary `$n > 0 ? 1 : 2` compiles to a NumGt comparison (producing an i1
Bool) fed into a TernaryExpr (LLVM `select i1`). No branches, no phi — the only
runtime-free control-flow idiom in this topic.

Builder gap: the named-SSA syntax handles `Op(%a, %b)` for binary ops and `Op(%a)`
for unary ops, but has no 3-input form. `TernaryExpr(%cond, %true, %false)` needs
three named inputs. The LLVM backend (`_lower_ternary` in Target::LLVM) supports
this op; the gap is in the constructive markdown builder. Once a 3-input form is
added to the builder, this case becomes GREEN.

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
L: GAP(builder: TernaryExpr needs 3 inputs but binary-op pattern handles 2 args only; LLVM backend supports this op via select i1)
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
L: GAP(needs LLVM basic blocks + br + phi for if/else join)
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
L: GAP(needs LLVM basic blocks + br + phi for loop back-edge)
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
L: GAP(needs LLVM basic blocks + br + phi for foreach loop back-edge)
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
L: GAP(needs LLVM basic blocks + br + phi for single-branch conditional)
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
L: GAP(needs LLVM basic blocks + br + phi for postfix-while back-edge)
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
L: GAP(needs LLVM basic blocks + br + phi for nested if/else join)
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
