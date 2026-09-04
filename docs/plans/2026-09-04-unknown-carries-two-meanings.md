# `Unknown` is an honest top now, and the comments have not caught up

**Date:** 2026-09-04
**Status:** MEASURED. Supersedes this file's own first draft, which argued from
stale comments.
**Trigger:** perigrin, on the RuntimeRep research — *"If RuntimeRep allows us to
handle Unknowns then I retract all my statements about Unknown being an
inference failure"* — and then, on being shown `Analysis.pm:683`: *"Not
actually exactly true anymore."*

## The correction

This document's first draft said the retraction was unwarranted, on the
strength of two comments:

- `Analysis.pm:683` — "`Unknown` is how the producer says it could not type a
  value; a present answer that answers nothing"
- `Context.pm:2444` — "an inference failure that got this far"

**Both describe the world before this session's `94316971`**, and quoting them
as current was the error. The live contract is stated in the loader, in the
code that commit changed:

> **`Unknown` IS A TYPE AND MUST BE CARRIED**, even though it is not lowerable.
> ... Dropping it turns a node the producer typed `Unknown` ("inference ran and
> could not decide") into a node with NO stamp ("inference never reached
> this"), which are different claims. ... every Value node carries a stamp
> after T1, with `Unknown` as the honest answer where nothing could be derived.
> — `Serialize/JSON.pm:727`

So there are THREE states, and the first is being whittled away from both ends
(perigrin, 2026-09-04) — at the producer and at T1:

| state | meaning | today |
|---|---|---|
| absent | inference never reached this | **gone for value nodes**; survives only on control nodes |
| `Unknown` | inference ran; no narrower answer available | carried; a real lattice member |
| narrowed | committed to a representation | `_is_narrowed` true |

**Measured over all 257 corpus source blocks**, run through the pinned producer
and loaded (`scratchpad/t1gap2.pl`; 255 loaded, 2 failed to parse):

    files 255   graphs 309   nodes 3231

    nodes with NO stamp after load:
      Node /Start      309 of 309       Node /MemStart   41 of 41
      Node /Return     309 of 309       Node /If         34 of 34
      Node /Region      73 of  73       Node /Loop       25 of 25
      Node /Proj        66 of  66       Node /Unwind      5 of  5

**Zero `Value/*` rows.** Every surviving absence is a `Node/` — a control
construct that denotes no value, so having no stamp is the correct state rather
than a gap. `Print` does not appear because the producer stamps all 311 of them.

The `Proj` rows are not an exception. Checked across the same corpus: all 147
`Proj` nodes on the wire project from `If` (99) or `Loop` (48) — they are CFG
body-entry edges, never value extractions — so unstamped is right for them too.

That said, the invariant's guard is `$node isa Chalk::IR::Value`, and this
session established that `Print`, `Proj`, `VarDecl` and `ListAssign` are
`:isa(Chalk::IR::Node)` DIRECTLY — siblings of Value, not subclasses (see
commit `0cc04737`, where a coercion guard asking the class question instead of
the stamp question shipped a miscompile). So the invariant does not currently
COVER the four node kinds that can produce a value without descending from
Value. It happens to hold for them on this corpus because the producer stamps
`Print` and the others are control-only here. That is a measured coincidence,
not a guarantee.

## The decisive evidence: `Unknown` is grouped with `Scalar`

```perl
sub _is_narrowed ($repr) {
    return false if !defined $repr;
    return false if $repr eq 'Unknown' || $repr eq 'Scalar';
    return true;
}
```

`Analysis.pm`. The predicate consumers actually ask does not partition
"failure" from "success" — it partitions **un-narrowed from narrowed**, and it
puts `Unknown` on the same side as `Scalar`. `Scalar` is unambiguously a
legitimate static type (it is the top of the scalar spine and encodes as
`%Slot`). Treating `Unknown` as its sibling is treating it as an honest top.

`Unknown` also has five real children with no common ancestor below the root —
`List`, `Code`, `Glob`, `IO`, `Format` — and the join walks to it as a genuine
least upper bound:

    join(Code, Glob)   = Unknown      <- least common ancestor, a REAL answer
    join(IO, Format)   = Unknown      <- same
    join(Unknown, Int) = Unknown      <- absorb
    join(Int, Num)     = Num          <- ordinary lub

## So: does RuntimeRep apply?

**Partly, and the part it does not cover is the interesting one.**

GHC's `RuntimeRep` describes a value that is legitimately typed but whose
machine representation is not yet chosen, with **defaulting** supplying one
before code generation. That is a real match for `Unknown`-as-honest-top and
for `Scalar`: both are types, neither has committed to an encoding.

What RuntimeRep does NOT give us is the distinction the compiler still needs at
emission. A node stamped `Unknown` may be:

1. `Code` joined with `Glob` — a correct, informative answer that genuinely has
   no narrower type; or
2. a node nothing could type, where the honest fix is upstream.

Both are legitimately "typed, representation unchosen" in RuntimeRep's sense.
But (1) is *finished* and (2) is *evidence of a gap elsewhere*, and
`Context.pm:2444` renders both as `""` while calling them inference failures.
For (1) that comment is now wrong; for (2) it is still the right diagnosis.

**The distinction that matters is therefore not "type vs failure" — it is
"narrowed vs not", which the code already has, plus "is anything still expected
to narrow this?", which it does not.**

## What is genuinely missing

The third concept, and it has no name:

**typed fine, representation unchosen, AND a choice still pending** — `Num`
that may be `i64` or `double` until something observes it. T2 records this as a
candidate set (`Num => ['double','i64']`) in a pass that is not wired into
lowering, and `%_REPR_LLVM_TYPE` collapses it to `double` before any constraint
is seen. That premature collapse is the 2^53 miscompile
(`t/corpus/mdtest/arithmetic.md`, commit `b7486a7f`).

This is exactly what RuntimeRep is for, and it is the piece worth stealing:
a representation variable that stays open, is constrained by observations, and
is **defaulted** if nothing constrains it. `Unknown` and `Scalar` are already
un-narrowed types; what is absent is a *pending representation choice* with a
defaulting rule.

## The backend already says this, and already did the measurement

Found after drafting the above, in `%_REPR_NO_MACHINE_TYPE`
(`Target/LLVM/Context.pm`) — the refusal entry states the position better than
any comment quoted earlier in this file:

> `'Unknown'` is the lattice TOP: this value may be anything, so no machine
> type can hold it. **That is an answer, not necessarily a failure** — but the
> program cannot be compiled until something NARROWS it: a producer stamp, a
> flow refinement, or a callsite. If no such information exists, this construct
> is legitimately un-compilable and the GAP is correct.

That is the honest-top reading, in production, with the narrowing requirement
attached. It also distinguishes `Unknown` from `Scalar` on the right axis:
"Scalar is absent from THIS target's map and an SV*-based target would have it;
Unknown is absent from EVERY target's map, permanently."

**And it settles the question this document listed as unestablished.** The same
comment records an exhaustive measurement over all 26 `%PARENT` members:

> 180 ordered pairs join to Unknown with neither operand Unknown, and EVERY ONE
> involves Code, Glob, IO or Format (48 appearances each; every other type
> appears only when paired with one of those four).

So route (1) — reaching `Unknown` as a genuine least upper bound rather than by
absorption — is not hypothetical; it is 180 pairs, all of them a callable or a
symbol-table slot joined with a value. The comment's own reading of that case:
"a program-level error rather than an imprecision."

Note also that an earlier version of THAT comment claimed nothing climbs to
`Unknown`, "from a sample that happened to omit the four types it is true of."
The same shape of error as this document's first draft. The fix in both cases
was to enumerate rather than sample.

## Stale comments to fix when touching these files

Not fixed here — flagged so the next reader does not re-derive this document:

- `Analysis.pm:683` — "a present answer that answers nothing" predates the
  carry-`Unknown` invariant.
- `Context.pm:2434` — "Scalar is a legitimate static answer, Unknown is an
  inference failure" draws a line `_is_narrowed` does not draw.
- `Context.pm:2444` — "an inference failure that got this far" is right for
  case (2) and wrong for case (1).

## What is NOT established

- Whether any real program produces `Unknown` via route (1). The LATTICE
  question is settled (180 pairs, measured exhaustively, all involving
  Code/Glob/IO/Format). What is still unmeasured is whether a corpus case or
  lib/ file actually constructs such a join — the backend comment reads that
  case as "a program-level error rather than an imprecision", which if right
  means it SHOULD be rare in valid code.
- Whether (1) and (2) need distinct names at all, given that `_is_narrowed`
  already asks the question consumers care about.
- What the pending-representation concept should be called, and whether it is a
  stamp value or a separate field. The
  `[[t1_t2_split_and_bidirectional_inference]]` note says `Unknown` at T1 is a
  failure rather than an honest top — **that note is now contradicted by the
  loader contract and should be updated.**
