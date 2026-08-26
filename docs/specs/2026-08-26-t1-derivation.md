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

The design details each system justifies, which spec §5 states as bare rules:

- **the guard is a position, not a condition object** — Graal's `GuardingNode`
  is a marker interface with ZERO methods.
- **never fold the narrow stamp back onto the guarded input** — a Pi is *"only
  true at this point in the control flow"*; Graal permits the fold only under
  `guard == null && !hasMoreThanOneUsage()`, i.e. exactly when it was not
  flow-sensitive after all.
- **`_floating` and `_narrows_type` are two independent bits** — C2 collapsed
  them and an array access floated above its range check.
- **the frontend creates the Pi** — Graal's main producer is the bytecode
  parser, not a later analysis: it is the phase that sees the guard as syntax.
- **a Pi must not reach the backend** — Graal's `FixReadsPhase` is that same
  boundary.

Prior art for `remove(σ, Undef)` specifically: Tobin-Hochstadt & Felleisen's
occurrence typing (POPL 2008, ICFP 2010), which names **Perl** as a motivating
language. Nullability narrowing is the base case there, not a special case.

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

## Why absorb, in full

The contract states the rule (spec §10); this is the argument, which took two
corrections to get right.

`join(Unknown, T)` is `Unknown` — what `join_types` already does. `_join_repr`
DROPS the `Unknown` arm and joins the rest, and the loader depends on that.

```perl
my $v;
if ($c) { $v = f() }   # f's return type not yet resolved -> Unknown
else    { $v = 2 }     # Int
```

**First version of the argument, too weak:** drop "guesses ahead of the
fixpoint" — true, but it presupposes there IS an iteration and that `f`
eventually resolves.

**The decisive argument, from perigrin:** drop is sound only if `f`'s type is
already known at the join — only if `f` is defined and analysed before its use.
Perl does not work that way: forward references, mutual recursion, `@ISA`
resolution, a sub defined below its caller. So drop is either unsound, or it
imposes a declaration-order constraint the language does not have.

That inverts what the fixpoint IS. Since use-before-definition is legal, no
single ordered pass can type everything — iteration is FORCED BY THE LANGUAGE
rather than chosen. And absorb is what makes it work:

- **Absorb** yields `Unknown` — a sound intermediate a later round sharpens.
- **Drop** yields `Int` — an unsound one later rounds have no reason to
  revisit, because it looks resolved. The same error as the reverted `Slot`-arm
  drop: committing before the evidence is in, and SELF-CONCEALING where
  `Unknown` would have advertised that work remained.

The poison-spreading objection to absorb is just non-convergence: run to
fixpoint, and a surviving `Unknown` means `f` genuinely could not be resolved,
which the exit condition reports at the arm that actually failed.

## The graph set that is not in the architecture

An early draft of §2 took `run(\%graphs, $classes)` as the entry contract,
because the loader returns a hash of graphs and every consumer takes one.
perigrin rejected it: the program-as-graph-set is a misalignment with how SoN
implementations actually work.

Graal is the reference shape — a `StructuredGraph` PER METHOD, with inlining
pulling the callee in *through* the call node rather than iterating a map. The
hash is the wire's `methods` section, i.e. transport. Modelling transport as
architecture is what made the one-graph contract look impossible, and the fix
is that inter-unit references are EDGES (spec §2, §6).
