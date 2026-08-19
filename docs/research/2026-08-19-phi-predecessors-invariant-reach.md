# The predecessors invariant reaches the corpus, and nothing else. Measured.

**Date:** 2026-08-19
**Status:** MEASURED. One commit (`a9d11af2`) landed; the follow-on work it was
supposed to unblock DOES NOT EXIST.
**Question:** having landed the pairing invariant, update the "20 mechanical
sites" so the field becomes load-bearing.
**Answer: there are no such sites to update.** The estimate was built on a
category error.

## What I predicted, and why it was wrong

Classifying 63 Phi construction sites by grep, I reported: 26 loop (exempt), 32
merge, of which **20 mechanical** (>=2 Projs already in scope, so a one-line
add) and 12 branchless (nothing to name). Estimated half a day.

The classifier asked **"does this file construct Projs?"**. The question that
decides the work is **"does this file RUN TypedInvariant?"** Those are different
questions and I measured the easy one.

## The measurement

Files referencing `TypedInvariant` anywhere in `lib/` or `t/`:

| file | role |
|---|---|
| `t/bootstrap/corpus/son-corpus-wide.t` | the corpus gate |
| `t/bootstrap/corpus/mdtest.t` | corpus |
| `t/bootstrap/corpus/mdtest-constructive-builder.t` | corpus |
| `t/lib/.../MdtestCorpus.pm` | corpus harness |
| `t/lib/.../Mode2Adapter.pm`, `ProgramRunner.pm` | corpus harness |
| `t/bootstrap/ir/typed-invariant-*.t` (3) | the invariant's own tests |
| `t/bootstrap/ir/well-typed-graph.t` | the invariant's own tests |
| `lib/.../TypeLibrary.pm` | a comment |

**Of the 19 merge-Phi sites I planned to edit, ZERO run the invariant.** They are
LLVM-lowering tests and node-construction unit tests. Adding `predecessors` to
them would be unverifiable decoration: no assertion would fail if it were wrong,
absent, or mis-paired.

Confirmed by running all 8 non-`ir/` files carrying merge sites after the
invariant landed: `Files=8, Tests=192 ... Result: PASS`. Nothing flagged,
because nothing looked.

## Where the check DOES bite

The corpus, and only the corpus. Verified by building a graph through the real
`MdtestCorpus->build_graph_from_ir` in real corpus syntax with an `If` ->
two `Proj` -> `Region` merge:

```
Phi records no predecessors, but every control input of its Region Region#5
resolves to a Proj; a merge over named arms must say which value comes from
which arm
```

Flagged. So the invariant is live where graphs are *specified*, which is the
right place — a corpus case is a triple contract, and this makes arm pairing
part of it.

## Why it flagged nothing in today's 196 cases

There are 33 `= Phi(` lines across `t/corpus/mdtest/*.md`, and **every one that
reaches lowering is a LOOP Phi** (`Phi(%rn0, region: %loop)`) — structurally
exempt, since a loop Phi's values pair with entry/back edges rather than merge
arms. The 32 in control-flow.md sit in GAP-declared cases the harness `pass()`es
without running.

This is the `2026-08-19-phi-search-fallback-audit.md` finding from the other
side: that audit measured ONE corpus SEARCH hit; this measures why there is
exactly one — the corpus barely specifies merge Phis at all.

## What this actually says

The invariant is **correct and live but currently unexercised** — green because
the corpus does not yet contain the shape it polices, not because the shape is
sound everywhere. That is the vacuous-coverage pattern this project keeps
rediscovering, caught this time before it was mistaken for a passing contract.

It also connects directly to
`2026-08-19-corpus-node-coverage-measured.md`: 34 of 80 node types have zero
corpus coverage. A merge Phi over named arms is now one more shape the corpus
should specify and does not.

## The honest next step

**Not** "update 19 sites." Add corpus cases whose `ir` blocks specify a branch
merge with recorded predecessors — which exercises the invariant, closes part of
the node-coverage gap, and pins arm pairing behaviourally against perl, all in
the same case. The three `t/bootstrap/ir/typed-invariant-*.t` files already
cover the invariant's own logic; what is missing is a real program that depends
on it.

## Method note

Two grep-derived numbers in a row turned out to answer a question adjacent to the
one that mattered — first counting corpus USAGE and reporting it as format
CAPABILITY, now counting Proj CONSTRUCTION and reporting it as invariant REACH.
Both times the number was accurate and the inference was not. Before estimating
work from a count, state which question the count answers.
