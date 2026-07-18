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
%cls    = MOP::Class(name: "_A5Tmp")
%mf     = MOP::Field(class: %cls, name: "x", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%fa     = FieldAccess(field_index: 0, field_stash: "_A5Tmp") :Int
%mi     = MOP::Method(class: %cls, name: "val", body: %fa, return_repr: "Int")
%v42    = Constant(42) :Int
%new    = Call(%v42, dispatch_kind: "method", name: "new", class: "_A5Tmp", param_names: "x") :Object
%result = Call(%new, dispatch_kind: "method", name: "val", class: "_A5Tmp") :Int
return %result
L: GREEN
```

## C1 reassign then read

`my $x = 1; $x = 2; return $x` — a declaration initialised to `1`, followed
by a plain reassignment to `2`, with a single read of the final value.

The IR is a Sea-of-Nodes SSA graph, and dead-store elimination is IMPLICIT in
its construction: a pad slot is modelled as an immutable value binding at each
program point, so the reassignment `$x = 2` simply rebinds the slot to
`Constant(2)`, and the sole read observes that binding. The init `1` is never
observed by any read (no read-before-reassign, no read-through-copy), so it is
not reachable from the Return and does not appear in the graph — the SSA graph
IS `Constant(2)`. This is not an optimization applied to a fuller graph; it is
what the SSA construction produces. (Contrast the read-before-reassign case
`my $x = 1; my $y = $x; $x = 2; $y`, where the copy binds `$y` to the live
value `1` at that point, so THAT graph correctly returns `Constant(1)` — SSA
captures the distinction; the init is dead here only because it is genuinely
never read.)

```perl
# source
my $x = 1; $x = 2; $x
```

```behavior
return: 2
context: scalar
```

```ir
%two  = Constant(2) :Int
return %two
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

## A6 shift from a lexical array

`my @q = (1,2,3); shift @q` removes and returns the FIRST element (1). `shift`
mutates the array in place: it advances the array header's element pointer by
one slot and decrements its length (an O(1) front-drop), so a later whole-array
read observes the drained array. The mutation is modelled as a memory statement
effect — the `Call(builtin shift)` leads with control, takes the array and the
current memory, and produces the new memory version — so it is ordered on the
effect chain (not orphaned) and its result is stamped with the array's element
type.

```perl
# source
my @q = (1, 2, 3);
shift @q
```

```behavior
return: 1
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%arr   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%mem   = MemStart()
%sh    = Call(%arr, %mem, dispatch_kind: "builtin", name: "shift") :Int
return %sh
control: %sh
L: GREEN
```

## A7 pop from a lexical array

`my @q = (5,6); pop @q` removes and returns the LAST element (6), decrementing
the array's length. Like `shift`, it is a stamped memory statement effect.

```perl
# source
my @q = (5, 6);
pop @q
```

```behavior
return: 6
context: scalar
```

```ir
%c5    = Constant(5) :Int
%c6    = Constant(6) :Int
%arr   = ArrayRef(%c5, %c6) :ArrayRef
%mem   = MemStart()
%pp    = Call(%arr, %mem, dispatch_kind: "builtin", name: "pop") :Int
return %pp
control: %pp
L: GREEN
```

## A8 constant range literal expands to all its elements

`my @q = (1..4)` constant-folds (in perl) to a single `const[AV]` holding the
four elements. The producer must expand that folded AV into a full 4-element
`ArrayRef`, not read only its first element (which built a 1-element array, so
`scalar @q` returned 1 — a silent miscompile). With the AV expanded, `scalar @q`
counts all four.

```perl
# source
my @q = (1..4);
scalar @q
```

```behavior
return: 4
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%c4    = Constant(4) :Int
%arr   = ArrayRef(%c1, %c2, %c3, %c4) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GREEN
```

## A9 list-copy flattens the source array

`my @b = @a` copies @a's ELEMENTS into @b (a list-context assignment), so
`scalar @b` is @a's length, not 1. The producer currently wraps the source
aggregate as a single element (ArrayRef(ArrayRef(...))) so `scalar @b` returns 1
-- a silent miscompile of the same list-flattening class as A8's `(1..4)`. The
target: an array variable read in the list-context RHS of a list assignment
flattens to its elements.

```perl
# source
my @a = (1, 2, 3);
my @b = @a;
scalar @b
```

```behavior
return: 3
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%arr   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GREEN
```

## A10 list literal flattens an interpolated array

`my @b = (@a, 4)` builds a list that FLATTENS @a's elements and appends the
scalar, so @b is (1, 2, 3, 4) and `scalar @b` is 4. The producer currently counts
the array as one element (returning 2 for `(@a, 4)`) -- the list-flattening gap
applied to an array embedded in a list literal.

```perl
# source
my @a = (1, 2, 3);
my @b = (@a, 4);
scalar @b
```

```behavior
return: 4
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%c4    = Constant(4) :Int
%arr   = ArrayRef(%c1, %c2, %c3, %c4) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GREEN
```

## A11 list literal flattens two arrays

`my @c = (@a, @b)` flattens BOTH arrays into @c, so with @a = (1, 2) and
@b = (3, 4), @c is (1, 2, 3, 4) and `scalar @c` is 4 (the producer currently
returns 2). Multi-array flatten is the general form of A9/A10.

```perl
# source
my @a = (1, 2);
my @b = (3, 4);
my @c = (@a, @b);
scalar @c
```

```behavior
return: 4
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%c4    = Constant(4) :Int
%arr   = ArrayRef(%c1, %c2, %c3, %c4) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GREEN
```

## A12 list-copy flattens an array-ref variable deref

`my @b = @$r` derefs an arrayref VARIABLE in list context, so with
`$r = [1, 2, 3]` @b is (1, 2, 3) and `scalar @b` is 3. The producer flattened
only a const-range rv2av (A8) and a bare padav (A9-A11); an rv2av over a padsv
bound to a literal ArrayRef wrapped the single ref as ONE element, so
`scalar @b` returned 1 (a silent miscompile). The rv2av-flatten path now also
fires over a padsv kid in list context. A `@$r` over a RUNTIME ref (not a
literal ArrayRef node) stays a loud producer GAP. zhi 019f5e42.

```perl
# source
my $r = [1, 2, 3];
my @b = @$r;
scalar @b
```

```behavior
return: 3
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%arr   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GREEN
```

## A13 push onto a lexical array grows it

`push @b, 3` appends to @b, so with @b = (1, 2) the result is (1, 2, 3) and
`scalar @b` is 3. push/unshift GROW the array, but unlike shift/pop (which are
memory-SSA modeled -- the Call becomes the new memory version) the growing
mutation is not threaded onto @b's memory version, so a later `scalar @b` reads
the PRE-push binding and returns 2 -- a silent miscompile. The producer now
GAPs push/unshift loudly. Flip to `L: GREEN` when the growing mutation is
memory-modeled like shift/pop. zhi 019f5e42.

```perl
# source
my @a = (1, 2);
my @b = @a;
push @b, 3;
scalar @b
```

```behavior
return: 3
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%arr   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GAP(push/unshift array-growing mutation not memory-modeled: new length not observed by a later read)
```

## A14 splice shrinks a lexical array

`splice(@a, 1, 1)` removes one element, so with @a = (1, 2, 3) the result is
(1, 3) and `scalar @a` is 2. splice mutates array length like push/unshift, and
like them the mutation is not memory-modeled (only shift/pop are memory-SSA
modeled), so a later `scalar @a` reads the PRE-splice binding and returns 3 -- a
silent miscompile. The producer now GAPs splice loudly. Flip to `L: GREEN` when
the length mutation is memory-modeled like shift/pop. zhi 019f5ed3.

```perl
# source
my @a = (1, 2, 3);
splice(@a, 1, 1);
scalar @a
```

```behavior
return: 2
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c3    = Constant(3) :Int
%arr   = ArrayRef(%c1, %c3) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GAP(splice array length mutation not memory-modeled: new length not observed by a later read)
```

## A15 deref of a runtime array-ref GAPs

`my $r = \@a; my @b = @$r` derefs a RUNTIME array-ref -- $r is bound to a
Reference node (`\@a`), not a literal ArrayRef, so its elements are not known at
compile time and cannot be statically flattened (unlike A12, where $r is a
literal `[1,2,3]`). Leaving the single ref as one element would make `scalar @b`
return 1 (a silent miscompile); the producer GAPs it loudly instead. Flip to
`L: GREEN` when a runtime array-ref deref is lowered (a real deref + copy).
zhi 019f5e42.

```perl
# source
my @a = (1, 2, 3);
my $r = \@a;
my @b = @$r;
scalar @b
```

```behavior
return: 3
context: scalar
```

```ir
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%arr   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%len   = Length(%arr) :Int
return %len
L: GAP(deref of a runtime array-ref: elements not statically known, needs a real deref+copy)
```

## A16 package variable read (our $g) — t/ blocker: StashAccess

A package/global variable (`our $g = 5; $g`) models the stash slot as a
module-level LLVM global `@pkg_main_g` (an `i64` slot). The `our $g = 5` store is
a statement effect: an `Assign(StashAccess-lvalue, value)` threaded onto the
control chain that lowers to `store i64 5, i64* @pkg_main_g`. The `$g` read is a
`StashAccess` load (`load i64, i64* @pkg_main_g`) — a mutable-location read, so it
re-lowers at every use and observes the post-store value. t/ files use package
vars.

```perl
# source
our $g = 5;
$g
```

```behavior
return: 5
context: scalar
```

```ir
%c5    = Constant(5) :Int
%gl    = StashAccess(stash_name: "main", var_name: "g") :Int
%st    = Assign(%gl, %c5) :Int
%gr    = StashAccess(stash_name: "main", var_name: "g") :Int
return %gr
control: %st
L: GREEN
```

## A17 two distinct package globals — no aliasing

`our $g = 5; our $h = 7; $g + $h` proves two package scalars are DISTINCT
module-level slots (`@pkg_main_g` and `@pkg_main_h`), not one aliased cell: the
sum is 12, not 14 (which a single shared slot would yield). Each store threads
onto the control chain; the reads load their own slot.

```perl
# source
our $g = 5;
our $h = 7;
$g + $h
```

```behavior
return: 12
context: scalar
```

```ir
%c5    = Constant(5) :Int
%c7    = Constant(7) :Int
%gl    = StashAccess(stash_name: "main", var_name: "g") :Int
%stg   = Assign(%gl, %c5) :Int
%hl    = StashAccess(stash_name: "main", var_name: "h") :Int
%sth   = Assign(%hl, %c7) :Int
%gr    = StashAccess(stash_name: "main", var_name: "g") :Int
%hr    = StashAccess(stash_name: "main", var_name: "h") :Int
%sum   = Add(%gr, %hr) :Int
return %sum
control: %stg -> %sth
L: GREEN
```

## A18 read-modify-write a package global

`our $g = 5; $g = $g + 1; $g` re-stores into the SAME slot: the second store
reads the post-init value (5), adds 1, and writes 6 back. The final read observes
the re-stored value. This exercises store + read + re-store against one
`@pkg_main_g` slot (the mutable-read model must NOT serve a cached pre-store read).

```perl
# source
our $g = 5;
$g = $g + 1;
$g
```

```behavior
return: 6
context: scalar
```

```ir
%c5    = Constant(5) :Int
%c1    = Constant(1) :Int
%gl    = StashAccess(stash_name: "main", var_name: "g") :Int
%st1   = Assign(%gl, %c5) :Int
%gr1   = StashAccess(stash_name: "main", var_name: "g") :Int
%inc   = Add(%gr1, %c1) :Int
%st2   = Assign(%gl, %inc) :Int
%gr2   = StashAccess(stash_name: "main", var_name: "g") :Int
return %gr2
control: %st1 -> %st2
L: GREEN
```

## A19 package variable holding a string (our $g = "str")

A package/global scalar can hold a STRING, not just an Int (`our $g = "hi"; $g`).
A Str value is a `(ptr, len)` pair in this backend, so a Str package scalar is
modeled as TWO mutable module-level slots — `@pkg_main_g_ptr` (`i8*`) and
`@pkg_main_g_len` (`i64`) — not the single `i64` slot an Int global uses. The
`our $g = "hi"` store writes both slots (the string-constant pointer and its byte
length); the `$g` read loads both and re-registers the loaded ptr in the length
table so a downstream print/return slices exactly `len` bytes. The producer stamps
the StashAccess with the RHS value's repr (Str here), not a hardcoded Int — the
store lvalue and the read hash-cons to one node, so the read inherits the Str repr.
This is the t/base blocker for cond.t / if.t / pat.t (package string globals).

```perl
# source
our $g = "hi";
$g
```

```behavior
return: hi
context: scalar
```

```ir
%c     = Constant("hi") :Str
%gl    = StashAccess(stash_name: "main", var_name: "g") :Str
%st    = Assign(%gl, %c) :Str
%gr    = StashAccess(stash_name: "main", var_name: "g") :Str
return %gr
control: %st
L: GREEN
```

## A20 reassign a string package global reads the new value

`our $g = "hi"; $g = "bye"; $g` re-stores a DIFFERENT string into the same two
slots. The final read must observe the re-stored `(ptr, len)` — "bye" (len 3), not
"hi" (len 2) — proving the Str package global is a genuine mutable location (both
slots re-written on the second store), not a cached pre-store read. Bilateral with
A18 (the Int RMW): A18 re-stores an Int into one slot; A20 re-stores a Str across
two slots, and the differing lengths (2 vs 3) make a stale-read miscompile visible.

```perl
# source
our $g = "hi";
$g = "bye";
$g
```

```behavior
return: bye
context: scalar
```

```ir
%c1    = Constant("hi") :Str
%c2    = Constant("bye") :Str
%gl    = StashAccess(stash_name: "main", var_name: "g") :Str
%st1   = Assign(%gl, %c1) :Str
%st2   = Assign(%gl, %c2) :Str
%gr    = StashAccess(stash_name: "main", var_name: "g") :Str
return %gr
control: %st1 -> %st2
L: GREEN
```
