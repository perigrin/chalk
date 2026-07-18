# Subs

Named sub definitions, anonymous subs (closures), and chained sub calls.

The direct-call cases (F1 named sub, F1v void call) are GREEN; the CodeRef
cases (F2 closure, F3 chained) remain L: GAP — but CodeRef is runtime-free
(RF). Per the
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
call site as a Call node with dispatch_kind=direct — the target is statically
known (a bareword named sub), so it is a direct call, not dynamic dispatch. The
loader resolves the Call's name (main::foo) to the callee graph, and the backend
lowers the no-argument call by inlining the callee's result. This is RF: no
libperl/SV dependency.

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
%call = Call(dispatch_kind: "direct", name: "main::foo") :Int
return %call
L: GREEN
```

## F1v void direct call

A named sub is called in VOID statement position — `side();` — for its side
effect, with its result discarded, and a later value is returned. The call is
NOT the return value; it is a statement effect that must be threaded onto the
control chain (is_stmt_effect) so it is ordered and survives DCE. Without that
threading the pushed Call is dead in void context and the call vanishes
silently (zhi 019f26a5). The loader seeds the single-exit Return from the
stmt-effect Call as well as the returned value, so the call is scheduled before
the Return. This is RF: a direct call to a statically-known target.

```perl
# source
sub side { 42 }
my $n = 7;
side();
$n
```

```behavior
return: 7
context: scalar
```

```ir
%call = Call(dispatch_kind: "direct", name: "main::side")
%n = Constant(7) :Int
return %n
L: GREEN
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

## F4 sub returning a list flattens into the caller's list assignment

`sub inner { return (10, 20, 30) }` returns a LIST; `my @x = inner()` binds @x to
all three elements, so `scalar @x` is 3. Modeling this requires a multi-value
call return: the callee must yield every value (not just the last) AND the
caller's list-assignment must flatten them. The producer previously kept only
the last return value (`$args->[-1]` / a single `pop_node` at leavesub),
silently dropping 10 and 20, so `scalar @x` returned 1 -- a silent miscompile.

The sub body is compiled once and is context-independent, so the producer
cannot know the caller's runtime wantarray; a >1-value return cannot be soundly
collapsed to one scalar Return. Per GAP-not-miscompile the producer now refuses
the multi-value list return loudly (`_leavesub_returns_list` detects the trailing
OP_LIST / OP_RETURN with >1 value child). Flip to `L: GREEN` when a multi-value
return is modeled as a list result the caller's aassign flattens (this is the
list-flattening class variables.md A9-A11 at a sub-call boundary, and the
caller-side half of the no-Return list-returning method that poisons the shared
MOP -- Phase-5: Chalk::IR::Node::_serialize_inputs returns @parts). zhi 019f5e41.

```perl
# source
sub inner { return (10, 20, 30) }
my @x = inner();
scalar @x
```

```behavior
return: 3
context: scalar
```

```ir
%c1    = Constant(10) :Int
%c2    = Constant(20) :Int
%c3    = Constant(30) :Int
%arr   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GAP(multi-value list return: callee drops all-but-last, needs list-result + caller flatten)
```

## F5 direct sub call with arguments (t/ blocker: F3 argument binding)

A direct call to a named sub PASSING arguments (`f(10)` where `f` reads
`shift`/`@_`). Earlier work lowered a no-arg direct call (inline the callee value);
an arg-passing call needs argument binding into the callee params — currently a loud
GAP (`direct call ... passes arguments`). This is the load-bearing blocker for t/op
(Test::More `is`/`ok` are arg-passing calls). Flip to GREEN when direct-call argument
binding lands.

```perl
# source
sub f { my $x = shift; $x + 1 }
my $r = f(10);
$r
```

```behavior
return: 11
context: scalar
```

```ir
L: GAP(direct call passes arguments — argument binding into the callee not yet lowered (F3))
```
