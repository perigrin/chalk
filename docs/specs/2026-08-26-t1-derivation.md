# How the T1 requirements were arrived at

**Date:** 2026-08-26
**Status:** HISTORY. The contract itself is
`docs/specs/2026-08-26-t1-type-inference-requirements.md`. This file exists so
that document can be read as requirements rather than as a transcript.

Kept because the reasoning is reusable and several conclusions are only
defensible with the evidence attached — not because the narrative earns space
in a spec a builder reads.

## The failed split, and what it does NOT establish

I attempted the loader/T1 split by deleting `from_json`'s call to
`Chalk::IR::Analysis` and changing its return shape. The corpus gate fell
**218 → 136** (83 failures: 78 naming `Unknown`, 96 unblessed-reference from
the MOP return-shape change). Reverted whole; gate restored.

**The cause was not a bug in the edit — there was no T1 to split to.** What
exists is the same eleven passes with their bodies relocated into one file
(`f92c6869`). Relocating code is not building a transformation, and I let the
two read as the same thing: perigrin chose "build T1 as a class first, wire it
after", I agreed, then committed a file move whose message described where T1's
body *would* live. He had to ask directly whether T1 existed to find out it did
not.

**Read the numbers as a FLOOR, not a design constraint.** Removing a phase that
eleven passes depend on, while changing nothing else, breaks what depended on
it. That is a fact about the current wiring; the goal is not to preserve the
current implementation. Three claims in an early draft over-read it, all
corrected:

- *"`%LOWERABLE_STAMP` stays until T2"* — it says only that TODAY'S backend
  cannot receive an un-narrowed type. The exit condition dissolves it.
- *"the MOP problem is a prerequisite"* — a prerequisite for the contract being
  true, not one forced by the breakage.
- *"prerequisites, in order"* — prerequisites for a T1 that INHERITS the current
  passes. A different T1 may dissolve rather than satisfy them.

## Corrections that shaped the contract

Each of these was a correction to something I had asserted or written:

| I had | correction |
|---|---|
| "assign types to an untyped graph" | T1 receives a PARTIALLY TYPED graph and narrows it |
| absent and `Unknown` as two exit failures | absence normalizes to `Unknown`; one condition |
| "not a different bug class" | absent IS a distinct bug class — in the FRONTEND |
| narrowing as a quality metric | narrowing is part of correctness |
| "control nodes carry no type" (flat) | they carry no type OF THEIR OWN but act as type guards |
| boxing listed beside GAP and guess | boxing is okay; incorrect lowering is not |
| `DefinedOrFold` filed under `Optimizer::` | correct by luck — the question was never asked |

The last one is the pattern: filing a required stage as optional is how the
inliner became the only call mechanism, already recorded as an architectural
error. T1 and T2 are correctness transforms.

## Measurements

Collected 2026-08-25/26. Each is a floor or a population count, not a target.

- **10 Value nodes** reach the end of the current pass sequence with no stamp:
  2 `Call`, 1 `Ref`, 7 downstream `Phi`. Corpus-wide (218 cases).
- **976 of ~1800 stamps** are `Unknown` on the wire, four-program sample.
- **16 stamps** differ across decode-then-re-encode, every one the loader
  overwriting what the wire sent — `Print` seeded `Boolean`,
  `Subscript`/`Call`/`Add` narrowed from `Unknown`. That is the size of the T1
  split, measured by `t/bootstrap/ir/loader-reproduces-the-wire.t`.
- **218 → 136** on removing `%LOWERABLE_STAMP` alone.

An earlier census reported `Phi 21, ArgsSource 18, PadAccess 12, Call 6, Ref 3`
and was **wrong** — it loaded producer internals (`B::GV::SAFENAME`,
`Exporter::Heavy`) alongside the program under test. Scoped the way the corpus
gate scopes, it is the 10 above. A sample not scoped like the gate misleads in
whichever direction it happens to be unrepresentative; that error was made
twice.

## Producer bugs found by accident

Evidence for "a frontend stamp is EVIDENCE, not an axiom" — all three surfaced
while looking for something else:

- `@_` stamped `Unknown` because nothing ever asked (fixed, perl5-son
  `714ec0e`);
- aggregate signature parameters left unstamped because a comment described a
  die that had stopped happening (fixed, `86d7f73`);
- an ADJUST block dropped from the wire entirely by a bare `eval` (fixed, same
  commit — the eval also hid a live `CORE::chr` translator bug).

## The refinement research

Question: where does a branch-established refinement live? Researched against
primary sources rather than memory, after two same-day errors from recall
(`join_types` existing; the producer's lattice "lacking" `Array`/`Hash`).

| system | where refinement lives |
|---|---|
| Graal | `PiNode` — value node with a guard input |
| HotSpot C2 | `ConstraintCast` family — value node, control edge `in(0)` |
| V8 TurboFan | `TypeGuard` — `kPure` yet takes a control input |
| V8 Turboshaft | block-keyed side table — abandoned floating nodes to do it |
| TypeScript, Kotlin, mypy, C# | recomputed on demand over a CFG |

**The dividing line is whether the IR floats**, not language or paradigm.
TypeScript's on-demand model is explicitly motivated by IDE laziness, which a
batch compiler does not need, and its documented cost is exponential re-walking
patched by three cache tiers plus a bailout Hejlsberg describes as trading
correctness for speed.

Unconfirmed and stated as such: Graal's VMIL 2013 paper (closed access), Click's
1995 paper and thesis (hosts 403/404). The APPLC 2013 "Graal IR" paper is
confirmed **not** a source for `PiNode` — zero occurrences of the term.

## Serialization

`to_json` never emitted a `stamp` field, so every type a graph carried was
dropped at serialization (`2b5dfe2e`). Found by round-tripping producer wire and
predicting the wrong direction — I expected the loader to ADD stamps; every
observed difference was the reverse.

It matters beyond testing: `to_json` is the self-hosting output path, and there
is a planned bootstrap step where B::SoN parses Chalk itself. A serializer that
drops types means chalk cannot hand a typed graph to a future chalk.
