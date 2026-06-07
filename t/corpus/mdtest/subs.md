# Subs

Named sub definitions, anonymous subs (closures), and chained sub calls.

All cases in this topic are L: GAP — subroutine definitions and calls require
CodeRef (SV*) representation and dynamic dispatch, neither of which is part of
the runtime-free lowering slice (which covers only Int/Num arithmetic, Bool, and
TernaryExpr). The behavior is specified by the perl oracle; each GAP records the
honest reason the compile-time-only LLVM path cannot yet lower these idioms.

Archive sources: `archive/pu-2026-03-24:t/corpus/ir/sub-simple.chalk` (F1),
`archive/pu-2026-03-24:t/corpus/ir/anon-sub.chalk` (F2),
`archive/pu-2026-03-24:t/corpus/ir/chain-call.chalk` (F3 — adapted from method
chain to sub chain for the subs topic).

## F1 named sub

A named sub is defined and immediately called. The sub returns a constant
integer value. The IR models the sub definition as a separate graph and the
call site as a Call node with dispatch_kind=sub. Neither the sub definition
(SubDef/graph boundary) nor the Call node is in the current runtime-free LLVM
lowering slice, which handles only straight-line arithmetic with no dynamic
dispatch or code pointers.

Archive source: `sub helper($x) { return $x + 1; }` (sub-simple.chalk).

```perl
# source
sub foo { return 1 }
foo()
```

```behavior
return: 1
context: scalar
```

```ir
L: GAP(Call node not in LLVM lowering slice; sub call requires dynamic dispatch / CodeRef)
```

## F2 anonymous sub

An anonymous sub (closure) is created with `sub { ... }`, stored in a lexical
variable as a CodeRef (SV*), and then invoked via the arrow-call syntax
`$fn->()`. The IR models this with an AnonSub node (which carries a nested
graph) and a Call node at the invocation site. AnonSub requires CodeRef/SV*
representation, which is outside the runtime-free lowering slice.

Archive source: `my $fn = sub { return 1; };` (anon-sub.chalk).

```perl
# source
my $fn = sub { return 1 };
$fn->()
```

```behavior
return: 1
context: scalar
```

```ir
L: GAP(AnonSub/CodeRef needs Scalar/SV* representation; not runtime-free lowerable in the current Int/Num slice)
```

## F3 chained sub calls

One sub calls another sub — a two-level call chain. The IR contains two Call
nodes at the respective call sites, each requiring dynamic dispatch. Neither
is in the runtime-free LLVM lowering slice. This case is adapted from the
archive chain-call idiom to stay within the subs topic (the archive source
was method chaining on an object, which belongs to the classes topic).

```perl
# source
sub add1 { my ($x) = @_; return $x + 1 }
sub add2 { my ($x) = @_; return add1($x) + 1 }
add2(3)
```

```behavior
return: 5
context: scalar
```

```ir
L: GAP(chained Call nodes not in LLVM lowering slice; sub-to-sub dispatch requires CodeRef/dynamic-dispatch support)
```
