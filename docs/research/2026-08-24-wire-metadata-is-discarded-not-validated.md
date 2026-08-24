# The loader rebuilds what the wire already sent, instead of validating it

**Date:** 2026-08-24
**Status:** MEASURED. No defect found today — the two derivations agree
everywhere they both have an answer. Filed because the ARCHITECTURE is wrong
in a way that currently costs only work, and the producer's own code says so.
**Origin:** perigrin, on being told the loader runs a fixpoint to derive return
types: *"This sounds like we're not serializing the graph intelligently?"* and
then, decisively:

> Having a pass to validate / update the values that ship across the wire is
> very different from throwing all of the data sent across the wire out and
> building it from scratch.

## The wire is fine. The consumer is the problem.

The wire carries per-sub metadata under `classes->{PKG}{subs}{NAME}`, measured:

    sub f: graph=main::f, name=f, params=ARRAY, return_type=Int,
           signature=HASH, uses_args=JSON::PP::Boolean

`return_type` is computed by the producer at IR-construction time
(`B/SoN.pm:688`, `_graph_return_type`). The comment above it states the intent
exactly, and names the failure mode this document is about:

> DECLARED HERE, at IR construction, for the same reason uses_args is: this
> walk built the Return and knows its value node. **Re-deriving it downstream by
> walking the graph is the recovery-by-scanning the metadata channel exists to
> retire.**

And on why `Unknown` is SENT rather than the field omitted:

> `Unknown` when the value carries no stamp yet — a recursive call has nothing
> to read at this point. **NOT omitted: an absent field is not a type, and it
> forces every consumer to invent a meaning.**

That is the same absence-vs-value principle applied to `stamp` this morning
(`2026-08-23-goto-silently-dropped.md`). The producer applied it deliberately.

**Chalk's loader then invents its own meaning anyway.** `_stamp_method_call_reprs`
(`IR/Serialize/JSON.pm:1886`) rebuilds `class::method -> return_repr` from
scratch by walking each method graph to its `Return` and reading the value's
representation. It does not consult `return_type` at all. The only place chalk
reads that field is `:1286`, where it is stored as `MOP::Sub` metadata and not
used for typing.

## Measured: they never disagree

Fifteen subs across fourteen programs, comparing the wire's `return_type`
against what the loader derives:

    PROGRAM     SUB   WIRE       LOADER     VERDICT
    int         f     Int        Int        agree
    str         f     Str        Str        agree
    num         f     Num        Num        agree
    arg         f     Unknown    Int        loader better
    chained     f     Unknown    Int        loader better
    chained     g     Unknown    Int        loader better
    bool        f     Boolean    Boolean    agree
    concat      f     Str        Str        agree
    ternary     f     Int        Int        agree
    aggregate   f     ArrayRef   ArrayRef   agree
    effect      f     Int        Int        agree
    recursive   f     Unknown    Int        loader better
    divide      f     Num        Num        agree
    length      f     Int        Int        agree
    undef       f     Undef      Undef      agree

    agree          11
    loader better   4

**Zero disagreements.** Eleven agree exactly, including the cases most likely
to diverge: `Boolean` (a distinct lattice member), `Num` from a division,
`ArrayRef` (an aggregate), and `Undef` (the absence-vs-value case).

The four `Unknown`-on-the-wire cases are exactly the ones where the producer
genuinely cannot know: three take arguments (`arg`, `chained` ×2) and one is
`recursive`. In all four the producer works sub-by-sub and the answer depends
on a caller. That is the honest division of labour, correctly reported — the
producer says `Unknown` rather than guessing, and the loader, which has the
whole program, does better.

**So the wire is right wherever it commits, and abstains precisely where it
should.**

**So this is not a latent bug today.** It is redundant work with no
reconciliation.

## Why it still matters

The distinction perigrin drew is architectural, not stylistic:

| design | behaviour | catches a producer bug? |
|---|---|---|
| **validate / update** | seed from the wire, refine where `Unknown`, FLAG disagreement | yes, loudly |
| **discard / rebuild** | ignore the wire, derive from the graph | no — divergence is silent |

Chalk does the second. Nothing compares the two answers, so if they ever DID
diverge — a producer bug, a wire-format change, a lattice edit landing on one
side — the backend would consume one answer while the metadata channel carried
another, and no test would notice. The measurement above had to be written by
hand to discover they currently agree.

**And it explains the fixpoint.** The loader iterates
(`IR/Serialize/JSON.pm:871`, `:881`) because it asks a whole-program question:
a caller's type depends on its callee's, so it loops until nothing changes. The
producer already broke that cycle by answering per-sub at build time. Chalk
recreates the cycle by discarding the answers.

## What this changes about the open question

`docs/architecture/ir-and-lowering.md` lists as OPEN: *"whether the loader's
existing iterate-to-fixpoint representation-seeding survives, or moves into the
pass."* That framing assumed the fixpoint is necessary work in the wrong place.

The measurement narrows it. The fixpoint is:

- **mostly redundant** — 11 of 15 answers were already on the wire, correct;
- **partly real** — the 4 `Unknown` cases (3 arg-taking, 1 recursive) need
  whole-program context the producer does not have;
- **entirely unreconciled** — no comparison, in either direction.

So the target shape is not "move the fixpoint" but **seed from the wire, iterate
only over what is still `Unknown`, and assert on disagreement.** That is
strictly less work than today AND turns a silent divergence into a loud one.

## Not established

- Whether the agreement holds beyond these 15 shapes. METHODS ON CLASSES are
  the notable gap — every sub measured here is a plain `main::` sub, and
  `_stamp_method_call_reprs` (the function that motivated this) is specifically
  about methods. Also unmeasured: subs returning a `tie`d container's element,
  and mutually-recursive subs (only self-recursion was tested).
- Whether `uses_args`, `params` and `signature` — the other wire metadata
  fields — are consumed or likewise rebuilt. Only `return_type` was measured.
- Whether any consumer other than the LLVM target reads the loader's derived
  reprs, which would widen the blast radius of a divergence.
