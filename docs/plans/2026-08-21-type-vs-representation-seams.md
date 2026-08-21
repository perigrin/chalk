# Five seams between Chalk's type system and LLVM's

**Date:** 2026-08-21
**Status:** MEASURED, none fixed. Every claim below has a reproduction.
**Raised by:** perigrin, across one session, mostly by refusing my framings.

Findings 0a/0b share a root cause and are the design content. Findings 1-3 are
independent and smaller. Three of my own claims are retracted at the bottom.

---

## The frame, which I kept getting wrong

perigrin, twice, in different words:

> `Num` is a Chalk type ... `double` is a lowering commitment but it's an LLVM
> type ... Num doesn't make a decision about the representation / target type.

and

> Lexicals as of right now are just another scope for SSA variables no?

Both corrections are the same correction: **I kept letting the lowering
target's model drive decisions that belong to Chalk's own layer.** Once as
`Num`-means-`double` (so I reasoned about lattice design in terms of float
cost), once as pads-and-slots (so I reasoned about lexical scope in terms of
perl's implementation). This is the `chalk_is_l3` failure mode, twice in one
session.

The layering that holds:

    Chalk type      Int <: Num <: Str          an ordered lattice
    LLVM type       i64, double, %Str, ...     unordered, equality only
    the boundary    %_REPR_LLVM_TYPE           where one becomes the other

---

## 0a. CORRECTED: it is not `Add`. UV literals are stamped `Int` and wrap.

**The section below is superseded by this one.** perigrin split the 0-cluster by
whether the program is WRONG (fix now) or merely SLOW (later), which is the
axis that decides what gets fixed -- and chasing 0a under that split found the
actual cause, which is neither `Add` nor a lowering-table shape problem.

There is NO `Add` node in any of the three test cases. Perl's peephole
constant-folded all of them before B::SoN ran. The difference is what perl
folded TO:

    9223372036854775807 + 1    -> Constant value=9223372036854775808  const_type=integer -> Int
    -9223372036854775807 - 2   -> Constant value=-9.22337203685478e+18 const_type=number -> Num
    4611686018427387904 * 4    -> Constant value=1.84467440737096e+19  const_type=number -> Num

So `Subtract`/`Multiply` did not "handle overflow correctly" -- they happened to
fold to NVs. `Add` folded to a UV. All three share `=> 'join'` in
`%RESULT_STAMP` (FromOptree.pm:36-39) and the rule was never consulted.

**The real bug, pinned to one boundary.** The producer classifies perl integer
constants as `const_type=integer` -> `Int` across the WHOLE UV RANGE, but
Chalk's `Int` lowers to SIGNED i64:

    9223372036854775807    integer -> Int    IV_MAX, fine
    9223372036854775808    integer -> Int    *** exceeds i64 ***
    18446744073709551615   integer -> Int    *** UV_MAX ***
    18446744073709551616   number  -> Num    perl switches to NV here

Everything in `[2^63, 2^64-1]` is stamped `Int` and wraps negative.

**Minimal repro needs no arithmetic at all:**

    print 9223372036854775808   perl=9223372036854775808  chalk=-9223372036854775808
    print 18446744073709551615  perl=18446744073709551615 chalk=-1

`print 18446744073709551615` prints `-1`.

The corpus pins `-9223372036854775808` (arithmetic.md:189-210) -- the NEGATIVE
limit. The positive UV range is unpinned, which is how a bare-literal miscompile
survived.

**Layer -- CORRECTED AGAIN.** I called this "a TYPING bug in the producer:
`Int` is the wrong type for a value that does not fit `Int`". Wrong, and wrong
in the same direction as twice before.

perigrin: `Int` is correct ... what `Int` LOWERS TO should be optimized ... this
is the same seam as `Num` lowering to `double`.

`18446744073709551615` IS an integer, so `Int` is the right Chalk type and
`const_type=integer` is the right classification. What is wrong is the lowering
choice `Int => 'i64'` (SIGNED), hardcoded in `%_REPR_LLVM_TYPE`. So 0a and 0b
ARE the same seam after all: one Chalk type, one hardcoded machine type, no
channel for the value's properties.

**`u64` is not a fix.** It would lower `18446744073709551615` correctly and
break every negative integer (`-1` becomes `18446744073709551615`). No single
signedness is right for a type spanning both, which is the same argument as
`Num => double` vs `Num => i64`: the selection needs value facts, not a better
default.

**Retracted from the previous version of this section:** "Add ONLY, and the
difference between it and its two siblings is where the fix starts" (they
differ by constant-folding luck, not by handling) and "0a is typing, 0b is
lowering" (both are lowering). What SURVIVES is the measurement: perl folds
`Add` to a UV and its siblings to NVs, the UV range `[2^63, 2^64-1]` lowers
wrong, and the minimal repro needs no arithmetic.

perigrin's fix-now/fix-later split still holds and is what matters for
sequencing -- 0a produces wrong OUTPUT, 0b produces correct-but-slow output.
They just share a mechanism.

---

## SUPERSEDED: `Add` wraps at i64 where perl promotes to NV

    my $x = 9223372036854775807;
    print $x + 1, "\n";

    perl   9223372036854775808
    chalk -9223372036854775808        wrong sign, wrong value, NO GAP

The producer stamps that `Add` as `Int`. The backend lowers `Int` to `i64` and
lets it wrap. Perl promotes past IV range to an NV.

**MEASURED: `Add` ONLY.** I expected a general arithmetic defect and checked
before writing it down:

    Add       9223372036854775807 + 1     perl=9223372036854775808   chalk=-9223372036854775808  DIVERGE
    Subtract  -9223372036854775807 - 2    perl=-9.22337203685478e+18 chalk=-9.22337203685478e+18 agree
    Multiply  4611686018427387904 * 4     perl=1.84467440737096e+19  chalk=1.84467440737096e+19  agree

Subtract and Multiply promote correctly, float formatting and all. So this is
NOT "Int arithmetic wraps" -- it is specific to `Add`, and the difference
between it and its two siblings is where the fix starts. Not diagnosed here.

The corpus pins the i64 boundary as a LITERAL (`arithmetic.md:189-210`,
`-9223372036854775808` must lower without overflow) but nothing pins arithmetic
that CROSSES it. The boundary was considered; this case slipped past.

**Layer note.** This is not "`Int + Int -> Int` is unsound". The Chalk-level
type is a fine claim about a value that fits in `Int`. The bug is that the
backend lowered it to i64 and wrapped when the value did NOT fit -- a lowering
that silently violated the type it was handed.

## 0b. A provably-integral `Num` lowers to `double` throughout

    print 6 / 3, "\n";

    %tmp_1 = fadd double 0.0, 2.0    ; Constant(2, repr=Num -> double)
    %tmp_4 = call i32 @snprintf(..., double %tmp_1)   ; Coerce[Num->Str]: measure

Correct output (`2`), integral value, float the whole way down. `Divide => 'Num'`
is right -- perl's `/` yields a float type -- and the constant folded to `2`,
so the VALUE is integral even though the TYPE is `Num`.

**This is NOT an argument to narrow Divide's result type.** `6/3` is `Num` and
should stay `Num`. The specialization belongs at the lowering boundary.

## 0a + 0b: the shared root cause

`%_REPR_LLVM_TYPE` (`Target/LLVM/Context.pm:3036`) is a FUNCTION -- one machine
type per Chalk type:

    Int => 'i64',  Num => 'double',  Bool => 'i1',  Str => '%Str', ...

`Num => 'double'` is the only edge into `double` in the table, which is what
makes the boundary legible and is a good property. But a function from type
alone cannot express either of the above, because **both need facts about the
VALUE, not just its type**:

| Chalk type | known about the value | wanted LLVM type |
|---|---|---|
| `Num` | integral | `i64` |
| `Num` | otherwise / unknown | `double` |
| `Int` | fits i64 | `i64` |
| `Int` | provably exceeds i64 | must promote, NOT wrap |

0a and 0b are the same defect from opposite ends: the map answers from the type
alone, and the value's properties never reach it. The relation is one-to-many
and chosen per value -- a SELECTION, not a function.

I had accepted the one-arrow table as correct one turn before perigrin pointed
out `Num => i64` is a legitimate edge. Recorded because "the table is a clean
boundary" and "the table is the wrong shape" were both true and I only saw the
first.

**Not designed here.** Where value-facts live (a lattice refinement? a range
analysis? a per-node flag?) is open, and it is the same question `Int`'s
overflow needs answered. Do not build a second mechanism for 0b without
resolving 0a.

---

## 1. `TernaryExpr` joins its CONDITION with its arms

`%_COMPUTED_REPR` maps `TernaryExpr => 'join'` (`Serialize/JSON.pm:1285`), and
the join collects ALL inputs (`:1537`). A TernaryExpr's inputs are
`(cond, then, else)`.

    join(Bool, None, Int) = <undef>      what runs today
    join(None, Int)       = Int          arms only

`$c ? $a : $b` never evaluates to `$c`, so the condition is not a value the
expression can yield and must not be in the join. Measured on
`sub g { $d++ < 2 ? g() : 7 }`: the TernaryExpr goes untyped, and that is the
ACTUAL reason `g` cannot be typed.

Fix is arms-only for `TernaryExpr` specifically. `Phi` and `DefinedOr` share
the `'join'` rule and their inputs are arms-only already -- do NOT apply this
to the whole rule. Input order `(cond, then, else)` verified on this case only.

## 2. `Add => 'join'` derives what a signature should state

**THE DEFECT IS IN TWO TABLES, IN TWO REPOS.** Fixing one leaves the other:

    chalk     %_COMPUTED_REPR   Add => 'join'   next to Divide => 'Num'   Serialize/JSON.pm:1285
    producer  %RESULT_STAMP     Add => 'join'   next to Divide => 'Num'   FromOptree.pm:36

Both tables mix SIGNATURE entries (`Divide => 'Num'`, `Modulo => 'Int'`,
`Concat => 'Str'`, `Length => 'Int'`) with DERIVATION entries (`Add`,
`Subtract`, `Multiply`, `Negate` => `'join'`) under one key space, so the two
philosophies are indistinguishable by reading the table.

perigrin: `'join'` is the wrong choice there since we KNOW the expected type
signature for the operators.

Note this is NOT what caused 0a -- 0a fires on a bare literal with no
arithmetic node present at all. The two are independent.

**MEASURED: `'join'` mistypes `Int + Str`, and it does not merely look wrong.**

    my $s = "5"; print 2 + $s, "\n";     ->  Add stamp=Str      perl says 7

The join widened `Int` and `Str` to `Str`, but perl's `+` is NUMERIC regardless
of how its operands are spelled -- the result is a number, never a string. A
signature (`(Num,Num) -> Num`) gets this right by construction; the join cannot,
because widening is the wrong operation for an operator that COERCES its
operands.

Downstream this emits malformed IR rather than wrong output -- lli rejects it:

    %tmp_6 = add i64 %tmp_1, %tmp_5   ; Add(repr=Int) -> i64 add
    error: '%tmp_5' defined with type '%Str' but expected 'i64'

Three shapes measured, all the same: `2 + $s`, `$s + $s`, `$s * 2`. NOT silent
miscompiles -- the LLVM verifier catches them -- but they are programs perl runs
and Chalk cannot compile, and the cause is the derivation rule.

(My probe script labelled these "MISCOMPILE" on a naive string compare of perl's
output against lli's stderr. They are lowering failures, not wrong answers. The
distinction matters: GAP-not-miscompile is the project invariant and it HELD.)


perigrin:

> `Add => 'join'` may work fine but it's genuinely incorrect in a way that
> causes confusion *because* it works sometimes.

`Add` has a known signature; its result type should come from that, and an
untyped operand should be a COERCION question, not an unanswerable result type.
Instead `Add => 'join'` derives the result from the operands and bails when one
is untyped (`:1539`).

It is right by coincidence on the common path (`join(Int,Int) = Int` equals the
signature answer) and diverges where it matters:

    Int + Str    join = Str      but perl's + is numeric -> Num
    Bool + Int   join = undef    off-chain, when the answer is Int

Note `Divide => 'Num'`, `Concat => 'Str'`, `Modulo => 'Int'` in the same table
ARE signatures. `Add` is the odd one out.

**But there is no signature to switch to.** `Add` is absent from
`%IR_OP_SOURCE_NAME` (`TypeLibrary.pm:382`), which maps IR node -> perl source
name so the signature tables can be reached. The map covers string ops and
`Length`; arithmetic `+` is not there. And the map is operand-only --
`operand_repr_for_ir_op` exists, there is no result-type accessor, even though
`%BUILTIN_SIGNATURES` entries carry `return_type`.

**THE PATTERN ALREADY WORKS ONE ROW OVER.** perigrin: `2 + $s` should have
produced a `Coerce($s -> Int)`. It should, and the machinery to do it is built,
shipped, and firing today -- for `Concat`, which IS mapped:

    my $n = 5; print "x" . $n, "\n";

    Constant  Str  value=x
    Constant  Int  value=5
    Coerce    Str  from_repr=Int to_repr=Str    <- signature says Str, so coerce
    Concat    Str                               <- result STATED, not joined

`_required_operand_repr($op,$position)` + `_insert_str_coercions`
(Serialize/JSON.pm:971-986) do exactly this: look up the required operand type,
compare, insert a `Coerce` on mismatch. `Concat => '.'` is in
`%IR_OP_SOURCE_NAME` and `Concat => 'Str'` is in the result table, so both
halves work.

`Add` reaches neither -- it is absent from the map, so `operand_repr_for_ir_op`
returns undef ("no opinion") and no coercion is considered; and its result comes
from `'join'` instead of a signature.

So this is NOT a design call. It is wiring an existing mechanism to four more
operators. The only genuinely open question is narrow:

- `+`'s signature. Perl's `+` is numeric, and the table already commits to
  `Divide => 'Num'` and `Modulo => 'Int'`, so `(Num,Num) -> Num` is the
  consistent answer.
- whether `Int + Int -> Int` survives as a narrowing. Given 0a/0b, that is a
  LOWERING question (which machine type for a Num known to be integral), not a
  lattice one -- so it should not block the signature change.

A result-type accessor is still missing (`%BUILTIN_SIGNATURES` entries carry
`return_type`; nothing reads it for IR ops), but both tables already hold
literal result types for the fixed-result ops, so the signature change does not
depend on building one.

Keep `double` OUT of this decision -- see the frame above. That was my error and
it is what turned a lattice question into a backend-cost argument.

**A smaller, independent improvement.** `%IR_OP_SOURCE_NAME` is an allowlist
where "deliberately excluded" and "never added" look identical. `BitAnd`/`Print`
have documented exclusion reasons; `Add` has no comment at all.
`ir_ops_with_signatures()` exists so a test can assert every ENTRY names a real
node type -- there is no guard in the other direction. A test that enumerates
arithmetic node types and asserts each is either mapped or documented-absent
would make `Add`'s status legible without deciding `+`'s result type.

## 3. `PadAccess` leaks perl's implementation; cross-sub lexicals stop being SSA

Same scope -- already pure SSA, no slot anywhere:

    my $d = 41; my $e = $d + 1;
      -> Constant(41) :Int, Constant(1) :Int, Add :Int      NO PadAccess

Across subs:

    my $d = 41; sub g { $d + 1 }
      main::g:  PadAccess targ=1 varname=$d   stamp=<ABSENT>
      main::__PROGRAM__:  no node for `my $d = 41` AT ALL

The store is not in another graph -- it is nowhere on the wire. And `targ` is a
pad INDEX, meaningful only relative to one CV's pad, so it does not even name a
unique cell across graphs. Two different subs both have a `targ=1`.

Fails as a GAP (the invariant holds), but the message is:

    Add node has no representation at lowering time.
    Fix TypeInference to annotate this node (G.6/F7).

It blames TypeInference for a node whose type is knowable, when the real defect
is a scoping bug three levels away. Exactly the misdirection
`2026-08-21-unknown-is-a-type-absence-is-not.md` predicted for `_require_repr`:
it names a PHASE rather than the operation that needed a type.

**This is filed already** as H13 ("the cross-sub drop is a SCOPING bug,
validated"). The framing that matters: lexicals are ALREADY SSA values, and
`PadAccess` appears only where def and use land in different graphs. The
question is not "how do we model closures" -- it is why a cross-sub lexical
stops being an SSA value, and that is a consequence of per-sub graphs, which is
a Chalk representation choice.

---

## Retractions

**"Closures are not represented anywhere."** Wrong frame. Lexicals are already
SSA values (measured above); `PadAccess` is a perl-implementation leak, not a
missing feature. I spent several turns reasoning about pad slots, `targ`
indices and closure records -- all of which are how perl implements lexicals,
none of which is what a lexical means.

**"With the join fixed, `g` declares Int."** It does not. I asserted a causal
chain across the repo boundary without tracing it. `return_type` is stamped at
the PRODUCER from `->stamp->type`; `_join_repr` is a chalk LOADER function and
never runs on that path. The actual blocker is finding 1.

**"`Num` is a lowering commitment (`double`)."** `Num` is a Chalk type. `double`
is an LLVM type. Conflating them is what made me argue a lattice decision on
backend-cost grounds.

Also worth recording: I twice dumped wire nodes using GUESSED JSON field names
(`{fields}{repr}`, `{repr}`) and read `repr=-` off every node. The real key is
top-level `stamp`. The first dump went into a report before I checked; the
second I checked first. The producer's vocabulary is `stamp`, the chalk side's
is `representation`, and reading the wrong one returns undef everywhere --
which looks exactly like "nothing is typed".

## What is NOT established

- 0a's mechanism. `Add` diverges and its two siblings do not; why is unknown.
- Whether the value-facts needed by 0a/0b belong in the lattice, a separate
  analysis, or a node annotation. Undesigned.
- Finding 1's input order `(cond, then, else)` is verified on one case.
- Nothing here is fixed. Corpus gate is 214 across four legs at time of writing,
  with the two return-type commits landed and none of these findings addressed.
