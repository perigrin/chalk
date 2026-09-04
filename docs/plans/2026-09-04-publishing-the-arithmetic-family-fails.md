# Publishing the whole arithmetic family fails: 224 -> 184

**Date:** 2026-09-04
**Status:** MEASURED, REVERTED. Nothing from this attempt is committed.
**Producer pin:** perl5-son `b96087c`.

## The question, and the honest answer to it first

perigrin asked: *"Is `+` polymorphic?"*

**No, and my claim that it was is wrong.** Measured on perl 5.42:

    "3" + "4"   is 7      -- not "34"; there is no string-preserving `+`
    1   + "abc" is 1      -- the string numifies to 0

`+` numifies both operands unconditionally. I had justified admitting only
`Divide` to `%IR_OP_SOURCE_NAME` on the grounds that `+`, `-`, `*` are
"genuinely polymorphic in perl (Int+Int and Num+Num are both valid)". That
conflated two different things:

- what varies between `1+2` and `1.5+2` is the **result representation**
  (`B::IV` vs `B::NV`)
- the **operand requirement** is numeric either way

This table answers the second question. `%BINARY_OP_SIGNATURES` has always
agreed — `+ - * / % **` share one `(Num, Num) -> Num` entry.

So the comment in commit `169a0cb3` is wrong on that point, and the obvious
follow-up was to publish the whole family.

## That follow-up FAILS, and the number is large

Adding `Add`, `Subtract`, `Multiply`, `Power` to `%IR_OP_SOURCE_NAME` (plus
`Modulo` with its own `Int` signature — measured, `7.9 % 3` is `1`, not `1.9`,
so perl truncates both operands and the shared `Num` entry is imprecise for it):

    corpus gate   224 -> 184     (-40 cases)
    worklist        3 -> 43
    Num-stamped nodes  54 -> 215

The unit test went green. The gate did not.

## Why: this table is not a passive lookup

`operand_repr_for_ir_op` feeds `_required_operand_repr`
(`Analysis.pm:1365`), which drives **`_insert_str_coercions`** — a pass that
MINTS `Coerce` nodes. Publishing a requirement does not merely record an
observation; it causes T1 to insert coercions that did not previously exist.
That is why the `Num` node count nearly quadrupled: most of the new nodes are
coercions the change itself created.

The failures come in three shapes:

1. **`shape: missing [Coerce(Int -> Str) :Str, Add :Int]`** — the corpus `ir`
   blocks pin the graph, and inserting coercions changes it. These are spec
   disagreements, arguably fixable by updating the blocks.
2. **`lli '' != perl '60'`** — behavioural. Not a spec question.
3. **`invariant: op Subtract at position 0: Coerce node to_repr=Num does not
   match required Num`** — the interesting one. It says a thing does not match
   itself, which means the comparison is not the string equality it appears to
   be. Not diagnosed.

Shape (3) is the signal that this change interacts with machinery I have not
understood, not merely that some spec blocks are stale.

## What this says about the design

The narrowing design
(`2026-09-04-t2-narrowing-the-design.md`) assumed observations could be
published cheaply and consumed later by a separate solver. **They cannot, as
things stand**: publishing an observation has an immediate side effect in
`_insert_str_coercions`, so "add a constraint" and "change the emitted graph"
are the same action today.

That is a real finding for the design, and it changes the shape of the work:

- A narrowing pass wanting to READ requirements needs a channel that does not
  also mint coercions — either a separate table, or a flag on the lookup, or
  `_insert_str_coercions` learning which requirements are advisory.
- Until then, the residue measurement is confounded: publishing a requirement
  changes the population being measured.

## What stands from the earlier commit

`169a0cb3` (Divide alone) is green at 224 and stays. Its measurement holds:

    54 Num-stamped nodes, 19 pinned (35%), residue 35
      fractional literal   15
      Divide wants Num      4

Its *justification comment* is wrong about `+` being polymorphic and should be
corrected — but correcting the comment is not the same as making the change it
describes, and this document is why.

## Not established

- Why `to_repr=Num does not match required Num` fails. That comparison is
  somewhere in the invariant checker and was not read.
- Whether the shape-(1) failures are simply stale `ir` blocks. Plausible, but
  40 cases is too many to assume.
- Whether `Modulo => Int` is right independently of the rest. It was measured
  (`7.9 % 3 == 1`) but only tested as part of the failing bundle.
