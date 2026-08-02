# Effect ordering in production compiler IRs — prior art

Research grounding for the Chalk effect-system redesign. Trigger: `print "before\n";
die "boom\n"` emits EMPTY stdout because `Unwind` stores its control predecessor in
`inputs[0]` instead of `control_in`, stranding a correctly-pinned `Print` off the
backward chain walk.

## Provenance and confidence — READ THIS FIRST

Two passes produced this document, with DIFFERENT confidence levels:

- **Pass 1 (workflow, partial).** A 103-agent deep-research run. Search and fetch
  phases completed and extracted 25 falsifiable claims from primary sources. **The
  adversarial verification phase never ran** — every one of the 25 verifier panels
  died on an account spend limit. So claims marked `[UNVERIFIED]` below are
  single-extraction from a named primary source, with no refutation pass. Several
  carry the extractor's own caveats, which are preserved.
- **Pass 2 (direct).** Three primary sources fetched and read directly to fill the
  gaps Pass 1 left. Marked `[DIRECT]`. Stronger than Pass 1 but still single-pass.

**Gaps that remain UNFILLED:** libFirm (M edges) was never fetched. Click's 1995
paper claims are from the Oracle-hosted PDF only; the thesis was not read.
Graal's ACM paper is paywalled — claims 22-24 come from the abstract plus the JKU
thesis, and the extractor flagged that the abstract alone does not settle whether
Graal carries a memory edge in addition to fixedness (the JKU thesis says it does).

## 1. The cross-cutting answer (Q6)

There is no single industry answer. There are **four distinct mechanisms**, and the
systems disagree:

| Mechanism | Who | Effect ordering is… |
|---|---|---|
| (b) data dependence on an opaque state value | Click/Paleczny 1995, C2, Graal's memory graph | a VALUE (`STORE`, `I_O`, memory state) threaded producer→consumer |
| (c) structural property of node class | Graal `FixedWithNextNode` | fixedness — no successor slot exists on a floating node |
| (a) a third edge kind | V8 TurboFan | an explicit effect chain alongside value and control |
| (d) per-operation declared properties | V8 Turboshaft | a bit-vector of produces/consumes dimensions ON the node |

Chalk's `control_in` is **(a)** — a third edge kind — which is precisely the one
design in this table that its own authors abandoned. See §3.

## 2. C2 / Click — effect ordering as a threaded VALUE, kind-split

`[UNVERIFIED]` *Click & Paleczny 1995, "A Simple Graph-Based Intermediate
Representation"* (https://www.oracle.com/technetwork/java/javase/tech/c2-ir95-150110.pdf):

- Memory is **not** a third edge kind. It is an ordinary value — the `STORE` —
  threaded as a data dependence. A STORE node consumes a STORE + address + value and
  **produces a new STORE**; a LOAD consumes a STORE and an address but produces
  **only the loaded value, no new STORE**. Phis merge STORE exactly like any other
  value.
- **I/O is a SEPARATE state value from memory, and the asymmetry is deliberate:** I/O
  reads *do* produce a new I/O state (unlike memory loads), which **totally
  serializes I/O**; and the I/O state — but not the memory state — is **live at
  program exit**. This is direct prior art for kind-indexed chains of *differing
  strength*.
- Calls and START are tuple-producing nodes whose results are split by PROJECTION
  nodes; a subroutine's signature includes at minimum control, memory STORE, and I/O.
- The authors themselves flag the single global STORE as too coarse and name memory
  slicing as future work — the alias machinery was **not** in the 1995 design.

`[UNVERIFIED]` *OpenJDK `opto/type.hpp` and `opto/memnode.cpp`*:

- `TypeFunc` defines six fixed projection slots — `Control, I_O, Memory, FramePtr,
  ReturnAdr, Parms`. The remembered claim about CallNode projections is confirmed at
  the type level.
- **The correctness-by-construction property:** these slots are allocated implicitly
  by the tuple constructor for *every* subroutine call type. **You cannot construct a
  C2 call signature that omits its Memory or I_O slot.** This is exactly the
  structural defense against Chalk's "forgot to register this node type" failure.
- C2 models abstract I/O (`Abio`) and abstract memory as two **distinct base types in
  the lattice** — the I_O edge carries a different value kind, not a duplicated chain.
- Memory is an alias-index-indexed *family* of slices merged by `MergeMemNode`, one
  input per alias index plus a wide `<Bot>` slice. MergeMem carries no control input.
- The **control edge on a load is optional and routinely deleted** (set to `nullptr`)
  when the address is invariant and non-null; ordering is then carried purely by the
  memory edge. Stores get no such freedom.
- Extractor's own caveat, preserved: `type.hpp` gives slot *names* only and never
  documents what I_O is semantically for. Do not cite it for I/O-vs-memory semantics.

## 3. V8 — the abandonment evidence, and it points AGAINST multiple chains

`[DIRECT]` *https://v8.dev/blog/leaving-the-sea-of-nodes*. This is the most
decision-relevant source in the document, because it is the one team here that built
the design Chalk currently has and then walked away from it.

**On effect chains specifically — quoted:**

> "managing a single effect chain is already hard; managing multiple ones will be
> much harder."

> "Because of the various branches and cases that have to be handled here, we end up
> managing 3 different effect chains. It's easy to get it wrong and use one effect
> chain instead of the other."

They cite a real bug from incorrect effect-chain management that **went undetected
for months**. That is Chalk's `Unwind` bug, at Google scale, in the mature version of
the design.

**On the premise collapsing:** "almost all generic JS operations can have arbitrary
side effects," so most nodes end up on the effect chain and "only pure nodes actually
float freely." Their conclusion: *"SoN is just CFG where pure nodes are floating."*

**On compile time:** nodes change "only once every 20 visits"; ~3x more L1 dcache
misses on average and up to 7x in some phases (~5% of compile time); the CFG load
elimination is "up to 190 times faster" with better worst-case complexity; overall
"compile time got divided by 2 compared to SoN."

**On debuggability:** "Manually/visually inspecting and understanding a Sea of Nodes
graph is hard"; a 9-line function's SoN graph is "a messy soup of nodes."

**On scheduling perversity:** two identical divisions were CSE'd to one, then
re-duplicated by the scheduler — "we started with 2 divisions, then 'optimized' to a
single division, and then optimized further to 2 divisions again."

**What replaced it** `[UNVERIFIED]` *Turboshaft source,
chromium.googlesource.com/v8/v8.git/+/lkgr/src/compiler/turboshaft*:

- Turboshaft has **NO effect edge and NO effect chain.** Effects are per-operation
  **properties** — a packed `OpEffects` struct with two bit-vectors, `produces` and
  `consumes`, over `EffectDimensions`.
- Those dimensions **are kind-indexed** (prior art for Q7): seven independent
  dimensions — heap load, off-heap load, heap store, off-heap store, two
  raw-heap-access fences, and control_flow.
- **Cross-kind ordering is resolved by an ASYMMETRIC produces/consumes match, not a
  total order:** two operations may not be swapped exactly when the earlier
  *produces* a dimension the later *consumes*. This permits one-directional motion (a
  load sinking past a control-flow-producing check, but not the reverse) that a
  single monolithic chain cannot express.

This is answer (d), and it is the direct answer to Q7: **you get kind-indexing
without maintaining N chains**, because there are no chains to maintain — only a
per-node-type declaration and a derived may-swap relation.

## 4. Graal — fixedness as node CLASS, plus a memory edge

`[UNVERIFIED]` *JKU thesis, https://epub.jku.at/obvulihs/download/pdf/1390355*, and
*`FixedWithNextNode.java`*:

- Ordering is a structural property of node kind. `FixedWithNextNode` is the abstract
  base for exactly those nodes pinned into the CFG, carrying one immediate successor.
  **Floating nodes have no successor slot at all** — a node is either structurally
  schedulable-anywhere or structurally chained. You cannot forget to chain a fixed
  node; there is nowhere to put it otherwise.
- Graal does **not** have three edge kinds. It has control-flow edges plus data-flow
  edges refined into seven named categories — Value, Memory, Condition, State, Guard,
  Anchor, Association — of which **Memory is the dedicated effect-ordering edge, and
  it is type-restricted so it may only point at nodes that may have an observable side
  effect.** One `Invoke` can be referenced by both a value edge and a memory edge.
- The memory model (attributed to Click/Paleczny) makes effect ordering a **data
  dependence on an opaque memory-state value**. Write-after-read edges are
  deliberately omitted — each side effect is conceptually an immutable snapshot —
  which shrinks the graph but **pushes complexity into the scheduler**.
- Alias classes give kind-indexing: `ANY_LOCATION` aliasing everything (for calls with
  unknown effects), disjoint per-field classes, immutable classes aliasing nothing.
  Edges are inserted only between a read and a side-effecting node that **may** alias.
- `[UNVERIFIED, abstract-only]` Side-effecting nodes are a distinguished class
  carrying mandatory framestate metadata; guards need no explicit control or effect
  edge because they inherit the framestate and position of the **last side-effecting
  node** — which is what lets guards float while still being ordered.
- **A named hard trade-off, attributed to real compilers:** "deoptimize to the
  previous side-effect" lets deopt nodes float but **forbids reordering side-effecting
  nodes** (parts of Graal; V8 Crankshaft); "fixed deoptimizations" pins deopt at parse
  time but **permits side-effect reordering** (HotSpot C1 and C2). Governing rule: two
  side-effecting nodes may be reordered only when no deoptimizing node lies between.

## 5. GHC — the token is NOT self-enforcing

`[DIRECT]` *GHC.Magic and GHC.IO.Unsafe source docs.* This corrects a tempting
assumption: threading `State# RealWorld` as a data dependence gives ordering, but
**nothing structural stops the token being floated or duplicated.** GHC needs
compiler special-casing:

> "the IO computation inside unsafePerformIO must be atomic: it must either all run,
> or not at all. If we let the compiler see the application of the IO to realWorld#,
> it might float out part of the IO."

> "there is a possibility that the IO action may be performed multiple times (on a
> multiprocessor)."

> "It may even happen that one of the duplicated IO actions is only run partially, and
> then interrupted in the middle without an exception being raised."

The defenses are pragmas and runtime machinery, not types: `NOINLINE`, `-fno-cse`,
`-fno-full-laziness`, `noDuplicate#`. `runRW#` exists precisely because "when manually
applying a function to `realWorld#`, it is necessary to use `NOINLINE` to prevent
semantically undesirable floating"; modern GHC inlines `runRW#` **"only very late in
compilation after all floating is complete."**

Explicitly **not** stated by these pages: which mechanism fundamentally prevents
duplication. It is not linearity and not the type system — it is a set of compiler
special cases. **Haskell's IO monad is not a correctness-by-construction ordering
mechanism at the IR level.** It is a source-language discipline that the compiler
must then be taught not to break.

## 6. What this means for Chalk (analysis, not yet a design)

1. **Chalk is on the one mechanism its authors abandoned.** `control_in` is TurboFan's
   effect edge. V8's stated failure mode — "easy to get it wrong and use one effect
   chain instead of the other," a bug undetected for months — is the `Unwind` bug.
2. **The proposed direction (separate IO/Memory/Control chains) is the thing V8
   explicitly warns against:** *"managing a single effect chain is already hard;
   managing multiple ones will be much harder."* They were managing three. Chalk
   already has two mechanisms (`control_in` + memory-SSA/MemStart) and the bug arose
   at the seam between conventions.
3. **Kind-indexing is still right — the chain is the wrong carrier for it.** C2, Graal
   and Turboshaft all kind-index. Only Turboshaft does it without N chains, by making
   effects a per-node-type *declaration* and deriving the may-swap relation.
4. **The Fixed/Free instinct is the strongest correctness lever available.** Graal's
   `FixedWithNextNode` and C2's mandatory `TypeFunc` slots are the two places in this
   research where forgetting is *structurally impossible* rather than merely
   discouraged. Chalk's `Unwind` bug is possible only because `control_in` is an
   optional side-pointer every node type may or may not set.
5. **A token as data dependence buys ordering, not safety.** GHC is the cautionary
   case. If Chalk threads a token, hash-consing/CSE/DCE must each be taught about it —
   the same class of special-casing GHC needs, and the same class Chalk's `%ALLOC_OPS`
   and `%STATEMENT_EFFECT_OPS` registries already are.
