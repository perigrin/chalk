# ABOUTME: Chalk's Print rule requires Str in EVERY position; operand 0 may be a filehandle.
# ABOUTME: Latent today only because the loader drops the Glob stamp that would expose it.

# `print STDERR "x"` does not print "STDERR"

Reported by perl5-son (2026-09-02) after fixing the producer side, and
confirmed present in chalk.

## The rule

    lib/Chalk/IR/Analysis.pm:171
    my %_NODE_OPERAND_REPR = (Print => 'Str');

`_required_operand_repr($op, $position)` consults this table FIRST and returns
its value for **every** position, ignoring `$position` entirely. So operand 0
of a `Print` is required to be `Str`.

That is true of everything a `print` PRINTS. It is false of operand 0 when a
filehandle is stacked there:

    print STDERR "x"    # writes "x" to stderr
                        # does NOT write the six characters "STDERR"

Measured on 5.42.0 — both `print STDERR ...` and `print STDOUT ...` emit only
their argument, never the handle's name.

## Why it does not fire yet

Two defects are cancelling, which is the only reason the corpus is green here.

Producer `b792c05` now stamps the handle honestly. Measured on the wire for
`print STDERR "hi\n"`:

    #2  Constant  stamp=Glob      <- []        the handle
    #3  Constant  stamp=Str       <- []        the payload
    #4  Print     stamp=Scalar    <- [#2, #3]

But chalk's loader DROPS that stamp. `%LOWERABLE_STAMP`
(`lib/Chalk/IR/Serialize/JSON.pm:87`) admits only

    Int Num Str Boolean Undef Object ArrayRef HashRef Array Hash Scalar

so `Glob` is filtered out and the node arrives untyped. Measured through the
loader:

    %4   Constant      :undef     <- [] value=STDERR
    %6   Print         :Boolean   <- [%4,%5]

`_insert_str_coercions` declines an operand with no representation ("nothing
established a type, so a coercion here would be the guess the producer already
declined to make"), so no `Coerce(Glob -> Str)` is inserted and nothing breaks.

**A wrong rule and a dropped stamp cancel exactly.** perl5-son hit the same
pair from the other side: their handle was mis-stamped `Str`, and their
coercion predicate declines a `Str` operand, so their "every position" rule was
equally invisible until the stamp became honest.

## Why this is not fixed here yet

The obvious repair — add `Glob`/`GlobRef` to `%LOWERABLE_STAMP` — would make
the stamp survive and IMMEDIATELY expose the Print rule, turning a latent bug
into a live `Coerce(Glob -> Str)` at operand 0. The two must move together:

1. `%_NODE_OPERAND_REPR` needs to express "Str at positions 1..n, and operand 0
   is a handle when one is stacked". The table is keyed by op only; the
   per-position mechanism already exists
   (`TypeLibrary::operand_repr_for_ir_op($op, $position)`), so the fix is
   plausibly to move `Print` there rather than to grow this table.

2. Deciding what operand 0 may be. perl5-son measured TWO spellings with TWO
   types and no common subtype:

       ref($T)     GLOB       lexical handle   -> GlobRef
       ref(*FOO)   not a ref  bareword handle  -> Glob
       blessed($T) no         so NOT IO

   and `join(Glob, GlobRef)` is `Unknown`. They tried declaring a single
   `GlobRef` requirement for `open` and it was wrong twice, fabricating a
   handle from a string and then a reference from a glob; their corpus Unknowns
   went 369 -> 373. Each spelling is now stamped at its source instead. A
   single-type requirement at Print operand 0 would repeat that mistake.

3. `Glob`/`GlobRef` need a machine encoding before `%LOWERABLE_STAMP` should
   admit them — that table is a CONTRACT ("a stamp admitted here is claimed to
   have a machine encoding"), and admitting a stamp with no encoding moves the
   failure from a dropped type to a backend refusal.

## Related

`%LOWERABLE_STAMP` living in the loader is itself the recorded T2-fact-in-a-T1-file
defect. Its own comment documents `Scalar` having been excluded "long after it
gained" a machine encoding, at the cost of the largest single GAP group in the
gate. `Glob`, `GlobRef`, `CodeRef` and `Ref` are all currently dropped the same
way — this is the first case where a dropped stamp is load-bearing for
CORRECTNESS rather than only for coverage.
