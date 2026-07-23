# Justifying the "everything is a coercion" architecture via thin vertical slices

ABOUTME: Go/no-go slice program to prove-or-falsify the coercion architecture's
ABOUTME: load-bearing claims before committing to the Chalk::Meta::Type registry.

Date: 2026-07-22
Status: PLAN (capture) — pending assess -> refine -> chain-review -> execute
Origin: a Fable-investigation / Opus-synthesis workflow (wf_6b809ed6-888) that
extracted the architecture's falsifiable claims, mapped reality, and
adversarially hardened the slices. This doc records that plan.

## The question this answers

Not "how many coercions before we build the registry" but: **what are the
thinnest end-to-end slices that PROVE OR FALSIFY the architecture's load-bearing
claims?** Each slice targets one falsifiable claim, reuses what exists, builds
only the delta, and banks standalone value. You can stop at any rung.

## The claims (falsifiable form)

- **C1 UNIFORMITY** — every pass IS coerce(From,To) with From/To as TYPES.
  *Already DEMOTED by the docs* to a naming claim (`coerce(SourceText,OPTree)` is
  un-liftable in principle — OPTree is a libperl C struct). NOT thinly provable;
  see Dropped.
- **C2 VALUE-COERCION-AS-NODE** — value coercions (Int->Num, ...) are IR NODES
  inserted in the graph, not inline lowering code. *FALSE today* by the doc's own
  bypass-site count (six inline sites). This is the most load-bearing provable claim.
- **C3 REGISTRY-UNIFIES** — one coerce(From,To) contract holds BOTH value
  coercions AND compiler-pass coercions. Falsifier located (see Slice C).
- **C4 PURITY** — coercions are pure/cacheable BECAUSE effects are quarantined to
  the control chain. Rider on C5; needs a shape assertion to be gated.
- **C5 MONAD-SHAPED EFFECTS** — the control-chain effect threading keeps a spliced
  loop+effect body's stores/prints in PROGRAM ORDER. The doc's SELF-NAMED "biggest
  UNPROVEN mechanism." This is the program's pivot.
- **C6 EMERGENCE** — demand-pulled, built one coercion at a time. Rider on C2 (N=1).

**Quarantined (NOT in either doc — do NOT let a slice cite them):**
`optimize = coerce(IRGraph,IRGraph)` and "monad-shaped effects / IO monad" appear
in neither architecture doc (grep-verified). They are conversation-introduced
claims that need their OWN capture + decision before any slice references them.

## RECONCILED SHAPE (assess + ponytail, 2026-07-22): "do A, then see"

Both assessors converged: Slice A is shovel-ready (adversarial REPRODUCED the red
invariant leg by execution); Slice C is over-built (the C3 falsifier needs no
registry — see below); the go/no-go criterion had a logic flaw (fixed below). The
milestone is effectively **Slice A alone**, with B a documented go/no-go DECISION
and the registry a documented trigger. Details in "## The slice program" retained
below for the full analysis; the reconciled deltas:

1. **Slice A now.** Shovel-ready. Itemize the 4 edits; declare the TARGMY-Divide
   twin site (`$x /= 2`, FromOptree ~:1932) explicitly IN or OUT (the gated corpus
   case needs only the plain site ~:2194; skipping TARGMY leaves it invariant-red).
2. **C3 is ALREADY FALSIFIED in-repo — do NOT build a probe OR a registry.**
   Adversarial found (a) the from_json MOP-drop is statically observable by one
   grep (`return (\%graphs,$mop) if wantarray`, JSON.pm:739), and (b) a LIVE C3
   counterexample already exists: Target::C's `($sa,$ctx)` backchannel (documented
   in CLAUDE.md) — a pass whose contract does NOT unify under one apply. So C3's
   "one contract unifies value + pass coercions" is already false; document it, do
   not build 200 lines (or 20) to rediscover it.
3. **Slice B = a go/no-go DECISION with an OPERATIONAL criterion (the key fix).**
   The old "if B drops/reorders a store -> FALSIFIED" conflates a
   first-implementation BUG with architectural IMPOSSIBILITY. Fixed criterion:
   - FALSIFIED only if the control-chain model CANNOT EXPRESS the ordering (a
     structural impossibility, not a bug) within a bounded effort.
   - A dropped/reordered store on first attempt is a BUG -> debug it (bounded
     effort, e.g. 2 sessions), not a STOP.
   - Third honest outcome: commit 1 (loud GAP) lands, commit 2 (ordered lowering)
     DEFERRED -> neither proven nor falsified; park with a follow-up.
   B is heavier than even the bumped budget (finding 1: `_find_memstart`/
   `_freeze_memory_reads` + control-lowering re-entrancy collide too). So B is a
   DECISION to schedule, not a committed slice.
4. **Registry deferred** behind B-holds AND N>=3, as a documented trigger (unchanged).
5. **C1 -> doc note only.** Drop the invented `IRModule` replacement type (zero
   hits in lib/+docs — the fix-of-the-fix is itself mistyped). Just note the
   `coerce(SoNGraph,LLVMIR)` row's From is really the `(\%graphs,$mop)` bundle /
   return-rooted graph; don't assert a specific new type name.
6. **C4 assertion needs an ll_text negative check** (corpus `ir` blocks assert the
   GRAPH, not the emitted .ll). Constructible via the libperl-guard grep precedent
   (MdtestCorpus.pm:2313-2330) — cost it when B is scheduled, not now.

## The slice program: A -> B -> (C at N>=3)

### Slice A — the divide bridge (zhi 019f82f1). DO FIRST. Proves C2 + C6.
Cost: ~45-65 lines, one commit, ZERO new classes. Produces the first PRODUCTION
`Coerce(Int->Num)` node in perl5-son FromOptree, wires it end-to-end, flips the
divide corpus case's red invariant leg green.
- Reuses (all shipped, verified against head): `_lower_coerce` sitofp arm
  (Context.pm:1028), JSON loader Coerce arm (Serialize/JSON.pm:467), the
  TypedInvariant Divide=>Num bridge check (TypedInvariant.pm:22, red today on
  unbridged Int inputs), the corpus absorption shim (MdtestCorpus.pm:394).
- **4 EDITS, not 3** (adversary + synthesizer verified firsthand): the perl5-son
  wire emitter `lib/SoN/Serialize/JSON.pm` `_extract_fields` returns `undef` for
  Coerce, SILENTLY DROPPING from_repr/to_repr on the wire. Add a Coerce arm. The
  invariant gate catching its omission is itself proof the gate is real.
- Proves C2 (a coercion is a real routed node, not inline code) end-to-end AND C6
  (N=1, zero registry, demand-pulled by the divide case). Standalone value: closes
  a real bug-class + flips a red test whether or not the registry is ever built.
- Gate: corpus `t/bootstrap/corpus/son-corpus-wide.t` — the divide case
  ('Float division of two variables') green across all three legs, floor held/
  raised (PIN the floor number at implementation time, do NOT hardcode 148/152),
  well-typed-graph.t H2-6/H2-7 stay green, perl5-son suite green (producer touched).

### Slice B — inliner on a loop+effect callee. THE GO/NO-GO GATE. Proves C5 (+C4).
Cost: two commits, one file + one corpus case; **budget for memory-SSA
re-entrancy, NOT the stated 60-100 lines** (adversary: understated).
- Commit 1: convert silent effect-drop to a loud GAP in `_lower_call_direct`.
- Commit 2: lower the callee's `control_in` chain in PROGRAM ORDER inside the
  arg-bind frame. Weakening (adversary, valid): the loop-writing-array shape
  collides with `_scan_memory_shape`'s once-per-top-Return cached
  `_branch_guarded_store`; commit 2 must LOCALIZE/per-graph that scan state and
  drive nested loop lowering, not just call `lower_value`.
- **C4 rider is UNGATED as written** — behavior output can't observe non-emission
  of dead pure code. MUST add a shape-block assertion that the callee's dead pure
  computation is ABSENT from the emitted LLVM. Without it, this slice proves C5
  only, not C4.
- **This is the whole program's go/no-go.** If B holds, the modest architecture is
  earned incrementally. If B fails (a store dropped or reordered), C5 is dead ->
  the architecture is FALSIFIED at its own self-named weakest point, cheaply, with
  one slice. That is exactly what thin slices are for.

### Slice C — the (From,To) registry as a FALSIFICATION INSTRUMENT. Proves C3 (weakly).
Cost: ~200 lines, one lib file + one test, zero production call-sites re-pointed.
**Only legitimate AFTER Slice A lands consumer #1 AND two more real coercions
exist (numify Str->Num, print-args Stringify)** — the registry doc forbids
building Chalk::Meta::Type below N>=3; building it early proves C3 only by breaking
C6. Its VALUE is to try to FALSIFY C3, and the adversary found exactly where:
- `from_json` returns `(\%graphs, $mop)` in LIST context (JSON.pm:739;
  Mode1Runner.pm:151 consumes both). A one-value `apply` signature forces scalar
  context and SILENTLY DROPS the MOP — the precise point where the common-contract
  claim falsifies. The cell must carry a tuple To-value or record the falsification.
- Add one CLASSFUL (mop-carrying) unit to the pipeline probe so
  `(SoNGraph,LLVMIR)`'s side-input problem can actually fire.
- Even amended, C3 proves "typed arrows are registrable/dispatchable" (the doc's
  demoted naming form), NOT that passes are writable in the subset.

### DROPPED — C1 uniformity.
Not thinly provable. Its byte-compare gate was `x eq x` (the table cell and the
oracle are the same two statements, one closured) — unfalsifiable by construction.
Its two real findings are a **short DOC CORRECTION**, not a slice: the doc's
`coerce(SoNGraph,LLVMIR)` row's From is really the `(\%graphs,$mop)` bundle /
return-rooted graph, NOT a distinct type. Do NOT assert an invented type name
(`IRModule` has zero hits in lib/+docs — per the RECONCILED SHAPE delta 5). Just
note the row's From is the bundle and add an API-shape guard note citing
JSON.pm:739 / LLVM.pm:53. Make the doc edit; skip the test.

## The decision gate — build Chalk::Meta::Type only when ALL of:
- Slice A green (C2 proven).
- Slice B green WITH its C4 shape-block assertion (C5 + C4 proven). **If B cannot
  keep effects in order, STOP — architecture falsified, no registry warranted.**
- N>=3 real produce-time coercion insertions exist (Int->Num divide, Str->Num
  numify, one more), each referencing the failing test that pulled it.
- At least one needs Type BEHAVIOR (the MRO-fallback requirement supplies this).

**No-go / falsified if:** Slice B drops/reorders a store (C5 dead -> architecture
dead); or Slice C's amended cell cannot preserve the MOP under a one-value apply
AND the classful probe cannot fit its side-input (C3 common-contract falsified).

## Honest verdict

**Incrementally justifiable — barely, and only the MODEST version.** NOT
all-or-nothing: Slice A banks standalone value, each slice gates the next, stop at
any rung. But the grand "compilation IS one uniform coercion over the whole
pipeline" reading is NOT what these slices justify — the docs already walked it
back. What is earned is coercions-as-routed-nodes (C2) + a demand-pulled registry
(C3/C6) that names and dispatches typed arrows. The load-bearing risk is Slice B:
the effect-ordering mechanism has never run on a loop+effect inline shape. Do A
first (cheap, real, standalone); do B and treat its result as go/no-go for the
entire program.

## Evidence base (verified 2026-07-22, workflow wf_6b809ed6-888)

- TypedInvariant Divide=>Num bridge red today: TypedInvariant.pm:22.
- Coerce node + sitofp lowering shipped: Node/Coerce.pm; Context.pm:1019-1046.
- JSON loader Coerce arm exists; perl5-son wire emitter arm MISSING: chalk
  Serialize/JSON.pm:467 vs perl5-son SoN/Serialize/JSON.pm `_extract_fields`.
- from_json returns (\%graphs,$mop) in list ctx (C3 falsifier): JSON.pm:739.
- C1 gate is x-eq-x / doc row mistyped: LLVM.pm:53.
- optimize/monad claims in neither doc: grep-verified.
