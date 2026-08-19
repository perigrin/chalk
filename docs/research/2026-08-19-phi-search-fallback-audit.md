# Audit: the Region search is NOT dead. Measured, not reasoned.

**Date:** 2026-08-19
**Status:** MEASURED. No code changed — the instrumentation was temporary and
is removed. Both repos clean.
**Question:** can `_phi_slot_for_proj` / `_proj_index_of_control` be deleted now
that producers supply `predecessors`?
**Answer: no.** Not yet, and the reason is not the one I predicted.

## Method

Instrumented the single decision site (`Context.pm:3613`) to log FIELD when the
Phi supplied predecessors and SEARCH when it fell back, then ran the real
suites. Counting actual hits rather than reasoning about callers — the
prediction I was about to act on ("dead for producer-built graphs") was wrong
in a way no amount of caller-reading would have shown.

## Results

| suite | FIELD | SEARCH |
|---|---|---|
| corpus gate (`son-corpus-wide.t`, 196 cases) | 1 | **1** |
| IR tier (`t/bootstrap/ir`, 79 files) | 0 | **10** |

**11 SEARCH hits across the two gates.** The fallback is load-bearing.

## Where they come from

**The IR tier's 10 are hand-built test graphs.** Expected: those construct Phis
directly via `NodeFactory->make('Phi', ...)` and none passes `predecessors`.
Deleting the search would break them, and they are testing the backend, not the
producer.

**The corpus gate's 1 is the finding.** It is NOT producer output — it comes
from a hand-written `ir` block. `MdtestCorpus.pm:490` builds corpus Phis with
`make('Phi', region => $region, values => \@inputs, %attrs)` and no
predecessors, so every lowered corpus spec containing a Phi takes the search
path.

There are 33 `= Phi(` lines across `t/corpus/mdtest/*.md` (32 in
control-flow.md, 1 in logical.md) but only ONE reaches lowering — the rest sit
in GAP-declared cases, which the harness `pass()`es without running. That is
the gate blind spot recorded in
`docs/plans/2026-08-03-effect-chain-followups.md` Part D1, visible here from a
new angle: a corpus spec's IR shape is only exercised when its case actually
lowers.

## What this means

The plan "producers supply predecessors, then delete the search" was
incomplete. There are THREE Phi sources, not two:

1. **perl5-son** — supplies predecessors (`ef019a0`, `1752b9d`)
2. **the parser-driven frontend** — builds only loop Phis
   (`Bootstrap/Bindings.pm:119`), which are exempt by design
3. **hand-written graphs** — corpus `ir` blocks and IR-tier tests. **Supply
   nothing, and there are 11 live.**

Source 3 is the one I missed. It is not a migration target in the usual sense:
a corpus `ir` block is a SPEC, written to describe a shape, and requiring every
one to carry predecessor wiring would make specs harder to write for a benefit
the spec itself does not need.

## Options, none taken

- **A. Teach `MdtestCorpus` to infer predecessors** when a spec's Region inputs
  resolve to Projs — the same `arm_proj` walk, done once at corpus-build time.
  Removes the corpus hit; leaves the IR tier's 10.
- **B. Keep the fallback permanently** and document it as the hand-built-graph
  path rather than a migration remnant. Honest, and costs one function that is
  now correct (`9ce43cdd` fixed it) and exercised.
- **C. Require predecessors on every merge Phi** and update all 11 sites. Makes
  the field load-bearing, which strengthens the invariant — a merge Phi could
  then be REQUIRED to carry them, catching a producer that forgets. Most work.

**B is the honest default** and A is cheap if the corpus hit is worth removing.
C is the only one that lets `TypedInvariant` police pairing rather than just
arity, which is the half it currently cannot check.

## Method note

I was one command from deleting a function that 11 live call paths depend on.
The prediction — "dead for producer-built graphs" — was TRUE and irrelevant:
the graphs that still use it are not producer-built, and I had said as much in
`a328d7d1`'s message ("hand-built test graphs and the parser-driven frontend
still reach it") without measuring how many or noticing the corpus was among
them.

Stating a caveat is not the same as measuring it.
