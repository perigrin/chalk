# ABOUTME: A slice is a List, the loader drops that stamp, and the backend cannot lower Slice at all.
# ABOUTME: Zero corpus coverage, so none of it is measurable by the gate today.

# Slices: no coverage, no lowering, and a dropped stamp behind both

perl5-son landed `Slice => List` (bb73dfb) and flagged that it might cost
chalk, since `List` has no machine reading here either. Measured: it costs
nothing, and the reason is worth stating precisely because "no regression"
here does not mean "handled".

## Measured, against pinned producer b792c05

    eda7a95  gate-green=214 behavior=215 shape=215 invariant=221 worklist=8
    b792c05  gate-green=214 behavior=215 shape=215 invariant=221 worklist=8
    fixed 0, broken 0

## Why nothing moved: the corpus cannot see a slice

    grep -cE '@[a-z_]+\[[0-9]' t/corpus/mdtest/*.md   ->  0

**ZERO corpus cases use a slice**, in any of the twelve topic files. The gate
could not have registered a change either way. That is a coverage gap, not a
clean bill of health.

For scale, `lib/Chalk` itself uses 10 of them, including
`@_[-2, -1]` in the LLVM backend and `@args[0 .. $#args - 1]` in the Perl
target -- so this is an idiom the self-hosting path actually needs.

## Three layers, and the stamp is the least of them

Traced `my @a=(1,2,3,4,5); my @s=@a[1,2]; say($s[0]);` (perl prints 2):

1. **The producer is correct.** It stamps the Slice `List`, and that is both
   right and the tightest honest answer. Measured here on 5.42.0 with
   `my @a = (1,2,3,4,5)`:

       \@a         ->  ARRAY
       \@a[1..3]   ->  SCALAR, pointing at element 3 (value 4)

       scalar(@a[1..3])  ->  4    the LAST element
       scalar(@a)        ->  5    a real count

   An array yields ONE array ref; a slice yields a scalar ref to its last
   element -- the comma operator's collapse, the same one `scalar()` shows.
   So a slice is not an Array, and Array/Hash/Scalar are the only things under
   List, leaving no narrower true stamp.

   A NON-ARGUMENT, recorded because this doc first carried it: `\(@a[1..3])`
   yields three SCALAR refs rather than one ARRAY ref. That looks like the same
   proof and is not -- `\(@a)` on a PLAIN ARRAY yields five SCALAR refs,
   identically. The distribution comes from `\(...)` mapping over any list,
   not from the operand being a slice, so the form cannot separate the two
   cases. perl5-son raised and retracted it; I reproduced both the confound and
   the discriminator above before correcting this.

   (The aliasing is real either way: `$$rs = 99` writes through to `@a`.)

2. **The loader drops it.** `%LOWERABLE_STAMP` (Serialize/JSON.pm:87) does not
   admit `List`, and the existing `List -> Array` rescue at :723 is scoped to
   BUILTIN CALLS, so a `Slice` is not rescued. Measured through the loader:

       %7   Slice         :undef     <- [%1,%2,%6]
       %11  Subscript     :undef     <- [%8,%9,%10]

   The untyped Slice propagates to the read of it.

3. **The backend cannot lower it at all**, and this is the actual blocker:

       LLVM backend: cannot lower op=Slice (not in literal-arithmetic slice)
       at lib/Chalk/Target/LLVM/Context.pm line 1673

   There is no `Slice` arm. Widening `%LOWERABLE_STAMP` to admit `List` would
   change WHICH message appears, not whether the program lowers.

## What to do, in order

1. **Add corpus cases first.** Without them nothing here is measurable, and a
   fix would land unexercised by the gate -- the failure mode F2 nearly shipped
   with. At minimum: an array slice read, a hash slice, and a slice in list
   context vs scalar context (they differ: scalar context gives the last
   element).
2. **Lower `Slice`.** This is the real work and it is independent of the
   stamp.
3. **Then widen `%LOWERABLE_STAMP`** for `List`, once there is something for
   the type to reach.

Doing (3) alone is the tempting one-line change and it buys nothing.

## Related

`%LOWERABLE_STAMP` living in the loader is the recorded T2-fact-in-a-T1-file
defect. `Glob`, `GlobRef`, `CodeRef`, `Ref` and `List` are all dropped there
today. See `2026-09-02-print-operand-zero-is-not-a-str.md` for the case where a
dropped stamp is load-bearing for CORRECTNESS rather than only for coverage --
there, widening the filter without fixing the rule beside it would turn a
latent bug into a live miscompile.
