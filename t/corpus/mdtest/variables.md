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
code path. The named-SSA builder supports the keyword-arg form
`CompoundAssign(%lhs, %rhs, op: "+=")` for the `op` parameter.

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

`field $x :param; return $x` — a class field declared with `:param`. Per
docs/architecture/runtime-free-boundary.md field access is RF: a `feature class`
is lexically declared, so the object is a static struct `{vtable*, fields}` and a
field read is a known offset load — no libperl, no runtime SV slot. The MOP
object-struct + field-offset lowering (campaign group G5) models exactly this.

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
%fa     = FieldAccess(field_index: 0, field_stash: "_A5Tmp") :Int
%mi     = MethodInfo(name: "val", body_node: %fa, return_repr: "Int")
%mf     = MOP::Field(name: "x", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%cls    = ClassInfo(name: "_A5Tmp", methods: [%mi], fields: [%mf])
%v42    = Constant(42) :Int
%new    = Call(%cls, %v42, dispatch_kind: "method", name: "new", param_names: "x") :Object
%result = Call(%new, %cls, dispatch_kind: "method", name: "val") :Int
return %result
L: GREEN
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
(`$x_l`, for the CompoundAssign lhs), and the result read (`$x`, for the Return).
Using distinct varnames gives each a unique content hash, so they are
separate nodes in the graph and no poisoning occurs.

The compound assignment is modelled with `CompoundAssign(op: "+=")` — the
accurate node for `$x += 2`. The `op` keyword arg distinguishes it from plain
`Assign` and distinguishes different compound operators from each other.

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
%ca    = CompoundAssign(%lhs, %sum, op: "+=") :Int
%rx    = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %ca
L: GREEN
```
