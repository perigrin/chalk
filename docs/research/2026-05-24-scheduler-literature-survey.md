# Scheduler Literature Survey

**Date:** 2026-05-24
**For:** Chalk SoN scheduler — choosing the "destination" algorithm
  after the eager-pinning transitional phase.
**Status:** Literature review, no decision.

## 1. Background and scope

The Chalk scheduler design (`docs/plans/2026-05-24-son-scheduler-design.md`)
commits to **eager pinning** as a transitional scheduler: Phase 3d already
pins every side-effect node to its control predecessor via `inputs[0]`,
and the scheduler walks that pinning rather than recomputing placement.
The destination algorithm is open. The doc's default is "Click 1995 GCM
later"; this survey audits that default against thirty-one years of
intervening work.

Scope: SoN-class IRs and scheduling/placement algorithms. Out of scope:
register allocation (touched only where it bears on placement), instruction
selection per se, dataflow analysis techniques unrelated to placement, and
non-SSA IRs.

Pitch level: assumes familiarity with SSA, dominator trees, hash-consing,
GCM at the level of "early schedule + late schedule via dominator tree
LCA," and the SoN vs CFG-with-SSA distinction. We do not re-explain those.

## 2. The post-Click-1995 landscape

Click's 1995 PLDI paper *Global Code Motion / Global Value Numbering*
([Click 1995][gcm]) remains the canonical reference; the algorithm has
not been displaced, only refined and supplemented. The most cited
direct successors and refinements:

- **Anti-dependency fix (Click himself, much later).** Click's thesis
  scheduler missed anti-dependencies; this was corrected in HotSpot C2
  and in the pedagogical *Simple* implementation
  ([Click, *A Simple Reply*][asimplereply]). Anyone implementing GCM from
  the 1995 paper alone gets a known-wrong scheduler.
- **Barany & Krall, CC 2013** — *Optimal and Heuristic Global Code Motion
  for Minimal Spilling* ([Barany & Krall 2013][barany]). Models GCM as an
  ILP minimizing live-range overlap, against the question "does GCM-
  for-loop-depth actually pay off?" Their headline result is sobering:
  *purely register-pressure-driven* GCM rarely improves performance —
  the placement is too conservative. **Local** optimal scheduling for
  spilling does help; global motion mostly doesn't. This is the
  strongest published critique of "GCM as a performance win" we found.
- **VSDG / Lawrence et al.** — *Combined Code Motion and Register
  Allocation Using the Value State Dependence Graph* ([Lawrence 2007][vsdg]).
  A different IR (Value State Dependence Graph) with θ-nodes for loops
  and γ-nodes for conditionals. Schedules by simultaneously solving
  placement and register allocation. Influential but not adopted in
  production.
- **Formally verified LICM / GVN** (CompCert lineage; *Monniaux & Six*
  in TECS 2022, [HAL hal-03628646][monniaux]). Verifies that
  Click-style hoisting preserves semantics by composing unrolling with
  GVN. Confirms the algorithm's correctness rather than improving it.

We did not find a paper that *replaces* GCM in the way Aycock's DFA
work replaced naive Earley prediction. GCM is more "stable canonical
algorithm with known weaknesses" than "open research problem."

## 3. Industrial practice in modern SoN compilers

What production compilers actually do, as best we could reconstruct:

- **OpenJDK HotSpot C2** — Click's GCM, still. C2 is the reference
  implementation. Adds a frequency-aware late-schedule heuristic
  (move into low-frequency branches, especially deopt paths) and
  anti-dependency edges. PhaseCFG builds the schedule. C2 is widely
  regarded as the place GCM has been most carefully tuned over time.
- **GraalVM** — **hybrid pinning + GCM**. Graal IR distinguishes
  *fixed nodes* (anchored in control: begins, ends, deopts, side-
  effecting ops) from *floating nodes* (pure SSA values, freely
  schedulable). Fixed nodes pre-define a CFG; floating nodes get
  Click-style early/late placement against that CFG
  ([Duboscq APPLC 2013][graalir]; [Verifying GraalVM Optimization
  Passes (UQ)][uqgraal]). 22.x added "early GVN" and "early LICM"
  (`-Dgraal.EarlyGVN`, `-Dgraal.EarlyLICM`) — *partial* placement
  decisions made earlier in the pipeline, before full GCM, to reduce
  later work. This is the most explicit hybrid pin-vs-float design in
  production.
- **V8 TurboFan** — Click-style GCM with a "soup of nodes" relaxation
  ([Titzer, V8 blog][v8-leaving]). Famously abandoned; see §4. The
  scheduler had to *re-duplicate* what GVN had previously deduplicated
  to avoid forcing computations onto cold paths — a documented
  pathology of the GCM-after-GVN order in dynamic workloads.
- **V8 Turboshaft** — Not SoN. CFG with SSA, single forward pass, no
  global motion of any kind for the JS pipeline. ([V8 blog: *Land
  ahoy*][v8-leaving].) "Eager pinning" is the right shorthand: the
  IR fixes block placement at construction and the optimizer rewrites
  in-place. Reported compile time roughly halved versus TurboFan.
- **V8 Maglev** — Also not SoN, also not Turboshaft. A separate, simpler
  CFG-SSA tier between Sparkplug (baseline) and Turboshaft (optimizing).
  Single forward pass with phi-prepass; register allocation is a single
  forward walk maintaining abstract machine state ([V8 blog: *Maglev*][maglev]).
  Roughly ~10× faster to compile than Turboshaft, somewhat worse code.
  Worth noting because it's an explicit *tiering* answer to the "GCM
  is too slow / too complex" critique: don't fix scheduling, use less
  of it on warm code.
- **Cranelift** — Not SoN historically. Recent **acyclic e-graph
  ("aegraph") mid-end** with **scoped elaboration** for placement
  ([Fallin 2026][cfallin-aegraph]). Scoped elaboration is a dominator-
  tree preorder walk with a scope-stack mapping eclasses to SSA values;
  it subsumes GVN and (during elaboration) LICM. Structurally similar
  to GCM-late on the dominator tree, but driven by e-graph extraction
  rather than freestanding placement. A real third design point
  alongside GCM and eager pinning.
- **LibFirm** — Click-style GCM. SoN until assembly emission.
- **Azul Falcon** — Built on LLVM. LLVM is *not* SoN; it has a CFG and
  uses a pile of separate passes (LICM, GVN, MachineSink, MachineScheduler).
  Falcon inherits all of that. The data point matters because Azul
  explicitly *left* C2 for Falcon and reports speedups, so "production
  Java JIT must use SoN+GCM" is empirically false.
- **SpiderMonkey IonMonkey / WarpMonkey** — CFG with SSA from the start
  ([Mozilla wiki: *IonMonkey*][ionmonkey]). MIR → optimization (GVN,
  LICM) → LIR → linear-scan register allocation. Never SoN.
- **PyPy** — Tracing JIT; traces are by construction linear with guards,
  so there is no global scheduling problem. The "scheduler" exists
  only for the vectorizer ([Plangger SCOPES 2016][pypy-vec]).
- **LuaJIT** — Linear IR with snapshots ([Mike Pall, various]). Not
  SoN. No global scheduling problem.

The picture: **SoN+GCM is healthy in HotSpot/Graal/LibFirm, contested
in V8, and absent from every other modern dynamic-language JIT we
checked.** Cranelift's scoped elaboration is the most interesting new
algorithm in this space.

## 4. Scheduling for dynamic-language compilers

This is where Click's framing strains. The V8 *Land ahoy* postmortem
([Titzer/V8][v8-leaving]) and Click's reply ([*A Simple Reply*][asimplereply])
together form the clearest argument-counterargument in the literature:

**V8's specific complaints, all about scheduling consequences:**

1. *Deduplicate/re-duplicate oscillation.* GVN merges two divisions
   into one, GCM then has to duplicate it back to avoid running the
   division on cold paths it doesn't need. "We started with 2
   divisions, then 'optimized' to a single division, and then
   optimized further to 2 divisions again." The scheduler has to
   know which nodes *should* be re-duplicated and how — substantial
   complexity targeted at undoing prior optimization.
2. *Effect-chain merges everywhere.* JS is heavy on possibly-aliased
   memory accesses (every property access is a potential effect).
   Effect chains merge constantly, "negating part of the advantages
   of having multiple effect chains." The scheduling-relevant promise
   of SoN — that effects float when independent — is rarely cashable.
3. *Visitation order.* SoN has no natural traversal order, so peepholes
   visit the same node ~20 times before fixed point. CFG visits each
   node once per pass.

**Click's response:**

1. The scheduler complexity is "no more complex than the natural-loop-
   finding version of SCC." Use a worklist; back-edges are cheap; dead
   code falls out for free when ref-counts hit zero.
2. The effect-chain problem is V8's choice of equivalence-class aliasing,
   not SoN's fault. Strong-typed effect chains (HotSpot's approach) avoid
   the merge storm.
3. Expanding complex constructs *after* GCM solves several of the
   complaints — let GCM produce the CFG and then handle the awkward
   constructs in CFG form.

Note Click does **not** directly defend Turbofan; his argument is "V8
made specific design errors that compounded; SoN was not the load-
bearing wrong choice." We could find no published Click critique of
*Turboshaft's eager-pinning* per se — the prep doc's reference to such
a critique appears to conflate his GCM defense in *A Simple Reply* with
a hypothetical pinning critique. Worth verifying with the user.

The dynamic-language thread also surfaces a second issue not addressed
by Click: **deopt points are dense, and every floating node must
preserve its FrameState for re-entry into the interpreter.** This is a
real constraint on placement that static Java does not face to the
same degree, and it argues against aggressive code motion in any JS-
or Perl-class setting.

We found no scheduling algorithm specifically *designed* for dynamic
languages. The dynamic-language compilers either (a) inherit Click GCM
and live with the friction (Graal, old TurboFan), or (b) skip global
scheduling entirely (Maglev, Turboshaft, IonMonkey, WarpMonkey, LuaJIT,
PyPy). There is no third option in production. The research literature
follows industry: "scheduling for dynamic language IR" is not a named
subfield.

## 5. Region-based alternatives

**MLIR** is the significant counter-paradigm
([MLIR Rationale][mlir-rationale]; [SCF dialect][mlir-scf]). Control
constructs (`scf.if`, `scf.for`) are **regions** with explicit
terminators, nested inside operations. Scheduling-as-such barely exists
at the high MLIR levels — structure is preserved until deliberate
lowering to a CFG dialect (`cf`). Each lowering step is a scheduling
*decision* exposed as a pass.

Tradeoffs versus SoN:

- **Pro.** Source structure is recoverable indefinitely; no re-
  reconstruction. Optimization passes can refuse to lose structure.
  Deopt and exception semantics are easier to preserve.
- **Pro.** Multiple levels coexist; you can schedule the inner loop
  at vector-IR level and leave the outer control alone.
- **Con.** Optimizations that *want* to violate source structure
  (loop fusion, hoist-across-control) need region-aware rewrites,
  which are more complex than "move a node along the def-use graph."
- **Con.** Region IRs lock in the structured-source assumption. Goto-
  heavy IR (rare in modern source) becomes awkward.

For Chalk: we are committed to SoN and the question is *which scheduler*
not *which IR*. MLIR is included for awareness only. The fact that
Chalk's *parser* output is structured Perl makes the MLIR-style
"preserve structure, schedule via lowering" pattern philosophically
adjacent — but adopting it would invalidate the SoN investment.

## 6. Hybrid approaches

This is the most interesting category for Chalk and the literature
actually has something to say.

**Graal IR's fixed/floating split** is the canonical hybrid. Side-
effecting and control nodes are *born pinned* (fixed nodes); pure
values are *born floating* and get GCM placement at scheduling time.
The CFG can be computed from fixed nodes alone, at any time, without
running the floating scheduler. This is precisely the "pin by default,
allow opt-in placement freedom" pattern.

Crucially: **eager pinning of side-effect nodes is not in tension with
Click GCM.** It is what Click GCM does for control- and effect-edged
nodes anyway. Eager pinning in Chalk's Phase 3d sense (every side-
effect node anchored to its control predecessor via `inputs[0]`) is
*indistinguishable* from Graal IR's fixed-node treatment — the
difference is whether *pure data nodes* are also pinned.

Graal's "early GVN / early LICM" passes are a second-order hybrid: do
*some* placement decisions early, before the full GCM pass. Mostly an
engineering response to GCM's compile-time cost.

**Cranelift's scoped elaboration** is a different hybrid: the e-graph
mid-end keeps everything as eclasses (no placement), and a single
dominator-preorder walk extracts and places in one pass. It is
*morally* GCM-late (placement by dominator-tree walk) but driven by
e-graph extraction rather than data-flow chasing. LICM falls out of
the elaboration walk for free.

The literature does not, as far as we found, name an algorithm
explicitly called "selective GCM" or "opt-in placement freedom." But
the **Graal fixed/floating distinction** is the closest match to the
informal "eager pinning now, mechanical swap to GCM-or-similar later"
story in Chalk's design doc. The transition could be reframed as:
"add a `floating` annotation to a node class, mark our pure nodes
floating, then run GCM on just those." This is a smaller commitment
than full-graph GCM and aligns with industry practice.

## 7. Candidates for Chalk's destination scheduler

Three plausible destinations, in order of conservatism. We do not pick.

### Candidate A: Click 1995 GCM, anti-dep-corrected, frequency-aware

The default the design doc names. Reference implementations in HotSpot
C2 and `SeaOfNodes/Simple` chapter 11.

**Pros:**
- Most-studied SoN scheduler. Reference implementations exist.
- Cleanly separates "scheduling" from "optimization" (Click's design goal).
- Anti-dep correction is well-documented; the `Simple` repo's chapter 10
  is implementable in a weekend.
- Compatible with Chalk's eager-pinning transition: GCM on pure nodes
  only is structurally equivalent to "Phase 3d pinning + Click late-
  schedule for pure nodes."

**Cons:**
- Barany & Krall 2013 show register-pressure-aware GCM rarely helps;
  Chalk's targets (Perl source, eventually C/LLVM) put register-pressure
  decisions either entirely downstream (LLVM) or not-at-all (Perl).
  This may not matter for Chalk, but it removes one of GCM's classical
  selling points.
- Click's complaints in *A Simple Reply* still concede that the
  worklist gets visited many times; the V8 ~20-revisits-per-node
  pathology is real for Chalk's parser-emit-IR workload too.
- The 1995 paper's algorithm is wrong as published (anti-deps).
  Reference is `SeaOfNodes/Simple` chapter 10/11, not the paper.

### Candidate B: Graal-style fixed/floating split + GCM-on-floating

Annotate each IR node class as `fixed` (always pinned to control) or
`floating` (placeable). Side-effecting nodes are fixed. Pure data nodes
are floating. The scheduler walks fixed nodes for the CFG skeleton,
then runs Click-style early/late on floating nodes against that
skeleton.

**Pros:**
- Phase 3d's existing pinning is exactly the fixed-node treatment.
  No regression risk: removing the `floating` annotation reduces to
  Chalk's current eager pinning.
- Production-validated by Graal.
- "Mechanical swap" promise of the design doc is real: it's literally
  flipping an annotation on a node class.
- Lets us opt specific transformations (hoisting, sinking) into
  placement freedom without committing the whole IR.

**Cons:**
- More mechanism than Candidate A. Two-pass node-class taxonomy.
- We have to decide *per node class* what's fixed vs floating. The
  literature does not give a recipe; Graal evolved its taxonomy over
  years.
- Effect chains in dynamic-language IR (Perl's `local $_`, `$@`, tied
  variables, prototype dispatch) push many nodes into "fixed" — the
  payoff may be small.

### Candidate C: Scoped elaboration (Cranelift-style), without the e-graph

Adapt Cranelift's scoped elaboration: a dominator-preorder walk with
a scope-stack mapping content-addressed node IDs to emit positions.
Place each pure node at the deepest scope where all uses are visible
and no use forces hoisting. LICM and GVN-like reuse fall out of the
walk.

Chalk already has hash-consing in `Graph::merge`, which is the eclass-
equivalent without the e-graph machinery. Scoped elaboration on a
hash-consed SoN graph is plausible without building an e-graph mid-end.

**Pros:**
- Single pass. Compile-time wins vs Click GCM's two-phase walk.
- LICM-for-free aligns with Chalk's "no separate hoisting pass yet"
  posture.
- Closest to the structure of Chalk's current `_emit_node` walk, so
  the migration path is shortest.
- Newest algorithm; most active research backing.

**Cons:**
- Cranelift uses it with an e-graph mid-end; the algorithm's behavior
  on a non-e-graph SoN is unproven.
- Less literature, less tribal knowledge. We would be on the experimental
  edge. (We are anyway — see Chalk's overall design — but worth naming.)
- Cranelift reports aegraph slowed AArch64 benchmarks 3.3% on average;
  the "performance hybrid" win is mixed.

## 8. Open questions for the design session

1. **Does Chalk care about Barany & Krall's spilling result?** The
   answer depends on whether Chalk's eventual LLVM backend takes the
   spilling decisions, or whether Chalk's own scheduler is on the
   critical path for register pressure. If LLVM owns spilling, GCM's
   register-pressure case mostly evaporates and the "pick GCM because
   it's classical" argument weakens.
2. **What's the actual claim about Click's Turboshaft critique?** The
   prep doc and the user-facing notes reference Click criticizing
   Turboshaft's eager pinning. *A Simple Reply* defends SoN against
   V8's complaints but does not, in the version we read, name
   Turboshaft or eager pinning directly. If there's a different
   document the user has seen, it should be added to sources. If not,
   the framing of "Click critiques eager pinning" should be softened.
3. **Is Chalk's eager-pinning posture more like Graal's fixed nodes
   than like Turboshaft's full pinning?** If yes — and Phase 3d's
   `inputs[0]` threading is consistent with that read — then the
   destination is naturally Candidate B (Graal-style hybrid), and the
   "transition to GCM" framing is closer to "extend the pinning model
   to admit floating nodes" than to "replace eager pinning with GCM."
4. **Does the structured-source parser input change the calculus?**
   Chalk parses real Perl, not bytecode. Source structure is intact at
   IR construction. This is the MLIR thesis: prefer to preserve
   structure. Does that argue against GCM (which throws structure
   away and reconstructs it) and toward scoped elaboration (which
   walks the dominator tree, recoverable from source)?
5. **What does the Perl backend actually need?** The current backend
   emits Perl source. C/LLVM backends are planned but not committed.
   If "emit Perl that round-trips to the input" is the long-term goal,
   *no scheduler placement freedom is desirable at all* — we would
   want to preserve emit order exactly. This argues for permanent
   eager pinning and against any of the three candidates. The
   question is whether the C/LLVM backends are real enough to drive
   the scheduling design.

## Sources

- [Click 1995 — *Global Code Motion / Global Value Numbering*][gcm].
  Original GCM paper. Also at the [Bernstein Bear mirror](https://bernsteinbear.com/assets/img/click-gvn.pdf).
- [Click — *A Simple Reply* (Sea of Nodes / Simple repo)][asimplereply].
  Response to V8's *Land ahoy*.
- [Click — *The Sea of Nodes and the HotSpot JIT* (PDF slides)](https://assets.ctfassets.net/oxjq45e8ilak/12JQgkvXnnXcPoAGoxB6le/5481932e755600401d607e20345d81d4/100752_1543361625_Cliff_Click_The_Sea_of_Nodes_and_the_HotSpot_JIT.pdf).
- [Click & Paleczny 1995 — *A Simple Graph-Based Intermediate
  Representation*](https://www.oracle.com/technetwork/java/javase/tech/c2-ir95-150110.pdf).
- [Barany & Krall, CC 2013 — *Optimal and Heuristic GCM for Minimal
  Spilling*][barany].
- [Lawrence 2007 — *Combined Code Motion and Register Allocation Using
  the VSDG*][vsdg].
- [Monniaux & Six, TECS 2022 — *Formally Verified Loop-Invariant Code
  Motion*][monniaux].
- [Duboscq APPLC 2013 — *Graal IR: An Extensible Declarative IR*][graalir].
- [University of Queensland — *Verifying GraalVM Optimization
  Passes*][uqgraal].
- [V8 blog — *Land ahoy: leaving the Sea of Nodes*][v8-leaving].
- [V8 blog — *Maglev: V8's Fastest Optimizing JIT*][maglev].
- [Fallin 2026 — *The acyclic e-graph: Cranelift's mid-end
  optimizer*][cfallin-aegraph].
- [Cranelift egraph RFC](https://github.com/bytecodealliance/rfcs/blob/main/accepted/cranelift-egraph.md).
- [MLIR Rationale][mlir-rationale].
- [MLIR SCF dialect][mlir-scf].
- [Mozilla wiki — *IonMonkey Overview*][ionmonkey].
- [Plangger, SCOPES 2016 — *Vectorization in PyPy's Tracing JIT*][pypy-vec].
- [SeaOfNodes/Simple repo](https://github.com/SeaOfNodes/Simple) —
  chapters 10 (peeps + anti-deps) and 11 (GCM).
- [Sea of nodes — Wikipedia](https://en.wikipedia.org/wiki/Sea_of_nodes).

[gcm]: https://dl.acm.org/doi/10.1145/223428.207154
[asimplereply]: https://github.com/SeaOfNodes/Simple/blob/main/ASimpleReply.md
[barany]: https://www.complang.tuwien.ac.at/gergo/papers/cc2013-barany-krall.pdf
[vsdg]: https://www.researchgate.net/publication/2934116_Combined_Code_Motion_and_Register_Allocation_Using_the_Value_State_Dependence_Graph
[monniaux]: https://hal.science/hal-03628646/document
[graalir]: https://ssw.jku.at/General/Staff/GD/APPLC-2013-paper_12.pdf
[uqgraal]: https://www.cyber.uq.edu.au/project/verifying-graalvm-optimization-passes
[v8-leaving]: https://v8.dev/blog/leaving-the-sea-of-nodes
[maglev]: https://v8.dev/blog/maglev
[cfallin-aegraph]: https://cfallin.org/blog/2026/04/09/aegraph/
[mlir-rationale]: https://mlir.llvm.org/docs/Rationale/Rationale/
[mlir-scf]: https://mlir.llvm.org/docs/Dialects/SCFDialect/
[ionmonkey]: https://wiki.mozilla.org/IonMonkey/Overview
[pypy-vec]: https://www.complang.tuwien.ac.at/andi/papers/scopes_16.pdf
