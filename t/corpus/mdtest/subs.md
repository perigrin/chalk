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
use 5.42.0;
sub foo { return 1 }
say(foo());
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::foo") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
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
use 5.42.0;
sub side { 42 }
my $n = 7;
side();
say($n);
```

```behavior
stdout: 7\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::side")
%n = Constant(7) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%n : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
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
%arr   = ArrayLiteral(%c1, %c2, %c3) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GAP(multi-value list return: callee drops all-but-last, needs list-result + caller flatten)
```

## F5 direct sub call with arguments (t/ blocker: F3 argument binding)

A direct call to a named sub PASSING arguments (`f(10)` where `f` reads its
argument via `shift`/`@_`). Earlier work lowered a no-arg direct call (inline the
callee value); an arg-passing call binds the argument into the callee's parameter
read. Since the callee is INLINED (not a real call frame), the caller's Call input
is bound by SSA substitution to the callee's positional `shift @_` read — the
loader types the callee's `shift` read from the argument's repr (so the callee body
`$x + 1` carries an Int repr), and the backend intercepts the callee's `shift` node
during inlining and returns the caller's argument ref. This is the load-bearing
blocker for t/op (Test::More `is`/`ok` are arg-passing calls). GREEN for the sound
single-positional-`shift` shape; a callee that reads `@_` as an aggregate (a
list-assign `my ($a,$b)=@_` or a `$_[N]` subscript) or via multiple `shift`s (which
hash-cons to one node and lose their order) GAPs loudly — see F6/F7.

```perl
# source
use 5.42.0;
sub f { my $x = shift; $x + 1 }
my $r = f(10);
say($r);
```

```behavior
stdout: 11\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## F6 identity sub returns its shifted argument

A callee whose whole body is a single `shift` returns its first argument
unchanged. The `shift @_` read is the callee's Return value directly, so the
inline binding substitutes the caller's argument ref for the whole call — the
bilateral counterpart to F5 (F5 computes over the arg; F6 returns it verbatim).

```perl
# source
use 5.42.0;
sub id { shift }
say(id(99));
```

```behavior
stdout: 99\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::id") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## F7 list-assign of @_ into named params GAPs

A callee that reads its arguments as an aggregate — `my ($a,$b) = @_` — does NOT
carry the positional binding the caller's args need: the producer emits the pad
params but does not connect the list-assign to `@_` in the graph, so the two
PadAccess reads have no def linking them to the caller's `3` and `4`. Inlining
binds only positional `shift @_` reads; this shape (and its `$_[N]`-subscript and
multiple-`shift` siblings) GAPs loudly rather than miscompiling to a stale/zero
value. Flip to GREEN when the producer connects `my (...) = @_` to the call
arguments (a multi-parameter binding, the caller-side analogue of F4's
multi-value return).

```perl
# source
sub add { my ($a, $b) = @_; $a + $b }
add(3, 4)
```

```behavior
return: 7
context: scalar
```

```ir
L: GAP(list-assign of @_ into named params — inlining binds only positional `shift @_`; `my (...) = @_` does not connect to the call arguments in the graph)
```

## F8 positional `$_[0]` subscript binds the argument (t/cmd/elsif.t blocker)

A callee that reads its first argument as `$_[0]` (a subscript on `@_`, not
`shift @_`). The producer emits `Subscript(Constant("_"), Constant(0), Mem)` —
the `@_` array by name at index 0. Inlining binds it exactly like a positional
`shift @_`: the caller's argument ref substitutes for the Subscript node during
inlining (keyed by refaddr, consulted before _lower_subscript). This is the
t/cmd/elsif.t blocker (`sub foo { if ($_[0] == 1) {...} }`). GREEN for a single
`$_[N]` read; multiple distinct `$_[N]` subscripts (arg 0 AND arg 1) are a
multi-positional shape that still GAPs (like multiple `shift`s).

```perl
# source
use 5.42.0;
sub f { $_[0] + 1 }
say(f(10));
```

```behavior
stdout: 11\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## F9 effectful callee inline threads its print in program order (Slice B Commit 2-print)

A callee whose body performs an effect (`print`) and then returns a value that
the caller uses — `sub f { print "x"; 2 } my $r = f(); $r`. The callee's Return
value subgraph is just the constant `2`, but its `control_in` chain carries the
`print "x"` (`Return.control_in -> Print -> Start`, program order). Slice B
Commit 1 first converted the silent drop into a loud GAP (`_lower_call_direct`
died unless the callee's `Return.control_in` was `undef`/`Start`). Commit
2-print now threads a STRAIGHT-LINE Print-only chain (no Region/Loop/If/Assign
anywhere on it): `_collect_straight_line_effect_chain` walks `control_in` back
to `Start`, and `_lower_inlined_effects_then_value` drives it through
`process_control_node` (oldest-first) inside the arg-bind frame, splicing the
callee's `print "x"` onto the caller's control chain BEFORE the Return value is
lowered — `lli` now emits `xInt:2`, matching perl. Any OTHER effect shape
(Assign/store, or a Region/Loop/If on the chain — the parked loop-store slice)
still GAPs; see F12.

```perl
# source
use 5.42.0;
sub f { print "x"; 2 }
my $r = f();
say($r);
```

```behavior
stdout: x2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## F10 cross-graph cache-collision: caller AND callee both print, order preserved

The load-bearing hazard: `lower_value`'s cache is keyed by the node's STRING id
(`Print#N`), and each graph numbers its nodes from its OWN factory — a callee
`Print#N` can collide with an unrelated CALLER `Print#N`. A caller print
BEFORE the call, plus an inlined callee print, both survive and land in
program order only if the inliner does not silently serve the callee's print
from the caller's cached ref (or vice versa). `_lower_inlined_effects_then_value`
swaps the WHOLE cache to a fresh hash for the duration of the callee's chain
drive (mirrors the existing refaddr-keyed `_arg_bind` frame pattern), so the
callee's `Print` node is never cache-hit against the caller's identically-numbered
node.

```perl
# source
use 5.42.0;
sub f { print "callee"; 2 }
print "caller";
my $r = f();
say($r);
```

```behavior
stdout: callercallee2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%call : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## F11 same effectful callee inlined at two call sites emits its print twice

Side-effecting ops STAY cached once lowered (they execute once at their
control position) — so a naive fix that merely computed the callee's effect
under its real string id would drop the SECOND inline's print (the two calls'
`Print` nodes are the SAME node object, cached after the first inline). Since
`_lower_inlined_effects_then_value` swaps to a fresh cache per INLINE
INSTANCE (not per node), each call site re-lowers and re-emits the callee's
print independently — matching perl, which runs the sub body twice.

```perl
# source
use 5.42.0;
sub f { print "y"; 2 }
my $a = f();
my $b = f();
say($a + $b);
```

```behavior
stdout: yy4\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call1 = Call(dispatch_kind: "direct", name: "main::f") :Int
%call2 = Call(dispatch_kind: "direct", name: "main::f") :Int
%sum   = Add(%call1, %call2) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%sum : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## F12 loop-effect callee (parked loop-store shape) still GAPs, not a broken lowering

A callee whose control chain contains a `Region` (a loop that prints, then
returns a value) is the PARKED loop-store shape (Slice B Commit 2-loop-store,
not built here — memory-SSA re-entrancy is a separate slice).
`_collect_straight_line_effect_chain` GAPs loudly on any non-`Print`,
non-`Start` node it meets walking `control_in` — a `Region` here included — so
this shape is never attempted, only ever a clean GAP, never a reordered or
dropped effect.

```perl
# source
sub g { for my $i (1..2) { print "z" } 9 }
my $r = g();
$r
```

```behavior
stdout: zz
return: 9
context: scalar
```

```ir
L: GAP(direct call to 'g': callee has effect(s) on its control chain (print/store/...) that inlining does not yet thread in program order)
```

## F13 unused-result call still threads its effect (perl5-son R1.0 effect-by-default)

`sub f { print "x"; 2 } my $r = f(); 3` — like F9, but `$r` is never read: the
call's VALUE is completely dead, only its EFFECT matters, and the trailing
statement (`3`) is a different, unrelated value than the call's return. Before
perl5-son's R1.0 fix, `FromOptree::_handle_entersub` only pinned a Call's
`control_in` `if $void` — a non-void call (this one binds `$r`, so it is NOT
OPf_WANT_VOID) got NO control pin at all. Unpinned, the Call was unreachable
from Return, and the producer's reachability walk dropped it entirely: the
loaded caller graph was literally Start / Constant / Return, with no Call node
at all, and `print "x"` silently vanished (perl prints `x`; chalk printed
nothing). The fix pins `control_in` unconditionally (void or not) and advances
the sim's control to the Call before deciding whether to also push its value,
so the call survives and orders correctly regardless of whether its result is
used.

```perl
# source
use 5.42.0;
sub f { print "x"; 2 }
my $r = f();
say(3);
```

```behavior
stdout: x3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%call = Call(dispatch_kind: "direct", name: "main::f") :Int
%n    = Constant(3) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%n : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## F14 two calls to one sub with DIFFERENT arguments

The value miscompile the memoisation path produces, and the reason F11 does not
catch it: F11's callee PRINTS, so its visible output comes from the effect
chain, which IS re-driven per call site. The VALUE is lowered once through the
shared `{cache}` and served to the second site with the first site's argument
baked in.

Measured before the fix (Chalk 5c34fdf9 and earlier): `f(1)+f(2)` gave 4 where perl gives 6, and the emitted
LLVM contained exactly ONE `mul` for two calls.

Arguments must DIFFER. `f(3)+f(3)` passes today by coincidence -- the single
cached computation happens to be the right answer for both.

```perl
# source
use 5.42.0;
sub f { my $n = shift; $n * 2 }
print f(1) + f(2), "\n";
```

```behavior
stdout: 6\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%f1   = Call(%c1, dispatch_kind: "direct", name: "main::f") :Int
%c2   = Constant(2) :Int
%f2   = Call(%c2, dispatch_kind: "direct", name: "main::f") :Int
%sum  = Add(%f1, %f2) :Int
%co   = Coerce(%sum : Int -> Str) :Str
%nl   = Constant("\n") :Str
%p    = Print(%co, %nl)
return %p
L: GREEN
```

The two Calls stay DISTINCT nodes with distinct arguments -- that is the whole
contract here. Before the fix the graph was the same shape but the LOWERING
collapsed both to one computation, so the shape leg alone could never have
caught this; only the behavior leg did.

Written from measured output. An earlier version of this block expected a
folded `Constant(6)`, which nothing produces: the producer does not
constant-fold across a call, and Print takes its operands directly rather than
through a Concat.

## F15 the same call nested in its own argument

`f(f(1))` -- the same defect reached differently. The inner call's value is
cached, then the outer call reads that cache entry rather than computing over
the inner result. Worth its own case: an argument-binding fix could plausibly
close F14 and not this.

Measured before the fix (Chalk 5c34fdf9 and earlier): 2 where perl gives 4.

```perl
# source
use 5.42.0;
sub f { my $n = shift; $n * 2 }
print f(f(1)), "\n";
```

```behavior
stdout: 4\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%inner = Call(%c1, dispatch_kind: "direct", name: "main::f") :Int
%outer = Call(%inner, dispatch_kind: "direct", name: "main::f") :Int
%co   = Coerce(%outer : Int -> Str) :Str
%nl   = Constant("\n") :Str
%p    = Print(%co, %nl)
return %p
L: GREEN
```

The nesting is visible in the edge: the outer Call takes the INNER Call as its
argument, rather than both reading the same constant. That is what makes this
case distinct from F14 -- an argument-binding fix could plausibly close F14 and
leave this one broken.

Written from measured output; see the note under F14 about the folded
`Constant(4)` an earlier version of this block expected.

## F16 two calls in separate statements

The same defect outside a single expression, so a fix scoped to one expression
tree does not close it. Measured before the fix (Chalk 5c34fdf9 and earlier): `2 2` where perl gives `2 4`.

```perl
# source
use 5.42.0;
sub f { my $n = shift; $n * 2 }
my $a = f(1);
my $b = f(2);
print "$a $b\n";
```

```behavior
stdout: 2 4\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c2   = Constant(2) :Int
%c4   = Constant(4) :Int
%sp   = Constant(" ") :Str
%nl   = Constant("\n") :Str
%p    = Print(%nl)
return %p
L: GREEN
```

## F17 named sub with a signature parameter

A sub declared with a signature (`sub f($x)`) called with one argument. This is
the single most common sub form in `lib/Chalk/` -- 94 uses, against ZERO corpus
coverage before this case.

It LOWERS but does not RUN: `lli` prints nothing where perl prints 42. The
callee's body never sees the argument, because argument binding for direct calls
is the F3 gap (`_lower_call_direct` inlines a no-argument callee's result). So
the sub form itself is not the blocker -- passing a value into it is.

RECORDED HONESTLY BECAUSE I GOT IT WRONG FIRST: my probe called
`Chalk::Target::LLVM->lower` on this shape, saw no exception, and I wrote the
case GREEN. Lowering is not executing. The behavioural leg caught it on the
first gate run. This is precisely the trap the bson session measured on the
producer side the same day -- a broken implementation that closes more holes
than the correct one scores better on coverage alone -- and a corpus case
declared from a lowering probe rather than an execution is the same error in
the other direction.

```perl
# source
use 5.42.0;
sub f($x) { $x + 1 }
say(f(41));
```

```behavior
stdout: 42\n
return: Bool:1
context: scalar
```

L: GAP: direct call argument binding is unimplemented (F3) -- the call lowers, emits no output, and lli prints nothing where perl prints 42

## F18 sort with a comparator block

`sort { $a <=> $b }` -- 16 uses in `lib/Chalk/`, no corpus coverage. The block
is a Call the backend does not lower.

GAP: `LLVM backend: cannot lower op=Call (not in literal-arithmetic slice)`

The same blocker covers F19 and F20: sort, grep and map blocks are ONE gap
reached three ways, together accounting for 293 uses in `lib/Chalk/`. They are
filed as three cases because a fix scoped to one block-taking builtin would
close only that one, and the corpus should say so.

```perl
# source
use 5.42.0;
my @s = sort { $a <=> $b } (3,1,2);
say($s[0]);
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

L: GAP: LLVM backend: cannot lower op=Call (not in literal-arithmetic slice)

## F19 grep with a block

`grep { ... }` -- part of the 277 grep/map block uses in `lib/Chalk/`. Same
blocker as F18.

```perl
# source
use 5.42.0;
my @g = grep { $_ > 1 } (3,1,2);
say(scalar(@g));
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

L: GAP: LLVM backend: cannot lower op=Call (not in literal-arithmetic slice)

## F20 map with a block

`map { ... }` -- the other half of the 277. Same blocker as F18.

```perl
# source
use 5.42.0;
my @m = map { $_ * 2 } (1,2);
say($m[1]);
```

```behavior
stdout: 4\n
return: Bool:1
context: scalar
```

L: GAP: LLVM backend: cannot lower op=Call (not in literal-arithmetic slice)

## F21 postfix hash dereference `->%*`

`$h->%*` -- 85 uses in `lib/Chalk/`, no corpus coverage. Unlike F18-F20 this is
NOT an honest GAP: the backend CRASHES.

    Can't call method "id" on an undefined value at lib/Chalk/Target/LLVM/Context.pm

A crash is not a refusal. The GAP-not-miscompile invariant says an unsupported
construct must be REFUSED with a message naming what is missing; dying on an
undefined value names nothing and cannot be distinguished from a bug in a
supported path. This case exists to hold that distinction open: the fix is
either a real lowering or an honest GAP, and either closes it.

The array form `->@*` lowers (5 corpus cases), so this is specific to the hash
form rather than to postfix dereference generally.

```perl
# source
use 5.42.0;
my $h = {a=>1};
my %c = $h->%*;
say($c{a});
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

L: GAP: postfix hash dereference crashes rather than refusing -- Can't call method "id" on an undefined value

## F22 polymorphic callee: one sub called with Int and with Str

The shape the corpus has NEVER contained. G7's census over 231 cases found **4
multi-callsite callees and ZERO polymorphic**, and recorded what that costs:
"on every gate case `join(args) == args[0]`, and gather-then-stamp is
behaviourally IDENTICAL to first-caller-wins: **the gate holds whether the join
is correct, inverted, or absent.**" This case is the discriminator that was
missing.

Measured 2026-08-30 against producer `8c15e32`: the JOIN IS CORRECT and the
LOWERING IS NOT. `_seed_direct_call_arg_reprs` stamps the shared `shift` read
`Str` — the join of `Int` and `Str`, not first-caller-wins, which would give
`Int` — and both Call nodes carry `Str`. So T1 gets the right answer.

The backend then emits invalid IR:

    error: '%tmp_1' defined with type 'i64' but expected '%Str = type { i8*, i64, i32 }'
      %tmp_2 = extractvalue %Str %tmp_1, 0   ; %Str.ptr

The callee body is emitted once, at the JOINED type (`%Str`), but the `Int`
call site passes its argument as a raw `i64`. Nothing coerces at the boundary.
This is a T2 gap, not a typing one: T1 correctly says "this parameter is Str at
one site and Int at the other, so the parameter is Str", and lowering needs
either a `Coerce[Int -> Str]` at the narrowing call site or a per-callsite
specialisation of the callee.

It is also the first case where the argument join is OBSERVABLE. Every other
corpus case is monomorphic, so this is the only one that would go red if the
join were inverted or deleted.

```perl
# source
use 5.42.0;
sub id { my $x = shift; return $x }
say(id(1));
say(id("hi"));
```

```behavior
stdout: 1\nhi\n
return: Bool:1
context: scalar
```

L: GAP: the callee is emitted once at the joined type (%Str) but the Int callsite passes a raw i64 -- no coercion at the call boundary
