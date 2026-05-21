<!-- ABOUTME: Inventory of Chalk's IR-level optimization passes, implemented and planned. -->
<!-- ABOUTME: Links to the Optimizer module sources and the Sea of Nodes IR design document. -->

# Optimization

Chalk's optimization passes operate on the Sea of Nodes IR before code
generation. Because the IR is hash-consed, immutable, and target-agnostic,
a pass is written once and benefits every backend (Perl, XS, C, and future
LLVM IR). Passes live under `lib/Chalk/Bootstrap/Optimizer/`.

For the IR structure passes operate on, see
[`sea-of-nodes-ir.md`](sea-of-nodes-ir.md).

## Pass Interface

The base class `Chalk::Bootstrap::Optimizer::Pass` prescribes two methods:

- `name()` — returns a short string identifying the pass.
- `run($X) -> $X` — takes the input at the pass's scope and returns a
  (possibly rewritten) value of the same shape.

The input shape depends on scope:

- **Method-scope passes** (local rewrites like DCE) take a
  `Chalk::IR::Graph` and return one.
- **Program-scope passes** (whole-program analyses like
  StructPromotion) take a `Chalk::MOP` and return one. The MOP is the
  program-scope container — its classes own per-method graphs that the
  pass can walk via `$method->graph`.

Either way, a pass takes and returns a value of the same type. This
keeps passes composable: the output of one pass is a valid input to
another of the same scope. See [`mop.md`](mop.md) for the MOP layer
and [`sea-of-nodes-ir.md`](sea-of-nodes-ir.md) for the per-method
Graph.

Current reality diverges from this. DCE takes an arrayref of IR root
nodes; StructPromotion takes an arrayref of `{ class_name, ir, ... }`
bundles. These are residue from pre-MOP pass authorship and are
tracked for reconciliation as part of the MOP migration
(see
[`../plans/2026-04-21-chalk-mop-migration-plan.md`](../plans/2026-04-21-chalk-mop-migration-plan.md),
Phase 5).

Passes preserve IR immutability: build new nodes via the `NodeFactory`
rather than mutating existing ones; the hash-cons table automatically
shares equal structure. Deterministic output is required — sort any hash
iteration, use content-addressed node IDs.

## Implemented

### Constant folding (inline)

Constant folding happens at graph construction time via hash consing. A
`BinOp` node whose inputs are both `Constant` nodes is reduced to a
single `Constant` node immediately; subsequent uses of the same constant
value share the folded object. Not a separate pass — an invariant of the
`NodeFactory`.

### Dead code elimination

`Chalk::Bootstrap::Optimizer::DCE` (extends `Optimizer::Pass`) removes
nodes that are unreachable from the graph's roots.

- **Algorithm:** mark-and-sweep. Mark phase walks from the roots and
  their transitive `inputs()` via an iterative worklist, collecting
  reachable node IDs. Sweep phase asks the `NodeFactory` for every
  allocated node ID, subtracts the reachable set, removes each dead
  node from its inputs' `consumers()` lists, and evicts the dead nodes
  from the factory cache.
- **Current I/O shape:** takes an arrayref of IR root nodes, returns
  the same arrayref. The target is `run(Graph) -> Graph` — reshape
  pending with the MOP migration's Phase 5.

### Struct promotion

`Chalk::Bootstrap::Optimizer::StructPromotion` detects hashes with known
key sets and rewrites them to struct-shaped nodes, enabling C-target
optimizations the hash form would prevent. Design:
[`../archive/specs/2026-03-24-struct-promotion-peephole-design.md`](../archive/specs/2026-03-24-struct-promotion-peephole-design.md).

- **Algorithm:** two-pass. `analyze()` collects promotable schemas by
  scanning every method body for hash literal patterns across all
  compiled classes (escape analysis requires whole-program scope).
  `rewrite()` replaces the detected patterns with `StructRef` /
  `StructFieldAccess` nodes. New node types live alongside the regular
  IR taxonomy under `Chalk::IR::Node::`.
- **Current I/O shape:** takes an arrayref of `{ class_name, ir, ... }`
  bundles, returns `($rewritten_classes, $schemas)` in list context.
  Does not subclass `Optimizer::Pass` — the class-bundle input shape
  doesn't fit the base class's single-input-single-output contract.
  The target is `run($mop) -> $mop` (program-scope passes take the
  MOP). Reshape pending with the MOP migration's Phase 5.

## Planned

### Global code motion (GCM)

Cliff Click's GCM algorithm schedules floating data nodes into basic
blocks based on dominance relationships. The `schedule` field on
`Chalk::IR::Graph` is reserved for GCM's output. Not yet implemented;
waits on full SSA construction in `_build_method_graph` (see
[`../plans/2026-04-21-chalk-mop-migration-plan.md`](../plans/2026-04-21-chalk-mop-migration-plan.md),
Phase 3b/3c).

### Ternary lowering

`TernaryExpr` nodes are currently preserved through codegen. A planned
pass would lower them to the canonical `If` + `Proj` + `Region` + `Phi`
pattern, letting downstream optimizations treat them uniformly with
`if`/`else`.

### Peephole passes

Small local rewrites on the graph (simplifying identity operations,
removing redundant control flow, collapsing double negations, etc.).
Loosely scoped; specific passes will be added as patterns surface in the
self-hosting corpus.

### Aycock parser-side optimizations

Not IR-level, but worth noting: Aycock-style optimizations on the Earley
parser itself (Leo optimization, LR(0) DFA prediction, safe-set GC) are
tracked in [`../chalk-ayock-optimizations.md`](../chalk-ayock-optimizations.md)
and are orthogonal to the IR passes listed here.

## Contributing a pass

1. Subclass `Chalk::Bootstrap::Optimizer::Pass`.
2. Implement `name()` returning a short string identifier.
3. Implement `run($X) -> $X` where `$X` is `Chalk::IR::Graph` for
   method-scope passes or `Chalk::MOP` for program-scope passes.
   Interim workarounds in existing passes (root arrayrefs,
   class-bundle hashes) are accepted but new passes should not add
   to the reshape debt.
4. Preserve immutability: build new nodes via the factory, don't mutate
   existing ones.
5. Be deterministic: sort hash iteration, use content-addressed IDs.
6. Add tests under `t/bootstrap/optimizer-*.t`.

`lib/Chalk/Bootstrap/Optimizer/DCE.pm` is the closest current example;
its root-arrayref I/O shape is residue to be reconciled.
`lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` shows a
program-scope pass and the class-bundle workaround it uses pending
the MOP-input migration.
