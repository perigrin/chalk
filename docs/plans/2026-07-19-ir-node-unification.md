# IR-Node unification: B::SoN builds `Chalk::IR::Node` directly

**Status:** PLAN (2026-07-19, perigrin). No code yet. Grounded in a read-only
delta recon (two Node hierarchies + loader-as-map) run 2026-07-19; every
file:line below is from that recon and should be re-verified before editing
(the recon was read-only and point-in-time).

## ASSESSMENT (2026-07-19, independent empty-context Fable review, medium effort)

The review verified every codebase claim against both repos. **CORE SOUND, three
build-step amendments applied ([ASSESS-CORRECTED]/[ASSESS-ADDED] markers):**
- **The phantom-memory-edge correction is TRUE** — verified loudly (memory is
  StackSim builder state threaded as an ordinary positional input on BOTH sides;
  no Node field, no wire key; Chalk's MemStart consumed structurally). The unify
  genuinely does NOT touch the effect-token axis; no residue of the earlier
  three-turn error survives.
- The measured deltas are EXACT (5 Chalk-only ops; 4+1 fields; 82 shared
  subclasses; `%STATEMENT_EFFECT_OPS`; all loader citations land; repr fixpoint
  runs 5×; B::SoN produces no `representation`).
- **MAJOR-1 (Step 1 crashed as written):** the flattened-wire path needs
  `is_stmt_effect`/`loop_control`/`set_stamp` that the merged Chalk type lacks
  (feature-class DIES on unknown `:param`). "Zero rearchitecture" overshot — Step
  1 now names the transitional seam. FIXED.
- **MAJOR-2 (Step 2 was deletions-only):** moving control to produce-time REQUIRES
  a NEW `control_in` wire key + control-aware topo order (nothing emits
  `control_in` today). Step 2 now lists these additions before the deletions.
  FIXED.
- **MAJOR-3 (unbudgeted blast radius):** perl5-son's own suite (~15 files
  referencing `SoN::IR::Node`, SoN's own `from_json`) is a migration item. Added
  to Risks. FIXED.
- MINORs applied: content_hash-is-base-class-only reword; JSON.pm:296-306 STAYS
  (forward-input guard, not demotion-caused); factory seams (`make_unique`/scout
  walk, Phi consumer registration) added to Step 1.
Verdict: build via crochet:execute; keep the round-trip-test-first guardrail (it
catches exactly these seams).

## Why (the architectural driver)

Chalk is, at steady state, four coercions over one IR:
`String → Context → (MetaObjects + IRGraph) → Target`, plus `optimize: IRGraph
→ IRGraph`. The coercion architecture REQUIRES `IRGraph` to be **one type** —
`coerce(OpTree, IR)` (B::SoN) must produce the *identical* IR that
`coerce(IR, LLVM)` (`Target::LLVM->lower`) consumes. Today it does not: B::SoN
produces `SoN::IR::Node`, Chalk's loader rebuilds `Chalk::IR::Node`, and the
loader does **semantic work** in between (it demotes effect nodes' `inputs[0]`
to `control_in`). A loader that decides is a hidden THIRD coercion
`coerce(IR_bson, IR_chalk)` masquerading as deserialization — which means "IR"
in the vtable is two types with a fixup, not one type.

The fix is correctness-of-CONSTRUCTION, not correctness-of-output: a probe
(2026-07-19, 9 cases through B::SoN→Chalk→lli) found NO live miscompile from the
current flattened model — every scalar/element RMW and pure-read-across-store
case that lowers produces the correct answer. So this is not urgent-bug-driven.
It is required because you cannot build a coercion vtable over `IR` until `IR`
is genuinely one type, and the semantic loader is the standing evidence it
isn't. **Unify the Node type with the most-correct implementation of each part;
the loader collapses to a trivial inverse; serialization round-trips
losslessly.**

## Direction + survivor rule

**Direction (a): B::SoN adopts `Chalk::IR::Node`.** The unified type lives in
Chalk (the code that persists); perl5-son may depend on Chalk's IR classes
(perigrin, 2026-07-19); a build-time `cp` is an acceptable distribution
mechanism for a standalone B::SoN dist. B::SoN is the *transitional* producer
(the bootstrap airlock, retired once the Earley frontend self-hosts) — so the
dependency arrow (producer → IR) is correct.

**Survivor rule (perigrin): the merged type takes the MOST CORRECT
implementation of each part, even if that is currently the SoN-named one.** Name
goes to `Chalk::IR::Node`; content is picked field-by-field on merit. This is
"replace the worse implementation, keep the name evergreen," not "incumbent
wins." Where SoN's model is more correct, take SoN's and UPDATE Chalk's
consumers (perigrin: correctness > consumer-stability for this step).

## What the delta MEASURED (and the correction it forces)

**Chalk is a near-superset of SoN. The distance is SMALL.**
- **Op distance = 5**, all Chalk-only (`Access, Coerce, ExpressionList,
  ListAssign, Regex`); B::SoN's FromOptree emits ZERO of them. Adoption needs no
  new ops.
- **Base-Node field distance = 4 Chalk-only + 1 SoN-only.** The 4 Chalk-only
  (`control_in, schedule_data, representation, compat_class`) all default
  `undef` and are excluded from the base-Node `content_hash` (which =
  `operation()` + input-ids only). The 1 SoN-only (`loop_control`) is a narrow
  specialization the loader already folds into `control_in`.
  **[ASSESS-CORRECTED] `content_hash` = op + input-ids is BASE-CLASS-only.
  Subclasses override it: Chalk `Call.pm` hashes dispatch_kind/name/class_name/
  paren_form; `Phi.pm` hashes region; SoN `Call/Assign/Print` hash a
  `stmt_effect=0|1` bit. The "flattened-control-doesn't-change-identity"
  conclusion still HOLDS but for a different reason: Chalk's factory gives effect
  ops PER-CALL COUNTER identity and never consults content_hash for them
  (NodeFactory.pm:291-299), so their subclass hashes are moot. The SoN-side
  `stmt_effect`-in-hash is further evidence `is_stmt_effect` is a real
  per-subclass FIELD divergence, not merely "a JSON flag" (see the Step-1 seam).**
- **The one real difference is the CONTROL CONVENTION:** SoN flattens
  statement-effect control into `inputs[0]` + an `is_stmt_effect` JSON flag;
  Chalk carries it on a dedicated `control_in` field (content_hash-excluded,
  bidirectional edge). The loader's ~30 translation sites decode this.

**CORRECTION (perigrin's rule applied per axis) — this REPLACES an earlier
claim that "take SoN's model = adopt the memory edge = the deferred
effect-token re-architecture." That was WRONG; the memory edge is a phantom:**
- **Memory edge: NOT a Node field on EITHER side.** Both model memory-SSA by
  threading a memory VALUE through ordinary positional `inputs`, tracked on the
  producer's StackSim, seeded to a `MemStart` node
  (SoN StackSim.pm:16, FromOptree.pm:150-152; Chalk has the identical
  `MemStart`). The SoN serializer emits no memory key because there is nothing
  to emit — it already round-trips as an input. **So "gain the general memory
  edge" is a non-task, and the effect-token re-architecture is a SEPARATE,
  still-deferred project this unify does NOT touch.**
- **`control_in` as a first-class edge (Chalk's model) is MORE CORRECT** than
  flatten-into-inputs-and-flag → Chalk wins this axis; B::SoN moves to
  `set_control_in` at build time.
- **The smart factory (Chalk's `%STATEMENT_EFFECT_OPS` per-call identity) is
  MORE CORRECT** than SoN's dumb hash-cons-everything → Chalk wins; SoN's
  factory is deleted.
- **`representation` (Chalk, machine-lowering) and `stamp` (SoN, type lattice)
  are DIFFERENT LAYERS** → merged Node keeps both; B::SoN keeps emitting stamp,
  the 6-entry `%STAMP_TO_REPR` seed stays.

Net: applying "most correct per axis," the merged type is mostly Chalk's shape
(control_in, smart factory, representation) + SoN's stamp lattice, and B::SoN
builds `Chalk::IR::Node` directly. The principled choice and the affordable path
coincide.

## Sequencing verdict: unify FIRST, effect-token NOT triggered

DECISIVE (from the recon): the effect-token re-architecture is NOT required and
NOT triggered by this unify. Evidence: (1) memory is already an input on both
sides (nothing to add); (2) `control_in` already exists on Chalk and is
content_hash-excluded, so a node with control still flattened in `inputs[0]`
hashes by the factory's effect-op counter regardless — adopting the type forces
nothing off `inputs` on day one; (3) the loader's control-decode sites are pure
un-flattening, not structural bridging — they can keep running against a
still-flattened wire and be retired incrementally.

## The reconciliation list

**(i) B::SoN FromOptree/NodeFactory:**
- Call the Chalk factory; let it assign string ids (int `$next_id++` ids stop
  being load-bearing — the serializer already remaps to positional indices).
- DELETE SoN's factory; inherit Chalk's `%STATEMENT_EFFECT_OPS`/`%ALLOC_OPS`
  per-call identity for free (no `is_stmt_effect` flag).
- Build a `Chalk::IR::Graph` at the end (`->new(start=>, returns=>)`).
- Memory edge: NOTHING new (already an input).
- [Step-2 reward, not a precondition] call `set_control_in`/`set_region` at
  build time → the loader's decode sites become no-ops.

**(ii) `Chalk::IR::Node` gains:** almost nothing structural (already a superset;
B::SoN-unset fields default `undef`, content_hash-excluded). `stamp` already
rides along (`:param`). **[ASSESS-CORRECTED — the "nothing structural" was an
overshoot; there IS a small transitional seam.]** FromOptree constructs nodes
with SoN-only constructor/API that the merged Chalk type lacks, and
feature-class DIES on an unrecognized `:param` (it is a crash, not a silent
drop). Specifically:
- `is_stmt_effect => true` is passed at ~8 FromOptree sites (1024, 1058, 1587,
  1639, 1655, …) to Call/Assign/Print — Chalk's classes have no such `:param`.
- `set_loop_control` (FromOptree.pm:2696, 2816) and `$phi->set_stamp($join)`
  (unguarded, FromOptree.pm:2339) call setters Chalk::IR::Node lacks
  (`set_control_in`/`set_representation`/`set_schedule_data` exist; no
  `set_stamp`, no `loop_control`).
So the merged type must EITHER add `set_stamp` + a transitional `is_stmt_effect`/
`loop_control` carry (explicitly slated for deletion in Step 2), OR FromOptree
keeps that knowledge in a PRODUCER-SIDE side-table fed to the serializer. Step 1
below names this seam; it is small but NOT "zero rearchitecture."

**(iii) Loader DELETES vs MOVES vs STAYS:**
- DELETES (once control is produced first-class): Return control split/reattach
  (JSON.pm:338,440); stmt-effect split for Call/Assign/Print (JSON.pm:352-354,
  446); `loop_control` fold-in (JSON.pm:471-472); the Loop-condition
  unreachability guard that exists only because control is synthesized from a
  lossy demotion (JSON.pm:196-218).
  **[ASSESS-CORRECTED] JSON.pm:296-306 STAYS (do NOT delete):** it is the
  forward-input-reference integrity check (producer-ordering-bug guard, zhi
  019f26a5), not a demotion artifact — loop-Phi backedges remain the sanctioned
  forward edge after unification, so this guard stays relevant.
- MOVES to producer: Region/Loop/If `head` back-pointer — SoN's Region is empty;
  loader rebuilds `head` by walking arms' control chains (JSON.pm:492-524).
  B::SoN calls `set_region`/`set_head` at build time; the walk deletes.
- STAYS a Chalk post-load pass (unaffected by unification): the repr fixpoint
  engine + direct-call resolution + MOP replay + field-type inference
  (JSON.pm ~460-1430, ~2/3 of the file; `_seed_and_propagate_reprs` runs 5×).
  This is a whole-program/link-time fixpoint — it cannot become a per-node
  inverse and has no home in the per-optree producer. B::SoN produces no
  `representation` (machine reprs `Slot/Array/Hash` are Chalk lowering
  decisions, not lattice types).

## Sequence (capture → assess → refine → build applies to THIS doc; the build
steps below are what crochet:execute drives)

**Round-trip test FIRST (the guardrail, TDD):**
Assert `build(optree) ≡ from_json(to_json(build(optree)))` over an EFFECTFUL
fixture — multiple sequenced statement-effect Call/Assign/Print + a loop with a
memory-Phi (exercises control threading AND memory-SSA merge, the two axes most
likely to break). `≡` = structural graph equality: same node set by
`content_hash`, same input wiring, same `control_in` chain, same
memory-input threading, memory edge preserved. Lives in Chalk `t/bootstrap/`
beside the existing serialize round-trip tests; runs on a real effectful
fixture, not a toy.

**Build steps (ordered) — [ASSESS-CORRECTED: Step 1 is NOT "zero
rearchitecture"; Step 2 has ADDITIONS, not only deletions]:**
1. **Adopt the type + factory, keeping the wire flattened.** B::SoN builds
   `Chalk::IR::Node` subclasses via a shared/`cp`'d Chalk `NodeFactory`. Name the
   SEAM (§(ii)): FromOptree's `is_stmt_effect`/`loop_control`/stamp knowledge is
   carried EITHER as transitional fields on the merged type (slated for Step-2
   deletion) OR in a producer-side side-table fed to the serializer; add
   `set_stamp` to `Chalk::IR::Node`. Factory seams to reconcile (else silent
   breakage): (a) Chalk has NO `make_unique` — FromOptree's scout walk builds
   placeholder Constants with identical value `'scout'` via `make_unique` and
   detects mutation by identity (`$after != $ph`, FromOptree.pm:2249-2270); under
   Chalk `make()` these hash-cons to ONE node and loop-carried-slot detection
   breaks — port `make_unique` or an equivalent. (b) Chalk `make('Phi')`
   registers value-consumers only from `values =>`, never from `inputs =>`
   (NodeFactory.pm:220-225), but FromOptree/StackSim pass `inputs =>`
   (StackSim.pm:111-114) — use-def edges silently unregistered; reconcile the Phi
   input/value convention. Loader UNCHANGED. Delete SoN's factory. Prove the type
   adopts (round-trip green + perl5-son suite green — see risk).
2. **Move control to produce-time — ADDS a `control_in` wire key + control-aware
   topo order, THEN deletes decode sites.** FromOptree calls `set_control_in`/
   `set_region` at build time. This REQUIRES: (i) `to_json` gains a `control_in`
   wire key and `from_json` a decode for it (nothing emits `control_in` today —
   control round-trips ONLY because it rides in `inputs`); (ii) the serializer's
   topo order becomes control-aware (`SoN::IR::Graph` topo-orders by `inputs`
   only, Graph.pm:41-62 — a node linked solely via `control_in` has no ordering
   constraint vs its control predecessor, so either defer-patch it or order
   control edges; mitigated because the BFS already collects `consumers` and
   `set_control_in` registers them, so nodes aren't dropped). ONLY THEN delete
   the loader decode sites (JSON.pm:338,352-354,440,446,471-472) + Region
   head-walk (492-524) + the Loop-condition guard (196-218). Fold `loop_control`
   into `control_in` at the producer. Consider folding Step 3's Graph swap into
   this step (the topo-order change touches the Graph walk anyway).
3. Build `Chalk::IR::Graph` at the end (or fold into Step 2); per-subclass field
   audit (all 82 shared subclasses; confirm Chalk's extra per-subclass fields —
   e.g. `Call.resolved_graph` — default `undef` under B::SoN; this is the
   byte-completeness gate, and it subsumes the factory seams above).
4. Leave the repr/MOP inference pass alone.

## Risks

- **Corpus goldens (HIGH):** mdtest ir-blocks are a dual lowering-spec +
  optimizer-output contract (memory: corpus dual contract — IR-shape changes
  REQUIRE corpus updates). Step 2 changes in-process node shape (control on
  `control_in` vs `inputs`) → expect to regenerate/update goldens. Budget for it.
- **B::SoN byte-compat goldens (HIGH):** the factory swap changes id shape
  (int → `op#counter`) and possibly walk order → will move perl5-son byte-compat
  goldens. Most likely thing to light up red.
- **[ASSESS-ADDED] perl5-son's OWN test suite (HIGH — a MIGRATION item, not
  golden regeneration):** perl5-son has 84 test files; ~15 reference
  `SoN::IR::Node`/`SoN::IR::NodeFactory` directly and ~11 assert `is_stmt_effect`
  (grep over `~/dev/perl5-son/t/`). `SoN::Serialize::JSON::from_json`
  (:206-327) rebuilds via the factory this plan DELETES, and SoN's own round-trip
  tests run through it. Deleting `SoN::IR::Node*` breaks these outright. Build
  task (Step 1/2): port or rewrite the ~15 direct-reference test files, and
  DECIDE the fate of SoN's own `from_json` — delete it (Chalk's loader is now the
  only deserializer, the goal) or retarget it. This is real work, not a
  side-effect.
- **Parked MOP migration (MEDIUM):** the loader's MOP-replay + field-type
  inference (JSON.pm:687-1430) is entangled with the ~2/3-done MOP migration.
  This unify keeps it in place (does not advance/regress it). Step 2's deletions
  MUST NOT touch those lines. Keep the efforts strictly separate.
- **`compat_class` (LOW):** legacy debt on 17 test files; B::SoN never sets it.
  Not a blocker; do not delete it as part of this.

## Top unknowns to resolve before committing

1. **Can FromOptree call `set_control_in`/`set_region` at produce time without a
   StackSim/memory-SSA rework?** Step 1 is designed to NOT need this; Step 2's
   payoff depends on it. Prototype `set_control_in` on ONE effect op before
   committing to the decode-site deletion. If it forces a StackSim rework, Step
   2 splits off and Step 1 still stands alone.
2. **Per-subclass field divergence** (`Call` is 1848 B in SoN vs 3721 B in
   Chalk). Confirm no shared op carries a differently-named/shaped field that
   silently mis-round-trips. Byte-completeness gate.
3. **`loop_control` sufficiency:** does any Chalk pass read the loop-condition
   distinction AFTER the loader folds `loop_control` into `control_in`? The
   scheduler walks `control_in` only (Elaborate.pm:104-110, EagerPinning.pm:58-71
   — reads neither `loop_control` nor `is_stmt_effect`), suggesting `control_in`
   alone suffices — but confirm no loop-specific consumer needs the narrow
   channel before dropping it at the producer.

## What this is NOT (scope fence)

- NOT the effect-token / World-token re-architecture (memory is already an
  input; that project is separate and still deferred, capture-now/
  sequence-after-capstone).
- NOT a change to the repr/MOP inference pass (stays a Chalk post-load step).
- NOT an advance or regression of the parked MOP migration.
- NOT motivated by a live miscompile (the probe found none) — motivated by the
  single-IR-type property the coercion architecture requires.
