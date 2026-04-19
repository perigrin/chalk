<!-- ABOUTME: Inventory of Chalk's IR-level optimization passes, implemented and planned. -->
<!-- ABOUTME: Links to the Optimizer module sources and the Sea of Nodes IR design document. -->

# Optimization

Chalk's optimization passes operate on the Sea of Nodes IR before code
generation. Because the IR is hash-consed, immutable, and target-agnostic,
optimization passes are written once and benefit every backend (Perl, XS,
C, and future LLVM IR). Passes live under `lib/Chalk/Bootstrap/Optimizer/`
and extend the `Chalk::Bootstrap::Optimizer::Pass` base class.

For the IR structure passes operate on, see
[`sea-of-nodes-ir.md`](sea-of-nodes-ir.md).

## Implemented

### Constant folding (inline)

Constant folding happens at graph construction time via hash consing. A
`BinOp` node whose inputs are both `Constant` nodes is reduced to a
single `Constant` node immediately; subsequent uses of the same constant
value share the folded object. Not a separate pass — an invariant of the
factory.

### Dead code elimination

`Chalk::Bootstrap::Optimizer::DCE` removes nodes with no consumers.
Relies on the IR's bidirectional use-def chains: a node whose
`consumers()` set is empty and that is not a control-flow terminator is
unreachable and can be pruned.

### Struct promotion

`Chalk::Bootstrap::Optimizer::StructPromotion` rewrites hash-backed
object-like constructs into explicit `StructRef` / `StructFieldAccess`
nodes for the struct promotion design described in
[`../superpowers/specs/2026-03-24-struct-promotion-peephole-design.md`](../superpowers/specs/2026-03-24-struct-promotion-peephole-design.md).
Runs after IR construction, before target emission. New node types
(`StructRef`, `StructFieldAccess`) live alongside the regular IR
taxonomy.

## Planned

### Global code motion (GCM)

Cliff Click's GCM algorithm schedules floating data nodes into basic
blocks based on dominance relationships. The `schedule` field on
`Chalk::IR::Graph` is reserved for GCM's output. Not yet implemented;
waits on full SSA construction in `_build_method_graph` (see
[`../plans/2026-04-04-son-ir-polymorphic-migration.md`](../plans/2026-04-04-son-ir-polymorphic-migration.md)).

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

New passes should:

- Subclass `Chalk::Bootstrap::Optimizer::Pass`
- Operate on a `Chalk::IR::Graph` and return a (possibly new) `Graph`
- Preserve immutability: build new nodes rather than mutating existing
  ones; the hash-cons table will share equal structure automatically
- Be deterministic: sort any hash iteration, use content-addressed IDs
- Add tests under `t/bootstrap/optimizer-*.t`

See `lib/Chalk/Bootstrap/Optimizer/DCE.pm` for a minimal example and
`lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` for a pass with new
node types.
