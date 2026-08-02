# Design: the world token — effect ordering as a typed graph edge

**Status:** design, awaiting review. Not a plan; no implementation.
**Prior art:** `docs/research/2026-08-02-effect-ordering-prior-art.md` (read its
provenance section — the adversarial verification pass never ran).

## The problem

`print "before\n"; die "boom\n"` emits **empty stdout**. Perl prints `before`.
Exit status (255) matches, so only the output is wrong. Measured by
`t/bootstrap/corpus/executable-gate.t`.

Cause: `Unwind` stores its control predecessor in `inputs[0]`. Every other
effectful node uses the `control_in` side-pointer. The backward control-chain walk
goes `Return -> Unwind -> STOP`, so a correctly-pinned `Print` one hop further back
is stranded and emitted after the abort terminator, as dead code.

**The class, not the instance:** `control_in` is an optional side-pointer that each
node type must remember to set. Nothing fails loudly when one doesn't. R1.0
(effect-by-default, 2026-07-17) governs *whether* a node is pinned; it says nothing
about whether the chain is *unbroken*. The `Print` here is correctly pinned. The
chain is broken one link on.

The `effect_by_default_call_classification` memory predicted this exact class as
"correctness-of-CONSTRUCTION … not a structural memory edge" and recorded it as not
demonstrated. It is now demonstrated.

## The design

One **world** value, threaded through the graph as an ordinary typed input.

A node's world arity is a property of its class, and the five shapes are exhaustive:

| Shape | World in | World out | Nodes |
|---|---|---|---|
| Source | — | 1 | `Start` |
| Pure | — | — | `Add`, `Constant`, comparisons |
| Effectful | 1 | 1 | `Print`, stores, `Call` (R1.0 default) |
| Terminal | 1 | — | `Unwind`, `Exit`, `Return` |
| Merge | N | 1 | `Phi` |

Pure nodes have **no world edge at all** — they float and CSE exactly as today.
Effectful nodes **cannot be constructed without one**.

### Why this closes the bug by construction

`Unwind` is Terminal: consumes a world, produces none. That is the `throwIO` shape —
typed `IO a`, continuation never runs. The graph becomes `Print(w0) → w1`,
`Unwind(w1)`, and the walk reaches `Print` through a **required typed input**.

There is no "forgot to call `set_control_in`" state to be in, because there is only
one place a predecessor can live. The two encodings collapse.

This is C2's property (`TypeFunc` allocates Control/I_O/Memory slots implicitly for
every call signature — you cannot construct one that omits them) and Graal's
(`FixedWithNextNode` has a successor slot; floating nodes have no such slot at all),
reached through Chalk's own node typing rather than two borrowed conventions.

### What it subsumes

With the world as an ordinary input it enters `content_hash`. So `Print(w0,"a")` and
`Print(w1,"a")` have different hashes **for free**, and the identity registries that
exist to defeat hash-consing stop being necessary rather than being maintained:

- `control_in` → the world edge
- memory-SSA / `MemStart` threading → the world edge
- `%STATEMENT_EFFECT_OPS` (per-call identity for effect nodes) → falls out of hashing
- `%ALLOC_OPS` (added after two `[1,2]` literals shared one malloc) → falls out of hashing

Four mechanisms become one. **This claim is the design's main quantitative promise
and it is not yet measured — see Unverified below.**

### Control is not an effect

Branching is composition structure, not an effect. In monadic terms `if` is a pure
selector `Bool -> M a -> M a -> M a`; the world threads through whichever branch
runs, and the merge is where the threads rejoin. Loops are the same recursively —
the backedge Phi *is* the world threading through iterations.

So CFG structure edges (`If`, `Region`, `Loop`) **stay**, and are not world-carrying.
You cannot express a branch without them, and no system in the prior art merges them
with effect ordering.

**Carve-out — the thing that was mushed together:** control transfers that are
*observable* (`die`, `exit`) ARE effects. They have exit status and stderr. Haskell
agrees: `throwIO` lives in `IO`. So `Unwind` and `Exit` are Terminal-effectful and
take a world input; a branching `If` does not. That distinction is exactly what the
`control_in`-vs-`inputs[0]` split conflated.

### Memory and IO are one world, not two

Applying the ST/IO criterion — separate monads are correct exactly where cross-kind
ordering is never required — all three pairings need ordering here: `$x = 1; print
$x` (store before IO), `print "before"; die` (IO before transfer), and a store must
not float past its guarding branch. So: one monad.

What looks like C2 splitting them is one threaded state that happens to be a tuple.
The load-bearing detail is the asymmetry: I/O reads *produce* a new I/O state and
therefore totally serialize, while memory loads *don't* produce a new STORE and
therefore don't serialize against each other. One mechanism in which reads are
permitted to be non-producing.

That gives the staging. **Start with one opaque world** — coarse, totally ordered,
correct. Refining it so loads stop serializing is a pure optimization *inside* the
same discipline: the taxonomy and the validator are unchanged, only which nodes are
world-producing. Click shipped the coarse version and named slicing as future work.
Correctness > performance says take the same order.

### Merges

A world is an ordinary SSA value, so a merge is an ordinary Phi. Chalk already builds
explicit Phis during parse, including loop backedge Phis, so no new machinery.

Every merge gets a world Phi **unconditionally**, including arms with no effects
(`w1 = w0`). Eliding redundant ones is an optimization, deferred.

### The validator is the guarantee

One checkable invariant over the whole graph: every node's world arity matches its
class. That is the "valid graph going in" property — a gate, not a convention. It is
what makes this construction-correctness rather than a better convention.

## Scope

**In:** the world value; node-class world arity; world Phis at merges; the arity
validator; migrating the **observable-transfer** nodes (`Unwind`, `Exit`) and the
current `control_in` users (`Print`, stores, `Call`, `Return`) onto the world edge.

`If`, `Loop`, `Region` and `Proj` keep their `inputs[0]` control edge and are **not**
migrated — per "Control is not an effect" above, that edge expresses branch
structure, not ordering. The `inputs[0]` convention is not the defect; using it for
an *observable transfer* was.

A `Call` demoted to pure under R1.0's allow-list changes shape from Effectful to
Pure — it loses its world edge entirely and regains CSE. Purity demotion and world
arity are the same decision.

**Out:**

- **Transformation correctness.** The monad laws (associativity of bind = permitted
  re-association; left/right identity = what pure code may be inlined or elided) are
  a legality spec for *passes*. Graph rewriting is not built yet. A guarantee that
  the graph is valid *going in* is the prerequisite, and you cannot verify a rewrite
  preserves an invariant the input never had.
- **World slicing** (non-producing loads, alias classes). Future optimization.
- **Redundant-Phi elision.** Future optimization.

## Known cost

**Over-serialization.** One world totally orders every effect — a print is ordered
against an unrelated store. Accepted: correctness > performance, and the slicing path
above is the documented escape hatch.

In Perl the coarseness is less wrong than it looks. Allocation can run `DESTROY` and
magic, so "allocation is effectful" is defensible here in a way it would not be in
Java — which also explains why `%ALLOC_OPS` had to exist.

## Unverified — resolve before this becomes a plan

1. **The mechanism inventory is reasoning, not measurement.** The audit that would
   confirm what the world token actually replaces died on an account spend limit. The
   "four become one" claim above is the design's main promise and is unmeasured.
2. **Prior-art claims are single-extraction.** The research doc's verification pass
   never ran. The Graal memory-edge claims in particular come from a thesis
   extraction with the ACM paper paywalled.
3. **The 156-case corpus gate is the guard.** Every case is green today under the
   current mechanisms; the world token must hold all 156 across all three legs.

## Testing

- **RED first:** `t/bootstrap/ir/llvm-mainline-die.t` already locks the die
  regression. The executable gate's `die-aborts` program is the product-level RED —
  it must go from DIFF to PASS, raising the gate floor off 0.
- **The arity validator is itself a test surface:** construct an effectful node
  without a world and assert it fails loudly. That is the assertion that the class of
  bug is closed, not just the instance.
- **Corpus gate**, coordinator-run on committed HEAD, floor pinned at 156, all three
  legs (behavior, shape, TypedInvariant).
