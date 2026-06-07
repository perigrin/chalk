# Increment

Pre-increment (`++$i`) and post-increment (`$i++`) idioms. Both are
read-modify-write (RMW): read the current value, add 1, write the result
back to the variable slot, then return the post-write value. Both produce
the same return value when `return $i` follows the increment.

The RMW write-back is represented here with `Assign` — the natural Chalk IR
node for a plain `=` write-back. The more precise node for `++$i` in the
full compiler is `CompoundAssign(op => '+=')`, but the constructive
`build_graph_from_ir` builder in `MdtestCorpus.pm` does not support
`CompoundAssign` because it requires an extra `op` parameter that the
current named-SSA binary-op pattern (`Op(%a, %b)`) cannot convey. `Assign`
is semantically equivalent for the purpose of `return $i` (the return
reads the post-write value regardless of how the write was encoded). The
LLVM target handles both `Assign` and `CompoundAssign` through the same
`_lower_assign` code path.

Builder gap noted: once the named-SSA syntax gains a keyword-arg form
(e.g. `CompoundAssign(%lhs, %rhs, op: "+=")`) the `Assign` here should be
replaced with `CompoundAssign` for full IR fidelity.

The B1 stale-read guard does NOT fire on these cases because the RMW
internal read (`$i_r`), the lhs slot (`$i_l`), and the final return read
(`$i`) are **distinct PadAccess nodes**: each has a different `varname`,
so `content_hash` gives each a unique id. They do not alias, and no
poisoning occurs.

## K1 pre-increment (++$i; return $i)

Pre-increment reads the current value of `$i`, adds 1, writes the result
back, and the subsequent `return $i` sees the incremented value.

```perl
# source
my $i = 0; ++$i; $i
```

```behavior
return: 1
context: scalar
```

```ir
%c0    = Constant(0) :Int
%iname = Constant("i") :Str
%vd    = VarDecl(%iname, %c0) :Int
%c1    = Constant(1) :Int
%read  = PadAccess(%vd, "$i_r") :Int    # RMW internal read — distinct node from final read
%add   = Add(%read, %c1) :Int
%lhs   = PadAccess(%vd, "$i_l") :Int    # lhs slot for write-back — distinct from read nodes
%ca    = Assign(%lhs, %add) :Int        # write-back (Assign stands in for CompoundAssign += 1)
%ret_r = PadAccess(%vd, "$i") :Int      # final return read — distinct from RMW read
return %ret_r
control: %vd -> %ca
L: GREEN
```

## K2 post-increment ($i++; return $i)

Post-increment has the same side-effect graph as pre-increment when the
return is of `$i` (not the expression `$i++`). The distinction between `++$i`
(returns new value) and `$i++` (returns old value) is immaterial here because
the return statement reads `$i` after the increment completes in both cases.

```perl
# source
my $i = 0; $i++; $i
```

```behavior
return: 1
context: scalar
```

```ir
%c0    = Constant(0) :Int
%iname = Constant("i") :Str
%vd    = VarDecl(%iname, %c0) :Int
%c1    = Constant(1) :Int
%read  = PadAccess(%vd, "$i_r") :Int    # RMW internal read — distinct node from final read
%add   = Add(%read, %c1) :Int
%lhs   = PadAccess(%vd, "$i_l") :Int    # lhs slot for write-back
%ca    = Assign(%lhs, %add) :Int        # write-back (same side-effect shape as K1)
%ret_r = PadAccess(%vd, "$i") :Int      # final return read — distinct from RMW read
return %ret_r
control: %vd -> %ca
L: GREEN
```
