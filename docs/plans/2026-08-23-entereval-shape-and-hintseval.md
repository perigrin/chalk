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
unbuilt but **structurally impossible from where B::SoN stands** — and that
holds for BOTH operand forms, not just the variable one.

**B::SoN runs at CHECK time, on an already-compiled optree.** The `entereval`
op is there; the eval'd code is not. Perl compiles that string only when the op
EXECUTES, so at the moment B::SoN walks the tree there is no optree for the
body to walk — the walk is looking at the program before it has run.

That kills the constant case too. `eval q{1+2}` looks compilable because the
string is known, but making it so would require B::SoN to invoke the perl
compiler on that string mid-walk and splice the resulting optree into the
graph. That is running the compiler, at compile time, over data the optree
merely POINTS AT. It is a different tool, not a missing feature here.

Compare the rest of the family, which are all genuinely buildable:

- `enterwrite` — the format body is a separate CV that EXISTS and is already
  compiled. Walking it is work, not a barrier.
- `goto` — needs real control flow. Buildable.
- `entereval`, either operand form — the body has never been compiled, and
  B::SoN's whole position is downstream of compilation.

So the correct end state is a permanent, well-worded GAP for string eval as a
whole. Not a TODO, and not "constant form later".

(An earlier revision of this document called the constant form "buildable if
anyone wants it". That was wrong: it reasoned from whether the STRING is known
rather than from whether an OPTREE exists, which is the question B::SoN's
position actually poses.)

### The subprocess design, and the hole that kills it

perigrin raised the obvious escape: shell out to a SUBPROCESS that compiles the
string into a graph, then splice that graph in where the IR node would go. That
does dissolve the "different tool" objection — a subprocess is exactly how you
get an optree for a string without B::SoN becoming a compiler itself.

Two of its holes are closeable with effort: replaying `hintseval`'s pragma
state into the subprocess, and the per-site process cost.

**One is not, and it fails SILENTLY. Measured:**

    perl -e 'my $x = 5; my $r = eval q{$x + 1}; print $r'    # 6
    perl -e '         my $r = eval q{$x + 1}; print $r'      # 1

Same string, two answers. String eval's body closes over the ENCLOSING PAD, so
`$x` is the lexical 5 in the first case. A subprocess compiling `$x + 1`
standalone has no such pad: `$x` resolves to an undefined global and `undef + 1`
is 1. **No error, no warning.** A spliced-in graph built that way would emit 1
where perl emits 6 — a silent miscompile, which is the one failure class this
project does not accept.

Closing that would mean handing the subprocess the enclosing pad's shape AND
binding the resulting graph's free variables back to the caller's SSA
values — i.e. reimplementing perl's pad resolution across a process boundary,
for code whose text may vary per execution.

Two further walls stand behind it, both structural:

- `eval $c` — the string is not known at compile time at all.
- An eval in a loop over a varying string is a DIFFERENT program each
  iteration; inlining one graph presumes one body.

The design is therefore recorded as considered-and-rejected rather than
deferred. Anyone revisiting it should start from the pad-capture measurement
above, because that is the case that produces a wrong answer rather than a
refusal.

## The fix — LANDED, and it took three edits, not one

The first two were necessary but insufficient, which is worth recording because
each looked like the whole answer:

1. **`entereval` added to `%UNBUILT_OP_GAP`** (`lib/SoN/FromOptree.pm`),
   alongside `enterwrite`/`leavewrite`. Did nothing on its own.
2. **`entereval`'s BRANCH flag cleared** (`OpMap.pm:381`). The generic walk
   skips `is_branch` ops, so the new refusal was unreachable. Still nothing.
3. **`hintseval` changed from `Constant` to `SKIP`** (`OpMap.pm:513`) — THE
   ACTUAL TRIGGER. It was registered as a value-producing constant, so the walk
   built a Constant from a hints SV before `entereval` was ever dispatched, and
   died in the constructor.

`SKIP` with no push keeps the stack balanced: exec order is `const`,
`entereval`, `hintseval`, so the `const` supplies `entereval`'s single popped
operand and `hintseval` had been pushing a spurious extra.

Edits 1 and 2 are kept: the refusal must exist and must be reachable, or the
next person to touch this hits the same wall in a different order.

**NOT ring progress**, and stated so deliberately: `lex.t`'s reported blocker is
something else, so this changes which message it prints, not whether it passes.
Filed as correctness-of-diagnosis.

## The general lesson

`hintseval` is an op the walk treated as a VALUE when it is compiler METADATA.
That class will recur — `null` sits in the same op list, and the `dispatch_kind`
and `package=main` findings this same day were both "the machinery answered a
question it should not have been asked". Worth a sweep of the OpMap for other
entries whose `node_type` claims a value for an op that carries none.
