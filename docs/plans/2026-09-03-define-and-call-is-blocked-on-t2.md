# Real `define` + `call` works, and is blocked on T2 three separate ways

**Date:** 2026-09-03
**Status:** MEASURED. Mechanism built and demonstrated; NOT committed, gate red.
**Source:** conversation with perigrin, 2026-09-03
**The code:** `docs/plans/wip/2026-09-03-define-and-call.patch` — the working
tree as measured below, against `0f0dcc12`. Applying it reproduces gate 218
exactly; it is kept because the mechanism is right and only its dependency is
missing, so this is a starting point rather than an archive.

## What was built

Real LLVM function emission for named subs, replacing the inliner as the call
mechanism rather than falling back to it. perigrin, setting the direction:

> the inliner was a premature optimization that caused us to never build the
> _actual_ solution ... this is the time to build the _actual_ solution

The mechanism works. Verified end to end against perl, with `lli`:

| source | perl | chalk |
|---|---|---|
| `sub twice($n) { $n * 2 }; print twice(21)` | `42` | `42` |
| `sub diff($a,$b) { $a - $b }; print diff(10,3)` | `7` | `7` (not `-7`) |
| `sub noisy() { print "x"; 1 }` called twice | `xx` | `xx` |

The third row matters most: ONE define, TWO calls, body runs exactly twice.
That is the duplication trap that made the previous attempt at this change move
the gate 214 -> 207 (corpus F9/F10/F11/F13 each printed their callee's output
twice). It is closed.

Pieces that are sound independent of anything below: the sub-define emission,
the parameter ABI, `_sub_symbol` as one authority for the symbol, and the
`_in_method_body` / `_in_function_body` split.

**That split is worth keeping in mind separately.** One flag was answering two
questions -- "does this have an invocant?" and "is this an emitted function
body?" -- and the conflation broke two unrelated things: a sub's Parameter
refused to lower, and module-scope string globals lost their uniqueness prefix
(two bodies both emitted `@str_const_0`; `ir/llvm-class-sub-define.t` had
predicted exactly that, "this is what step 5 must fix").

## Where it stands: gate 218, floor 220

Measured on the working tree against pinned producer b96087c:

    TOTAL: gate-green=218 behavior=219 shape=225 invariant=225 worklist=8

Against 224 before. All six regressions are in `subs`, and after the arity fix
below they all read the same way:

    F5  lli '' != perl '11'      F14 lli '' != perl '6'
    F6  lli '' != perl '99'      F15 lli '' != perl '4'
    F8  lli '' != perl '11'      F16 lli '' != perl '2 4'

Empty output, not wrong output: the calls emit correctly and the defines do not
exist, so nothing runs. That is the diagnosis confirming itself.

## The three blocked directions, all the same block

Every remaining step routes through the missing T2 functor. This is the part
worth recording, because each looks like a different problem.

### 1. A `sitofp`/`fptosi` round trip that should not exist

`sub twice($n) { $n * 2 }; print twice(21)` is integer arithmetic end to end.
Emitted:

    %tmp_2 = mul i64 %arg0, %tmp_1          <- i64 throughout
    %tmp_3 = sitofp i64 %tmp_2 to double    <- widen, to meet declared `Num`
    ret double %tmp_3
    %tmp_2 = call double @main__twice(...)
    %tmp_3 = fptosi double %tmp_2 to i64    <- and immediately narrow back

Right answer, lossy in principle: an integer above 2^53 comes back wrong. Two
locally-defensible decisions -- the return boundary widening to the declared
`Num`, the call site narrowing to the node's `Int` -- composing into work that
should not exist.

`2026-08-31-t2-is-a-narrowing-analysis.md` says what should happen instead:
`Num` maps to `{double, i64...}` chosen by "is it ever fractional?". Here it
never is, so the whole chain is `i64`, the define returns `i64`, and NEITHER
conversion is emitted. One decision made once, over the graph.

### 2. Nineteen sites deciding encoding one at a time

`_emit_coercion` now has 19 call sites in the backend. Each compares two CHALK
types and picks an encoding. The T2 doc names this failure mode by name:

> The alternative leaves the final step scattered across 8 backend call sites
> and unverifiable, which is exactly the shape that produced `bc943e3b` and
> `ebdd6a23`: consumers deciding encoding one site at a time.

It was 8 when that was written. Two of the current 19 were added by this work,
each with a comment arguing it was principled.

### 3. A body that cannot be typed without its caller

The define side of a `shift @_` sub is blocked outright. From the registry skip
that has been there since sub metadata landed:

> A callee that reads `@_` has no bound arguments OUTSIDE an inline, so its
> body root carries no repr and `_require_repr` below would refuse the WHOLE
> PROGRAM -- even when the sub is never called.

Under the inliner this resolved by substitution at the call site. With real
calls it has to resolve as inference. That is T2's job, arrived at from a third
direction.

## What IS derivable, and its ceiling

For a signature-less sub the arity is not on the wire -- `sub f { my $n = shift }`
and `sub lit { return (10,20,30) }` ship the SAME `kind=implicit` record holding
a slurpy `@_`, one taking an argument and one taking none. The signature cannot
tell them apart because neither has one.

It IS derivable from the body, and the inliner already does it:
`_collect_positional_arg_reads` returns the argument reads in positional order,
so their count is the arity. The call side now uses that and emits correctly.

**Known ceiling, and it is the collector's:** `shift @_` caps at ONE argument,
because multiple shifts hash-cons to a single node and lose their order.
`my ($a,$b) = @_` has the same limit. A two-argument `@_` sub therefore GAPs
rather than being mis-bound -- the honest outcome until arguments are a real
declared signature.

## One genuine limit of real calls, unrelated to T2

`sub lit { return (10,20,30) }` returns a `List`, which is signature vocabulary
denoting a SEQUENCE -- there is no single-value layout to name in a `call`
instruction. The inliner never met this because it substituted the list at the
call site.

Returning a list needs a calling convention for multiple return values (an
out-parameter, or a boxed aggregate). Currently GAPs with that reason.

## Recommendation

Do not land the call mechanism before T2. Not because it is wrong -- it
demonstrably works for the shapes that do not need inference -- but because
every remaining step is a decision T2 should be making, and making them in the
backend is precisely how the 19 sites accumulated.

The three directions above are a concrete first target list for the pass:

1. the `Num`-declared / `Int`-bodied sub, which should emit zero conversions
2. the 19 `_emit_coercion` sites, which should become zero
3. a `shift @_` body typed from its call sites rather than by substitution

## What is NOT established

- That the call mechanism is correct beyond the three shapes measured above.
  The corpus never exercised it; the gate went red before it could.
- That T2 alone unblocks the define side. Item 3 is a claim about where the
  answer belongs, not a proof that a narrowing pass produces it.
- Any number for how many corpus cases real calls would unblock once T2 exists.
  That was never measured, and the F3 design doc warns twice against ranking
  this work by GAP-site count.
