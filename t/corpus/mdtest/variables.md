# Variables

Lexical variable declaration, assignment, compound assignment, and reads in
the Chalk typed-IR model.

The SSA model uses `VarDecl` for declarations, `PadAccess` for reads, and
`Assign` for writes. `PadAccess` nodes are hash-consed by `(targ, varname,
inputs[0])`: two `PadAccess` nodes with the same varname referencing the same
`VarDecl` are the SAME node in the graph. The B1 stale-read guard detects
when a cached pre-assign read would be served as a post-assign value and GAPs
rather than MISCOMPILEing.

For read-modify-write idioms (`$x += 2`, `++$x`) the internal read, the lhs
slot, and the final return read must use DISTINCT `PadAccess` nodes. This is
done by giving each a unique `varname` string (`$x_r` for the internal read,
`$x_l` for the write-back lhs, `$x` for the result read). The LLVM target
handles both `Assign` and `CompoundAssign` through the same `_lower_assign`
code path; the corpus uses `Assign` here because the named-SSA binary-op
builder pattern (`Op(%a, %b)`) cannot convey the extra `op` parameter that
`CompoundAssign` requires.

Builder gap noted: once the named-SSA syntax gains a keyword-arg form
(e.g. `CompoundAssign(%lhs, %rhs, op: "+=")`) the `Assign` here should be
replaced with `CompoundAssign` for full IR fidelity.

## A1 my-decl with init and read

`my $x = 1; return $x` — the simplest lexical-variable idiom. A single
`VarDecl` initialised to `1`, a single `PadAccess` read, and a `Return`.
The control chain threads through `%vx` so the declare happens before the
read.

```perl
# source
my $x = 1; $x
```

```behavior
return: 1
context: scalar
```

```ir
%one  = Constant(1) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %one) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
L: GREEN
```

## A4 my-decl then assign

`my $x; $x = 1; return $x` — a declaration with no initialiser followed by
a plain assignment. `VarDecl` is built with one argument (the name constant
only; no init — the builder's unary-op handler). The `Assign` stores `1`
into the variable. The `PadAccess` reads the post-assign value.

The lhs of `Assign` is a `PadAccess(%vx, "$x")` node. Because `Assign` in
`_lower_assign` never calls `lower_value(lhs)` (it only uses `lhs` to find
the owning `VarDecl`), the lhs `PadAccess` is never recorded as a read in
`reads_of_var`. When the result `PadAccess` is lowered, `reads_of_var` is
empty, no poisoning has occurred, and the updated var-table value `1` is
served correctly.

```perl
# source
my $x; $x = 1; $x
```

```behavior
return: 1
context: scalar
```

```ir
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn) :Int
%one  = Constant(1) :Int
%lhs  = PadAccess(%vx, "$x") :Int
%as   = Assign(%lhs, %one) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %as
L: GREEN
```

## A5 field param read

`field $x :param; return $x` — a class field declared with `:param`. Field
access has no runtime-free representation in the current typed IR: the value
lives in an SV-boxed slot whose address is determined at object-construction
time. No static-dispatch `PadAccess` can model it without libperl. This
idiom is a pure GAP.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class _A5Tmp { field $x :param; method val { $x } }
_A5Tmp->new(x => 42)->val
```

```behavior
return: 42
context: scalar
```

```ir
L: GAP(field has no Scalar-free representation; needs libperl SV slot access)
```

## C1 reassign then read

`my $x = 1; $x = 2; return $x` — a declaration initialised to `1`, followed
by a plain reassignment to `2`, with a single read of the final value. The
`Assign` updates the var-table from `1` to `2`. The result `PadAccess` is
distinct from the lhs `PadAccess` (same varname, same VarDecl — BUT the lhs
is never lowered as a read, so `reads_of_var` is empty and the B1 poison
guard never fires). The lli output is `2`.

```perl
# source
my $x = 1; $x = 2; $x
```

```behavior
return: 2
context: scalar
```

```ir
%xn   = Constant("$x") :Str
%one  = Constant(1) :Int
%vx   = VarDecl(%xn, %one) :Int
%two  = Constant(2) :Int
%lhs  = PadAccess(%vx, "$x") :Int
%as   = Assign(%lhs, %two) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %as
L: GREEN
```

## C2 compound assign then read

`my $x = 1; $x += 2; return $x` — a declaration followed by a compound
assignment. `$x += 2` is a read-modify-write (RMW): read the current value
of `$x`, add `2`, write the result back to `$x`.

RMW requires three distinct `PadAccess` nodes to avoid the B1 stale-read
guard: the internal read (`$x_r`, for the Add input), the lhs write-back slot
(`$x_l`, for the Assign lhs), and the result read (`$x`, for the Return).
Using distinct varnames gives each a unique content hash, so they are
separate nodes in the graph and no poisoning occurs.

The compound assignment is modelled with `Assign` (write-back after explicit
`Add`). See the file header for the builder-gap note on `CompoundAssign`.

```perl
# source
my $x = 1; $x += 2; $x
```

```behavior
return: 3
context: scalar
```

```ir
%one   = Constant(1) :Int
%xname = Constant("$x") :Str
%vx    = VarDecl(%xname, %one) :Int
%two   = Constant(2) :Int
%read  = PadAccess(%vx, "$x_r") :Int
%sum   = Add(%read, %two) :Int
%lhs   = PadAccess(%vx, "$x_l") :Int
%as    = Assign(%lhs, %sum) :Int
%rx    = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %as
L: GREEN
```
