# Subs

Named sub definitions, anonymous subs (closures), and chained sub calls.

All cases in this topic are L: GAP — but CodeRef is runtime-free (RF). Per the
runtime-free boundary, named subs and closures are RF: a CodeRef's
representation is a function pointer plus a captured-environment struct (NOT an
SV*), and a call is an indirect call. A statically-known call target is RF —
this is NOT "dynamic dispatch"; only a runtime-computed target would be
out-of-subset. These cases are GAPs only until the CodeRef representation and
call lowering are modelled — not because they need the interpreter. The
behavior is specified by the perl oracle; each GAP records the work-list item
that closes it.

Archive sources: `archive/pu-2026-03-24:t/corpus/ir/sub-simple.chalk` (F1),
`archive/pu-2026-03-24:t/corpus/ir/anon-sub.chalk` (F2),
`archive/pu-2026-03-24:t/corpus/ir/chain-call.chalk` (F3 — adapted from method
chain to sub chain for the subs topic).

## F1 named sub

A named sub is defined and immediately called. The sub returns a constant
integer value. The IR models the sub definition as a separate graph and the
call site as a Call node with dispatch_kind=sub. This is RF: the sub lowers to
a function pointer plus a captured-environment struct, and the call — whose
target is statically known — lowers to an indirect call (not dynamic dispatch,
which would require a runtime-computed target). The GAP is only that the
CodeRef representation and call lowering are not modelled yet.

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
L: GAP(CodeRef is RF: a function pointer + captured-env struct, call = indirect call to a statically-known target; GAP only until CodeRef representation is modelled, NOT a libperl/SV dependency)
```

## F2 anonymous sub

An anonymous sub (closure) is created with `sub { ... }`, stored in a lexical
variable as a CodeRef, and then invoked via the arrow-call syntax
`$fn->()`. The IR models this with an AnonSub node (which carries a nested
graph) and a Call node at the invocation site. This is RF: the closure lowers
to a function pointer plus a captured-environment struct (NOT an SV*), and the
arrow-call is an indirect call to a statically-known target. The GAP is only
that the CodeRef representation is not modelled yet.

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
L: GAP(CodeRef is RF: a function pointer + captured-env struct, call = indirect call; GAP only until CodeRef representation is modelled, NOT a libperl/SV dependency)
```

## F3 chained sub calls

One sub calls another sub — a two-level call chain. The IR contains two Call
nodes at the respective call sites. Both are RF: each call target is
statically known, so each lowers to an indirect call through a function
pointer (not dynamic dispatch, which would require a runtime-computed target).
The GAP is only that the CodeRef representation and call lowering are not
modelled yet. This case is adapted from the archive chain-call idiom to stay
within the subs topic (the archive source was method chaining on an object,
which belongs to the classes topic).

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
L: GAP(CodeRef is RF: each call is an indirect call to a statically-known target via a function pointer; GAP only until CodeRef representation is modelled, NOT a libperl/SV dependency)
```
