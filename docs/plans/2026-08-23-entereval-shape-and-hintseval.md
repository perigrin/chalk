# String eval: `entereval` is a unary op, and the walk descends into `hintseval`

**Date:** 2026-08-23
**Status:** FILED, COORDINATOR-VERIFIED. Not fixed. No miscompile — it refuses,
but with a message naming the wrong layer.
**Found by:** measuring what `t/base/lex.t:261` (`eval(q{...}) || print ...`)
actually is, after the ring blocker attributed to it turned out to be a
different construct.

## How string eval appears in the optree — MEASURED

    perl -MO=Concise,-exec -e 'my $r = eval q{1+2}; print $r;'

    3  <$> const[PV "1+2"] s
    4  <1> entereval[t256] sK/1
    5  <1> padsv_store[$r:1,2] vKS/LVINTRO

**One op.** `entereval` is a UNARY op (`/1` = one declared child, `sK` = scalar
context with kids) that consumes a string and produces a value. It is not a
region and has no closing partner in the emitted stream.

Contrast BLOCK eval, which is a genuine bracketed region:

    3  <|> entertry(other->4) s
    b  <;> nextstate(main 2 -e:1) v
    c  <$> const[IV 3] s/FOLD
    4  <@> leavetry sK

`entertry` branches (`other->4`) and its body IS in the optree. That is the
structural difference: block eval's body is compiled code; string eval's body is
a STRING.

With a non-constant operand the string is not even known at compile time:

    6  <0> padsv[$c:1,3] s
    7  <1> entereval[t256] sK/1

## The actual failure, and it is NOT "entereval is unhandled"

    sub { my $r = eval q{1+2}; $r }
    -> Required parameter 'value' is missing for "SoN::IR::Node::Constant"
       constructor at lib/SoN/IR/NodeFactory.pm line 368

Walking the CV's ops shows why:

    leavesub, lineseq, nextstate, padsv_store, entereval, const,
    hintseval, null, nextstate, padsv

`entereval` has a SECOND child: **`hintseval`**, an SV carrying the lexical
hints (pragmas, `use strict` state) the eval'd code must inherit. The walk
descends into it, treats it as a value operand, and tries to build a Constant
from an SV that has no value the extractor understands.

So the refusal comes from the CONSTRUCTOR, not from a GAP. It is loud — nothing
miscompiles — but it names `SoN::IR::Node::Constant` when the honest statement
is "string eval is not compiled". Same wrong-layer shape as the `_require_repr`
misattribution recorded in
`docs/plans/2026-08-23-package-main-filter-drops-declared-classes.md`.

Block eval fails differently and also wrongly:

    sub { my $r = eval { 1+2 }; $r }  ->  Stack underflow at
                                          lib/SoN/FromOptree/StackSim.pm line 25

That is the string a prior session recorded as never observed in the ring. It
reproduces here.

## The OpMap entry is miscategorised

`lib/SoN/FromOptree/OpMap.pm:381`:

    entereval   => [1, undef,        1, BRANCH],
    leaveeval   => [1, undef,        1, 0],

`BRANCH` is wrong: the optree shows a unary op with one value child (plus
`hintseval`), not a branch with arms. And the `undef` node_type with no handler
puts it in the same family as `goto` and `write` — see
`docs/plans/2026-08-23-goto-silently-dropped.md`.

Note `leaveeval` appears in the table but NOT in the walked op list: for string
eval, only `entereval` is present at the call site. `leaveeval` roots the
eval'd code's own optree, which does not exist until runtime — exactly the
`enterwrite`/`leavewrite` split, where only `enterwrite` appears at the call
site because `leavewrite` roots the format's separate CV.

## STRING EVAL IS NOT COMPILABLE IN PRINCIPLE, AND THAT IS THE POINT

This is the first construct measured in this project that is not merely
unbuilt but **structurally impossible** for a runtime-free target:

- `enterwrite` — the format body is a separate CV. It EXISTS and is compiled;
  walking it is work, not a barrier.
- `goto` — needs real control flow. Buildable.
- `entereval` with a CONSTANT operand — the string is known at compile time and
  could in principle be compiled then. Buildable, if anyone wants it.
- `entereval` with a VARIABLE operand — the code does not exist until runtime.
  Compiling it requires shipping the compiler as the runtime, which is exactly
  what "runtime-free" excludes.

So the correct end state is a permanent, well-worded GAP for the variable form,
not a TODO. The constant form is a separate question nobody needs yet.

## The fix

Add `entereval` to `%UNBUILT_OP_GAP` (`lib/SoN/FromOptree.pm`) alongside
`enterwrite`/`leavewrite`, with a message that says string eval is not compiled
and why, so the refusal stops naming `SoN::IR::Node::Constant`. Two lines, the
same shape as the `goto` fix.

That does NOT unblock `lex.t`: measured, its ring blocker is reported as
something else entirely, and closing this changes which message it reports, not
whether it passes. File this as correctness-of-diagnosis, not as ring progress.

The `hintseval` descent is worth a second look independently — an op the walk
treats as a value when it is compiler metadata is the kind of thing that will
recur, and `null` is in the same op list.
