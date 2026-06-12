# Phase 4 Brief — B::SoN as the Trusted IR/MOP Producer

**Date:** 2026-06-12
**Status:** SCOPING BRIEF — the phase-shape decision the three-axis plan
deferred ("Scope DEFERRED until Phase 3 lands; the B::SoN phase shape is
decided then", `docs/plans/2026-06-06-three-axis-codegen-and-typed-ir-contract.md`).
Phase 3 has landed (typed-IR contract concrete, LLVM corner green on the
corpus, G1–G7 complete), so this decision is due.
**zhi:** 019eaa51 "Phase 4: B::SoN as trusted IR/MOP producer".
**Blocked by (all wired):** mdtest corpus (done), 019eb316 value-cache
family (done), 019eb6ff cache/identity follow-ups (OPEN — see Gate 0).

## What Phase 4 is

The capstone (Phase 5: lib/ through B::SoN → CodeGen == perl) needs an
IR-producer for real Perl input. It is NOT the Chalk parser/SemanticAction
(untrusted, paused); it is **B::SoN** (`perl -MO=SoN`, repo
`~/dev/perl5-son`): walk the optree perl actually compiled into Chalk's
IR/MOP. B::SoN is DIRECTIONAL — treated exactly as CodeGen was at Phase 3's
start: a sketch of the right shape, output suspect until proven. It earns
trust ONLY through the now-trusted instruments: B::SoN IR → verified
backend → run → compare to perl. A divergence is a B::SoN bug, never
trusted around. perl stays the sole oracle.

## The verification instrument (what "verified through harness" means now)

The mdtest corpus becomes a **triple contract**. Each case already carries:
the perl source (the input), the hand-authored ir block (the graph shape
spec), and the frozen behavior oracle. Phase 4 runs the SAME perl sources
through B::SoN and checks, per case:

1. **Behavior** — B::SoN graph → backend → run == the behavior oracle.
   The P corner (Target::Perl, schedule-driven) is the full-coverage
   corner; the L corner (Target::LLVM via `lower(mop => ...)`, lli) covers
   the runtime-free slice.
2. **Shape** — structural-subset match of the B::SoN graph against the
   case's ir block (the format's decided matching mode), the same way the
   constructive builder is checked today.
3. **Invariant** — the graph passes TypedInvariant.

Red is the work-list, not failure (gap-map discipline). The existing
instruments (`script/chalk-emit-son-json`, `t/bootstrap/son-compare.t`,
`t/bootstrap/cross-load-son-json.t`) are the starting point; son-compare's
per-sub TODO divergences are the pre-Phase-4 baseline to re-measure.

## Contracts B::SoN must now meet (all landed 2026-06-10..11; none existed in April)

- **Sealed MOP travels with the graph.** The backend reads class structure
  via `lower(mop => $sealed_mop)`; B::SoN must emit a `Chalk::MOP`
  (declare_class/field/method/adjust, then `seal`) — the MOP-emission gap
  the three-axis doc names. No metadata rides as node inputs.
- **`Call.class_name`** names the statically-known class (serialized;
  Serialize/JSON carries it both ways).
- **Statement-effect per-call identity** (`%STATEMENT_EFFECT_OPS`: Assign,
  CompoundAssign, RegexSubst, TryCatch, Call) — two textually-identical
  statement effects must be distinct nodes, control-threaded in statement
  order. If B::SoN constructs nodes through its own factory, its identity
  semantics must match Chalk's NodeFactory (per-call #N ids vs content
  hash-consing), or it must construct through Chalk's factory on load.
- **Method bodies are per-method graphs** whose lowering root (for the L
  corner) is exactly one Return. Real lib/ methods have early returns —
  multi-exit bodies are an EXPECTED L-corner gap-map entry, not a Phase 4
  blocker; the P corner emits them schedule-driven.
- **TypedInvariant**: representations on value nodes (the typed-IR
  contract); Coerce materialized on edges.

## Known B::SoN-side debts (recorded April 2026 — figures stale, re-audit first)

- FromOptree PadAccess targ bug (the noted method-level-comparison blocker).
- FromOptree fails on `feature class` method bodies — zero overlap for
  class files; drops field writes. (This + MOP emission = the class tier.)
- Node parity was "70 of 76" in April — STALE: the IR vocabulary has since
  gained the G4 aggregate nodes, RegexMatch/RegexSubst/RegexCapture,
  EnvRead, TryCatch, Coerce-as-node, and lost the 7 parallel G5 nodes (R3).
  The parity table must be re-derived from today's `%DATA_CLASSES`.

## Stages

- **4a — Re-audit the seam.** Re-derive node parity against today's IR;
  re-measure son-compare divergences; verify cross-load round-trips the
  new vocabulary (class_name, regex nodes, per-call identity preserved
  across serialize/load). Deliverable: the Phase-4 gap map (per-idiom:
  produces / produces-wrong / cannot-produce), seeded from the mdtest
  corpus perl sources.
- **4b — Computation slice green.** Fix FromOptree on the
  scalar/aggregate/control-flow corpus topics (arithmetic, variables,
  increment, logical, strings, control-flow, references, statements):
  behavior == oracle through the P corner, L corner where runtime-free,
  shape-subset match against the ir blocks. PadAccess targ bug lands here.
- **4c — The class tier: MOP emission.** B::SoN emits the sealed MOP
  (classes/fields/methods/ADJUST as per-method/per-phaser graphs,
  control-threaded), `Call.class_name` set; classes.md + variables.md A5
  pass the triple check; class files stop being zero-overlap in
  son-compare.
- **4d — Regex/host tier** (regex.md, host.md sources) once 019eb6ff item 1
  (RegexMatch identity) lands — B::SoN-produced match nodes inherit
  whatever identity contract that fix decides.
- **Gate (the plan's acceptance criterion):** B::SoN produces IR/MOP from
  the optree that passes the well-typed-graph invariant and lowers via the
  verified backends to behavior matching perl, across the corpus topics.
  Then Phase 5 unblocks.

## Gate 0 — 019eb6ff (wired as a blocker 2026-06-12)

The follow-up family from the 019eb316 review holds live-reproduced
miscompiles in the verifier's own backend (RegexMatch/Match outside both
the identity table and the staleness predicate; loop-exit
`_wire_region_phis` never got the Family-B/C treatment; `_arr_table`
keying). They were latent for hand-built graphs; B::SoN graphs from real
lib/ (regex-heavy, loop-heavy) are exactly the input that flushes them.
"A divergence is a B::SoN bug" is only a sound debugging rule if the
backend has no known miscompiles of its own — so 019eb6ff gates Phase 4.
(Its items 5/6 — collector drift, inherited-ADJUST — should be triaged
within that issue; the miscompile items 1–3 are the hard gate.)

## Open decisions (made during 4a, not now)

1. Where conversion lives: does B::SoN emit Chalk-shaped JSON that
   Chalk::IR::Serialize::JSON loads (current shape), or construct Chalk
   nodes in-process through NodeFactory? The identity contract favors
   whichever path routes through ONE factory implementation.
2. MOP emission side: does perl5-son build the MOP (needs Chalk::MOP
   loadable there) or emit a declarative class-structure JSON section the
   Chalk side replays through declare_*/seal? (The corpus builder's
   MOP::* vocabulary is precedent for replay-on-load.)
3. Multi-exit method bodies: gap-map entry per above, or worth an early
   single-exit normalization (merge returns through a Phi) in FromOptree?
